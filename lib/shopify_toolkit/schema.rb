# frozen_string_literal: true

require "stringio"
require "shopify_api"
require "rails"
require "active_support/core_ext/module/delegation"

module ShopifyToolkit::Schema
  extend self
  include ShopifyToolkit::MetafieldStatements
  include ShopifyToolkit::Migration::Logging

  delegate :logger, to: Rails

  SCHEMA_PATH = "config/shopify/schema.rb"
  # https://shopify.dev/docs/api/admin-graphql/2024-10/enums/MetafieldOwnerType
  OWNER_TYPES = %i[
    api_permissions
    articles
    blogs
    carttransforms
    collections
    companies
    company_locations
    customers
    delivery_customizations
    discounts
    draftorders
    fulfillment_constraint_rules
    gift_card_transactions
    locations
    markets
    orders
    order_routing_location_rules
    pages
    payment_customizations
    products
    productvariants
    selling_plans
    shops
    validations
  ].freeze

  def load!
    path = Rails.root.join(SCHEMA_PATH)

    unless path.exist?
      logger.warn "Schema file not found at #{path}."
      return
    end

    announce "Loading metafield schema from #{path}"
    say_with_time "Executing schema statements" do
      load path
    end
  end

  def dump!
    schema_path = Rails.root.join(SCHEMA_PATH)

    announce "Dumping metafield schema to #{schema_path}"
    say_with_time "Generating schema" do
      content = generate_schema_content
      File.write(schema_path, content)
    end
  end

  def define(&block)
    instance_eval(&block)
  end

  def fetch_definitions(owner_type:)
    owner_type = owner_type.to_s.singularize.upcase

    query = <<~GRAPHQL
      query {
        metafieldDefinitions(first: 250, ownerType: #{owner_type}) {
          nodes {
            id
            name
            key
            type {
              name
            }
            namespace
            description
            validations {
              name
              value
            }
            capabilities {
              smartCollectionCondition {
                enabled
              }
              adminFilterable {
                enabled
              }
            }
            access {
              admin
              customerAccount
              storefront
            }
            ownerType
          }
        }
      }
    GRAPHQL

    result =
      shopify_admin_client
        .query(query:)
        .tap { handle_shopify_admin_client_errors(_1) }
        .body

    result.dig("data", "metafieldDefinitions", "nodes") || []
  end

  def generate_schema_content
    definitions =
      OWNER_TYPES.flat_map { |owner_type| fetch_definitions(owner_type:) }

    content = StringIO.new
    content << <<~RUBY
      # This file is auto-generated from the current state of the Shopify metafields.
      # Instead of editing this file, please use the metafields migration feature of ShopifyToolkit
      # to incrementally modify your metafields, and then regenerate this schema definition.
      #
      # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
      #
      # It's strongly recommended that you check this file into your version control system.
      ShopifyToolkit::Schema.define do
    RUBY

    # Sort for consistent output
    definitions
      .sort_by { [_1["ownerType"], _1["namespace"], _1["key"]] }
      .each do
        owner_type = _1["ownerType"].downcase.pluralize.to_sym
        key = _1["key"].to_sym
        type = _1["type"]["name"].to_sym
        name = _1["name"]
        namespace = _1["namespace"]&.to_sym
        description = _1["description"]
        validations = _1["validations"]&.map { |v| v.transform_keys(&:to_sym) }
        capabilities =
          _1["capabilities"]
            &.transform_keys(&:to_sym)
            &.transform_values { |v| v.transform_keys(&:to_sym) }

        args = [owner_type, key, type]
        kwargs = { name: name }
        kwargs[:namespace] = namespace if namespace && namespace != :custom
        kwargs[:description] = description if description
        kwargs[:validations] = validations if validations.present?

        # Only include capabilities if they have non-default values
        if capabilities.present?
          has_non_default_capabilities =
            capabilities.any? do |cap, value|
              case cap
              when :smartCollectionCondition, :adminFilterable
                value[:enabled] == true
              else
                true
              end
            end
          kwargs[:capabilities] = capabilities if has_non_default_capabilities
        end

        args_string = args.map(&:inspect).join(", ")
        kwargs_string = kwargs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        content.puts "  create_metafield #{args_string}, #{kwargs_string}"
      end

    content.puts "end"
    content.string
  end
end
