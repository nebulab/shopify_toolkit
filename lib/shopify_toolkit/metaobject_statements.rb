# frozen_string_literal: true

require "active_support/concern"

module ShopifyToolkit::MetaobjectStatements
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
  def create_metaobject_definition(type, **options)
    # Skip creation if metafield already exists
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

  def get_metaobject_definition_gid(type)
    result =
      shopify_admin_client
        .query(
          query:
            "# GraphQL
              query GetMetaobjectDefinitionID($type: String!) {
                metaobjectDefinitionByType(type: $type) {
                  id
                }
              }",
          variables: { type: type.to_s },
        )
        .tap { handle_shopify_admin_client_errors(_1) }
        .body

    result.dig("data", "metaobjectDefinitionByType", "id")
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

  log_time \
  def delete_metaobject_definition(type)
    existing_gid = get_metaobject_definition_gid(type)

    unless existing_gid
      say "Metaobject #{type} does not exist, skipping deletion"
      return
    end

    # https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metaobjectDefinitionDelete
    query =
      "# GraphQL
      mutation DeleteMetaobjectDefinition($id: ID!) {
        metaobjectDefinitionDelete(id: $id) {
          deletedId
          userErrors {
            field
            message
            code
          }
        }
      }
      "
    variables = { id: existing_gid }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectDefinitionDelete.userErrors") }
  end

  log_time \
  def create_metaobject(type, handle: nil, fields: [], **options)
    # Check if metaobject definition exists
    unless get_metaobject_definition_gid(type)
      raise "Metaobject definition #{type} does not exist. Create it first."
    end

    # Skip creation if metaobject with handle already exists
    if handle && find_metaobject(type, handle)
      say "Metaobject #{type} with handle '#{handle}' already exists, skipping creation"
      return find_metaobject(type, handle)
    end

    # https://shopify.dev/docs/api/admin-graphql/latest/mutations/metaobjectCreate
    query =
      "# GraphQL
      mutation CreateMetaobject($metaobject: MetaobjectCreateInput!) {
        metaobjectCreate(metaobject: $metaobject) {
          metaobject {
            id
            handle
            type
            displayName
            fields {
              key
              value
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
    
    metaobject_input = { type: type.to_s, **options }
    metaobject_input[:handle] = handle if handle
    metaobject_input[:fields] = fields.map { |field| { key: field[:key].to_s, value: field[:value].to_s } } if fields.any?
    
    variables = { metaobject: metaobject_input }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectCreate.userErrors") }
  end

  def find_metaobject(type, handle)
    # https://shopify.dev/docs/api/admin-graphql/latest/queries/metaobject
    query =
      "# GraphQL
      query FindMetaobject($type: String!, $handle: String!) {
        metaobject(type: $type, handle: $handle) {
          id
          handle
          type
          displayName
          fields {
            key
            value
          }
        }
      }
      "
    variables = { type: type.to_s, handle: handle.to_s }

    result = shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1) }
      .body

    result.dig("data", "metaobject")
  end

  def find_metaobjects(type, first: 50, query: nil, sort_key: "id", reverse: false)
    # https://shopify.dev/docs/api/admin-graphql/latest/queries/metaobjects
    graphql_query =
      "# GraphQL
      query FindMetaobjects($type: String!, $first: Int, $query: String, $sortKey: String, $reverse: Boolean) {
        metaobjects(type: $type, first: $first, query: $query, sortKey: $sortKey, reverse: $reverse) {
          nodes {
            id
            handle
            type
            displayName
            fields {
              key
              value
            }
          }
          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
      "
    variables = { 
      type: type.to_s, 
      first: first, 
      sortKey: sort_key, 
      reverse: reverse 
    }
    variables[:query] = query if query

    result = shopify_admin_client
      .query(query: graphql_query, variables:)
      .tap { handle_shopify_admin_client_errors(_1) }
      .body

    result.dig("data", "metaobjects")
  end

  log_time \
  def update_metaobject(type, handle_or_id, fields: [], **options)
    # Find the metaobject to get its ID
    metaobject = if handle_or_id.start_with?("gid://")
      # Already a GID
      { "id" => handle_or_id }
    else
      # It's a handle, find by handle
      find_metaobject(type, handle_or_id)
    end

    unless metaobject
      say "Metaobject #{type} with identifier '#{handle_or_id}' not found, skipping update"
      return
    end

    # https://shopify.dev/docs/api/admin-graphql/latest/mutations/metaobjectUpdate
    query =
      "# GraphQL
      mutation UpdateMetaobject($id: ID!, $metaobject: MetaobjectUpdateInput!) {
        metaobjectUpdate(id: $id, metaobject: $metaobject) {
          metaobject {
            id
            handle
            type
            displayName
            fields {
              key
              value
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
    
    metaobject_input = options.dup
    metaobject_input[:fields] = fields.map { |field| { key: field[:key].to_s, value: field[:value].to_s } } if fields.any?
    
    variables = { id: metaobject["id"], metaobject: metaobject_input }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectUpdate.userErrors") }
  end

  log_time \
  def delete_metaobject(type, handle_or_id)
    # Find the metaobject to get its ID
    metaobject = if handle_or_id.start_with?("gid://")
      # Already a GID
      { "id" => handle_or_id }
    else
      # It's a handle, find by handle
      find_metaobject(type, handle_or_id)
    end

    unless metaobject
      say "Metaobject #{type} with identifier '#{handle_or_id}' not found, skipping deletion"
      return
    end

    # https://shopify.dev/docs/api/admin-graphql/latest/mutations/metaobjectDelete
    query =
      "# GraphQL
      mutation DeleteMetaobject($id: ID!) {
        metaobjectDelete(id: $id) {
          deletedId
          userErrors {
            field
            message
            code
          }
        }
      }
      "
    variables = { id: metaobject["id"] }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectDelete.userErrors") }
  end

  def self.define(&block)
    context = Object.new
    context.extend(self)

    context.instance_eval(&block) if block_given?(&block)
    context
  end
end
