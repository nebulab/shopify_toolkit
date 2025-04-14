# frozen_string_literal: true

require "spec_helper"

RSpec.describe ShopifyToolkit::Schema do
  let(:schema) { described_class }
  let(:shopify_admin_client) { instance_double(ShopifyAPI::Clients::Graphql::Admin) }
  let(:root) { Pathname(Dir.mktmpdir) }

  before do
    allow(ShopifyAPI::Clients::Graphql::Admin).to receive(:new).and_return(shopify_admin_client)
    allow(Rails).to receive(:root).and_return(root)
    root.join("config/shopify").mkpath
  end

  describe "#dump!" do
    it "dumps the schema to a file" do
      allow(shopify_admin_client).to receive(:query).and_return(
        OpenStruct.new(
          code: 200,
          body: {
            "data" => {
              "metafieldDefinitions" => {
                "nodes" => [
                  {
                    "id" => "gid://shopify/MetafieldDefinition/1",
                    "name" => "My Metafield",
                    "key" => "my_metafield",
                    "type" => { "name" => "single_line_text_field" },
                    "namespace" => "custom",
                    "description" => "My description",
                    "validations" => [{ "name" => "min_length", "value" => "1" }, { "name" => "max_length", "value" => "10" }],
                    "capabilities" => {
                      "smartCollectionCondition" => { "enabled" => true },
                      "adminFilterable" => { "enabled" => false },
                    },
                    "access" => { "admin" => true, "customerAccount" => false, "storefront" => false },
                    "ownerType" => "PRODUCT",
                  },
                  {
                    "id" => "gid://shopify/MetafieldDefinition/2",
                    "name" => "My Metafield 2",
                    "key" => "my_metafield_2",
                    "type" => { "name" => "integer" },
                    "namespace" => "my_namespace",
                    "description" => nil,
                    "capabilities" => {
                      "smartCollectionCondition" => { "enabled" => false },
                      "adminFilterable" => { "enabled" => true },
                    },
                    "access" => { "admin" => true, "customerAccount" => true, "storefront" => true },
                    "ownerType" => "PRODUCT",
                  },
                ]
              }
            }
          }
        )
      )

      expect {  schema.dump! }.to output(/Generating schema/).to_stdout

      expect(root.join("config/shopify/schema.rb").read).to eq(<<~RUBY
        # This file is auto-generated from the current state of the Shopify metafields.
        # Instead of editing this file, please use the metafields migration feature of ShopifyToolkit
        # to incrementally modify your metafields, and then regenerate this schema definition.
        #
        # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
        #
        # It's strongly recommended that you check this file into your version control system.
        ShopifyToolkit::Schema.define do
          create_metafield :products, :my_metafield, :single_line_text_field, name: "My Metafield", description: "My description", validations: [{:name=>"min_length", :value=>"1"}, {:name=>"max_length", :value=>"10"}], capabilities: {:smartCollectionCondition=>{:enabled=>true}, :adminFilterable=>{:enabled=>false}}
          create_metafield :products, :my_metafield_2, :integer, name: "My Metafield 2", namespace: :my_namespace, capabilities: {:smartCollectionCondition=>{:enabled=>false}, :adminFilterable=>{:enabled=>true}}
        end
      RUBY
      )
    end
  end
end
