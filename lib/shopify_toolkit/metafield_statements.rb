# frozen_string_literal: true

require "shopify_toolkit/migration/logging"
require "shopify_toolkit/admin_client"
require "active_support/concern"

module ShopifyToolkit::MetafieldStatements
  extend ActiveSupport::Concern
  include ShopifyToolkit::Migration::Logging
  include ShopifyToolkit::AdminClient

  def self.log_time(method_name)
    current_method = instance_method(method_name)
    define_method(method_name) do |*args, **kwargs, &block|
      say_with_time("#{method_name}(#{args.map(&:inspect).join(', ')})") { current_method.bind(self).call(*args, **kwargs, &block) }
    end
  end

  # create_metafield :products, :my_metafield, :single_line_text_field, name: "Prova"
  # @param namespace: if nil the metafield will be app-specific (default: :custom)
  log_time \
  def create_metafield(owner_type, key, type, namespace: :custom, name:, **options)
    ownerType = owner_type.to_s.singularize.upcase # Eg. "PRODUCT"

    # https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metafieldDefinitionCreate
    query =
      "# GraphQL
        mutation CreateMetafieldDefinition($definition: MetafieldDefinitionInput!) {
          metafieldDefinitionCreate(definition: $definition) {
            createdDefinition {
              id
              key
            }
            userErrors {
              field
              message
              code
            }
          }
        }
      "
    variables = { definition: { ownerType:, key:, type:, name:, namespace:, **options } }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "metafieldDefinitionCreate.userErrors") }
  end

  def get_metafield_gid(owner_type, key, namespace: :custom)
    ownerType = owner_type.to_s.singularize.upcase # Eg. "PRODUCT"

    result =
      shopify_admin_client
        .query(
          query:
            "# GraphQL
              query FindMetafieldDefinition($ownerType: MetafieldOwnerType!, $key: String!) {
                metafieldDefinitions(first: 1, ownerType: $ownerType, key: $key) {
                  nodes { id }
                }
              }",
          variables: {
            ownerType:,
            key:,
            namespace:,
          },
        )
        .tap { handle_shopify_admin_client_errors(_1) }
        .body

    result.dig("data", "metafieldDefinitions", "nodes", 0, "id") or
      raise "Metafield not found for #{owner_type}##{namespace}:#{key}"
  end

  log_time \
  def remove_metafield(owner_type, key, namespace: :custom, delete_associated_metafields: false, **options)
    if namespace == nil && delete_associated_metafields == false
      raise ArgumentError,
            "For reserved namespaces, you must delete all associated metafields (delete_associated_metafields: true)"
    end

    shopify_admin_client
      .query(
        # Documentation: https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metafieldDefinitionDelete
        query:
          "# GraphQL
            mutation DeleteMetafieldDefinition($id: ID!, $deleteAllAssociatedMetafields: Boolean!) {
              metafieldDefinitionDelete(id: $id, deleteAllAssociatedMetafields: $deleteAllAssociatedMetafields) {
                deletedDefinitionId
                userErrors {
                  field
                  message
                  code
                }
              }
            }",
        variables: {
          id: get_metafield_gid(owner_type, key, namespace: namespace),
          deleteAllAssociatedMetafields: delete_associated_metafields,
        },
      )
      .tap { handle_shopify_admin_client_errors(_1, "metafieldDefinitionDelete.userErrors") }
  end

  log_time \
  def update_metafield(owner_type, key, namespace: :custom, **options)
    shopify_admin_client
      .query(
        # Documentation: https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metafieldDefinitionUpdate
        query:
          "# GraphQL
            mutation UpdateMetafieldDefinition($definition: MetafieldDefinitionUpdateInput!) {
              metafieldDefinitionUpdate(definition: $definition) {
                updatedDefinition {
                  id
                  name
                }
                userErrors {
                  field
                  message
                  code
                }
              }
            }",
        variables: {
          definition: {
            ownerType: owner_type.to_s.singularize.upcase,
            key:,
            namespace:,
            **options,
          },
        },
      )
      .tap { handle_shopify_admin_client_errors(_1, "metafieldDefinitionUpdate.userErrors") }
  end

  def self.define(&block)
    context = Object.new
    context.extend(self)

    context.instance_eval(&block) if block_given?(&block)
    context
  end
end
