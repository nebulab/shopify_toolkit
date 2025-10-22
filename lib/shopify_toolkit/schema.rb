# frozen_string_literal: true

require "stringio"
require "shopify_api"
require "rails"
require "active_support/core_ext/module/delegation"

module ShopifyToolkit::Schema
  extend self
  include ShopifyToolkit::MetafieldStatements
  include ShopifyToolkit::MetaobjectStatements
  include ShopifyToolkit::MetaobjectUtilities
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

    # Parse the schema file to separate metaobject and metafield definitions
    schema_content = File.read(path)

    say_with_time "Executing metaobject definitions" do
      # Execute only metaobject definitions first
      execute_metaobject_definitions(schema_content)
    end

    say_with_time "Executing metafield definitions" do
      # Execute only metafield definitions after all metaobjects exist
      execute_metafield_definitions(schema_content)
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

  def convert_validations_gids_to_types(validations, metafield_type)
    return validations unless validations&.any? && is_metaobject_reference_type?(metafield_type)

    validations.filter_map do |validation|
      convert_metaobject_validation_to_type(validation)
    end
  end

  private

  def convert_metaobject_validation_to_type(validation)
    name = validation["name"]
    value = validation["value"]

    return validation unless metaobject_gid_validation?(name)

    parsed_value = parse_json_if_needed(value)
    convert_gids_to_types(validation, parsed_value)
  end

  def metaobject_gid_validation?(name)
    name.in?(["metaobject_definition_id", "metaobject_definition_ids"])
  end

  def convert_gids_to_types(validation, value)
    if value.is_a?(Array)
      convert_array_gids_to_types(validation, value)
    else
      convert_single_gid_to_type(validation, value)
    end
  end

  def convert_array_gids_to_types(validation, gids)
    types = gids.filter_map { |gid| convert_gid_to_type_if_valid(gid) }

    return nil unless types.any?

    validation.merge("name" => "metaobject_definition_types", "value" => types)
  end

  def convert_single_gid_to_type(validation, gid)
    type = convert_gid_to_type_if_valid(gid)

    return nil unless type

    validation.merge("name" => "metaobject_definition_type", "value" => type)
  end

  def convert_gid_to_type_if_valid(gid)
    return gid unless gid&.start_with?("gid://shopify/MetaobjectDefinition/")

    type = get_metaobject_definition_type_by_gid(gid)

    if type.nil?
      say "Warning: Metafield validation references unknown metaobject GID #{gid} - excluding from portable schema"
    end

    type
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

  def fetch_metaobject_definitions
    query = <<~GRAPHQL
      query {
        metaobjectDefinitions(first: 250) {
          nodes {
            id
            type
            name
            description
            fieldDefinitions {
              key
              name
              description
              type {
                name
              }
              required
              validations {
                name
                value
              }
            }
            access {
              admin
              storefront
            }
            capabilities {
              publishable {
                enabled
              }
              translatable {
                enabled
              }
            }
          }
        }
      }
    GRAPHQL

    result =
      shopify_admin_client
        .query(query:)
        .tap { handle_shopify_admin_client_errors(_1) }
        .body

    result.dig("data", "metaobjectDefinitions", "nodes") || []
  end

  def generate_schema_content
    metaobject_definitions = fetch_metaobject_definitions
    metafield_definitions =
      OWNER_TYPES.flat_map { |owner_type| fetch_definitions(owner_type:) }

    content = StringIO.new
    content << <<~RUBY
      # This file is auto-generated from the current state of the Shopify metafields and metaobjects.
      # Instead of editing this file, please use the migration features of ShopifyToolkit
      # to incrementally modify your metafields and metaobjects, and then regenerate this schema definition.
      #
      # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
      #
      # It's strongly recommended that you check this file into your version control system.
      ShopifyToolkit::Schema.define do
    RUBY

    # Add metaobject definitions first
    metaobject_definitions
      .sort_by { _1["type"] }
      .each do |definition|
        type = definition["type"]
        name = definition["name"]
        description = definition["description"]

        field_definitions = definition["fieldDefinitions"]&.map do |field|
          field_hash = {
            key: field["key"].to_sym,
            type: field["type"]["name"].to_sym,
            name: field["name"]
          }
          field_hash[:description] = field["description"] if field["description"] && !field["description"].empty?
          field_hash[:required] = field["required"] if field["required"] == true

          # Convert validations for metaobject reference fields within metaobjects
          if field["validations"]&.any? && is_metaobject_reference_type?(field["type"]["name"])
            field_hash[:validations] = convert_validations_gids_to_types(field["validations"], field["type"]["name"])&.map { |v| v.transform_keys(&:to_sym) }
          elsif field["validations"]&.any?
            field_hash[:validations] = field["validations"]&.map { |v| v.transform_keys(&:to_sym) }
          end

          field_hash
        end

        access = definition["access"]
        capabilities = definition["capabilities"]

        args = [type.to_sym]
        kwargs = { name: name }
        kwargs[:description] = description if description && !description.empty?
        kwargs[:field_definitions] = field_definitions if field_definitions&.any?
        kwargs[:access] = access if access&.any?

        # Add capabilities if non-default
        if capabilities&.any? { |_, v| v["enabled"] == true }
          kwargs[:capabilities] = capabilities.transform_keys(&:to_sym).transform_values { |v| v.transform_keys(&:to_sym) }
        end

        args_string = args.map(&:inspect).join(", ")
        kwargs_string = kwargs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        content.puts "  create_metaobject_definition #{args_string}, #{kwargs_string}"
      end

    # Add blank line between metaobjects and metafields if both exist
    if metaobject_definitions.any? && metafield_definitions.any?
      content.puts ""
    end

    # Add metafield definitions
    metafield_definitions
      .sort_by { [_1["ownerType"], _1["namespace"], _1["key"]] }
      .each do
        owner_type = _1["ownerType"].downcase.pluralize.to_sym
        key = _1["key"].to_sym
        type = _1["type"]["name"].to_sym
        name = _1["name"]
        namespace = _1["namespace"]&.to_sym
        description = _1["description"]
        validations = convert_validations_gids_to_types(_1["validations"], type)&.map { |v| v.transform_keys(&:to_sym) }
        capabilities =
          _1["capabilities"]
            &.transform_keys(&:to_sym)
            &.transform_values { |v| v.transform_keys(&:to_sym) }

        args = [owner_type, key, type]
        kwargs = { name: name }
        kwargs[:namespace] = namespace if namespace && namespace != :custom
        kwargs[:description] = description if description
        kwargs[:validations] = validations if validations&.any?

        # Only include capabilities if they have non-default values
        if capabilities&.any?
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

  def execute_metaobject_definitions(schema_content)
    # Create a filtered version that only includes metaobject definitions
    metaobject_content = filter_schema_content(schema_content, :metaobject)
    eval_schema_content(metaobject_content)
  end

  def execute_metafield_definitions(schema_content)
    # Create a filtered version that only includes metafield definitions
    metafield_content = filter_schema_content(schema_content, :metafield)
    eval_schema_content(metafield_content)
  end

  def filter_schema_content(schema_content, type)
    lines = schema_content.lines
    filtered_lines = []

    # Always include the header and footer
    filtered_lines << lines.first(8) # Header lines up to "ShopifyToolkit::Schema.define do"
    filtered_lines.flatten!

    lines.each do |line|
      case type
      when :metaobject
        if line.strip.start_with?("create_metaobject_definition")
          filtered_lines << line
        end
      when :metafield
        filtered_lines << line if line.strip.start_with?("create_metafield")
      end
    end

    filtered_lines << "end\n" # Closing line
    filtered_lines.join
  end

  def eval_schema_content(content)
    instance_eval(content)
  end
end
