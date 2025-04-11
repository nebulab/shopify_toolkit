# frozen_string_literal: true

require "spec_helper"
require "logger"
require "active_support/concern"
require "active_support/core_ext/string"
require "ostruct"
require "shopify_toolkit/migration/logging"

RSpec.describe ShopifyToolkit::MetafieldStatements do
  def build_client
    Class.new do
      include ShopifyToolkit::Migration::Logging
      include ShopifyToolkit::MetafieldStatements

      def logger
        @logger ||= Logger.new(nil)
      end

      def shopify_admin_client
        @shopify_admin_client ||= instance_double(ShopifyAPI::Clients::Graphql::Admin)
      end

      def say_with_time(message)
        yield
      end
    end.new
  end

  def build_response(code: 200, body: {})
    OpenStruct.new(code: code, body: body)
  end

  let(:client) { build_client }

  describe "#create_metafield" do
    it "transforms owner_type correctly and checks for errors" do
      response = build_response(body: {
        "data" => {
          "metafieldDefinitionCreate" => {
            "createdDefinition" => { "id" => "123", "key" => "test_key" }
          }
        }
      })

      expect(client.shopify_admin_client).to receive(:query) do |params|
        expect(params[:variables]).to eq(
          definition: {
            ownerType: "PRODUCT",
            key: :test_key,
            type: :single_line_text_field,
            name: "Test Field",
            namespace: :custom
          }
        )
        response
      end

      expect(client).to receive(:handle_shopify_admin_client_errors)
        .with(response, "metafieldDefinitionCreate.userErrors")

      client.create_metafield(
        :products,
        :test_key,
        :single_line_text_field,
        name: "Test Field"
      )
    end
  end

  describe "#get_metafield_gid" do
    it "transforms owner_type correctly and checks for errors" do
      response = build_response(body: {
        "data" => {
          "metafieldDefinitions" => {
            "nodes" => [{ "id" => "gid://shopify/MetafieldDefinition/123" }]
          }
        }
      })

      expect(client.shopify_admin_client).to receive(:query) do |params|
        expect(params[:variables]).to eq(
          ownerType: "PRODUCT",
          key: :test_key,
          namespace: :custom
        )
        response
      end

      expect(client).to receive(:handle_shopify_admin_client_errors)
        .with(response)

      result = client.get_metafield_gid(:products, :test_key)
      expect(result).to eq("gid://shopify/MetafieldDefinition/123")
    end

    it "raises error when metafield is not found" do
      response = build_response(body: { "data" => { "metafieldDefinitions" => { "nodes" => [] } } })

      allow(client.shopify_admin_client).to receive(:query).and_return(response)
      allow(client).to receive(:handle_shopify_admin_client_errors)

      expect {
        client.get_metafield_gid(:products, :test_key)
      }.to raise_error("Metafield not found for products#custom:test_key")
    end
  end

  describe "#remove_metafield" do
    it "checks for errors and requires delete_associated_metafields for nil namespace" do
      expect {
        client.remove_metafield(:products, :test_key, namespace: nil)
      }.to raise_error(ArgumentError, /must delete all associated metafields/)

      response = build_response(body: {
        "data" => {
          "metafieldDefinitionDelete" => {
            "deletedDefinitionId" => "123"
          }
        }
      })

      allow(client).to receive(:get_metafield_gid)
        .with(:products, :test_key, namespace: nil)
        .and_return("gid://shopify/MetafieldDefinition/123")

      expect(client.shopify_admin_client).to receive(:query) do |params|
        expect(params[:variables]).to eq(
          id: "gid://shopify/MetafieldDefinition/123",
          deleteAllAssociatedMetafields: true
        )
        response
      end

      expect(client).to receive(:handle_shopify_admin_client_errors)
        .with(response, "metafieldDefinitionDelete.userErrors")

      client.remove_metafield(:products, :test_key, namespace: nil, delete_associated_metafields: true)
    end
  end

  describe "#update_metafield" do
    it "transforms owner_type correctly and checks for errors" do
      response = build_response(body: {
        "data" => {
          "metafieldDefinitionUpdate" => {
            "updatedDefinition" => { "id" => "123", "name" => "Updated Field" }
          }
        }
      })

      expect(client.shopify_admin_client).to receive(:query) do |params|
        expect(params[:variables]).to eq(
          definition: {
            ownerType: "PRODUCT",
            key: :test_key,
            namespace: :custom,
            name: "Updated Field"
          }
        )
        response
      end

      expect(client).to receive(:handle_shopify_admin_client_errors)
        .with(response, "metafieldDefinitionUpdate.userErrors")

      client.update_metafield(
        :products,
        :test_key,
        name: "Updated Field"
      )
    end
  end
end
