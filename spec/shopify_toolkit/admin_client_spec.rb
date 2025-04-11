# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require "logger"

RSpec.describe ShopifyToolkit::AdminClient do
  let(:client) { build_client }

  def build_response(code: 200, body: {})
    OpenStruct.new(code: code, body: body)
  end

  # Helper class that includes the module
  def build_client
    Class.new do
      include ShopifyToolkit::AdminClient

      def logger
        @logger ||= Logger.new(nil)
      end
    end.new
  end

  describe "#handle_shopify_admin_client_errors" do
    it "raises an error when response code is not 200" do
      response = build_response(code: 500, body: { "data" => {} })

      expect {
        client.handle_shopify_admin_client_errors(response)
      }.to raise_error(RuntimeError, /Error querying Shopify Admin API:.*code=500/)
    end

    it "raises an error when response contains top-level errors" do
      response = build_response(body: { "errors" => [{ "message" => "Something went wrong" }] })

      expect {
        client.handle_shopify_admin_client_errors(response)
      }.to raise_error(RuntimeError, /Error querying Shopify Admin API:.*message.*Something went wrong/)
    end

    it "raises an error when response contains user errors at specified path" do
      response = build_response(body: {
        "data" => {
          "productCreate" => {
            "userErrors" => [{ "message" => "Invalid input" }]
          }
        }
      })

      expect {
        client.handle_shopify_admin_client_errors(response, "data.productCreate.userErrors")
      }.to raise_error(RuntimeError, /Error querying Shopify Admin API:.*message.*Invalid input.*data\.productCreate\.userErrors/)
    end

    it "does not raise errors when response is successful and has no errors" do
      response = build_response(body: { "data" => { "product" => { "id" => "1" } } })

      expect {
        client.handle_shopify_admin_client_errors(response, "data.product.userErrors")
      }.not_to raise_error
    end
  end
end
