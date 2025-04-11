module ShopifyToolkit::Schema
  extend self
  include ShopifyToolkit::MetafieldStatements
  include ShopifyToolkit::Migration::Logging
  SCHEMA_PATH = "config/shopify/schema.rb"

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

  def fetch_definitions
    query = <<~GRAPHQL
      query {
        metafieldDefinitions(first: 250, ownerType: PRODUCT) {
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

    result = shopify_admin_client.query(query:).tap { handle_shopify_admin_client_errors(_1) }.body

    result.dig("data", "metafieldDefinitions", "nodes") || []
  end

  def generate_schema_content
    definitions = fetch_definitions
    content = ["ShopifyToolkit::Schema.define do"]

    definitions.each do |defn|
      owner_type = defn["ownerType"].downcase.pluralize.to_sym
      key = defn["key"].to_sym
      type = defn["type"]["name"].to_sym
      name = defn["name"]
      namespace = defn["namespace"]&.to_sym
      description = defn["description"]
      validations = defn["validations"]&.map { |v| v.transform_keys(&:to_sym) }
      capabilities = defn["capabilities"]&.transform_keys(&:to_sym)&.transform_values { |v| v.transform_keys(&:to_sym) }

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

      content << "  create_metafield #{args.map(&:inspect).join(", ")}, #{kwargs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")}"
    end

    content << "end"
    content.join("\n")
  end
end
