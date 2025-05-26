require "shopify_api"

module ShopifyToolkit::AdminClient
  API_VERSION = "2024-10"

  def api_version
    API_VERSION
  end

  def shopify_admin_client
    @shopify_admin_client ||=
      ShopifyAPI::Clients::Graphql::Admin.new(session: ShopifyAPI::Context.active_session, api_version:)
  end

  def handle_shopify_admin_client_errors(response, *user_error_paths)
    if response.code != 200
      logger.error "Error querying Shopify Admin API: #{response.inspect}"
      raise "Error querying Shopify Admin API: #{response.inspect}"
    end

    response
      .body
      .dig("errors")
      .to_a
      .each do |error|
        logger.error "Error querying Shopify Admin API: #{error.inspect}"
        raise "Error querying Shopify Admin API: #{error.inspect}"
      end

    user_error_paths.each do |path|
      response
        .body
        .dig(*path.split("."))
        .to_a
        .each do |error|
          logger.error "Error querying Shopify Admin API: #{error.inspect} (#{path})"
          raise "Error querying Shopify Admin API: #{error.inspect} (#{path})"
        end
    end
  end
end
