# frozen_string_literal: true

require "active_support/concern"

module ShopifyToolkit::MetaobjectStatements
  extend ActiveSupport::Concern
  include ShopifyToolkit::Migration::Logging
  include ShopifyToolkit::AdminClient
  include ShopifyToolkit::MetaobjectUtilities

  def self.log_time(method_name)
    current_method = instance_method(method_name)
    define_method(method_name) do |*args, **kwargs, &block|
      say_with_time("#{method_name}(#{args.map(&:inspect).join(', ')})") { current_method.bind(self).call(*args, **kwargs, &block) }
    end
  end

  # create_metafield :products, :my_metafield, :single_line_text_field, name: "Prova"
  # @param namespace: if nil the metafield will be app-specific (default: :custom)
  log_time \
  def create_metaobject_definition(type, **options)
    # Skip creation if metaobject already exists
    existing_gid = get_metaobject_definition_gid(type)
    if existing_gid
      say "Metaobject #{type} already exists, skipping creation"
      return existing_gid
    end

    # https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metafieldDefinitionCreate
    query =
      "# GraphQL
      mutation CreateMetaobjectDefinition($definition: MetaobjectDefinitionCreateInput!) {
        metaobjectDefinitionCreate(definition: $definition) {
          metaobjectDefinition {
            id
            name
            type
            fieldDefinitions {
              name
              key
            }
          }
          userErrors {
            field
            message
            code
          }
        }
      }
      "
    variables = { definition: { type:, **options } }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectDefinitionCreate.userErrors") }
  end

  def update_metaobject_definition(type, **options)
    existing_gid = get_metaobject_definition_gid(type)

    raise "Metaobject #{type} does not exist" unless existing_gid

    # https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metaobjectDefinitionUpdate
    query =
      "# GraphQL
      mutation UpdateMetaobjectDefinition($id: ID!, $definition: MetaobjectDefinitionUpdateInput!) {
        metaobjectDefinitionUpdate(id: $id, definition: $definition) {
          metaobjectDefinition {
            id
            name
            type
            fieldDefinitions {
              name
              key
            }
          }
          userErrors {
            field
            message
            code
          }
        }
      }
    "
    variables = { id: existing_gid, definition: { **options } }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectDefinitionUpdate.userErrors") }
  end

  def self.define(&block)
    context = Object.new
    context.extend(self)

    context.instance_eval(&block) if block_given?(&block)
    context
  end
end
