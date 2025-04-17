# frozen_string_literal: true

require "spec_helper"

RSpec.describe ShopifyToolkit::Schema do
  let(:schema) { described_class }
  let(:root) { Pathname(Dir.mktmpdir) }

  let(:definitions_by_owner) do
    { products: [product_definition], articles: [article_definition] }
  end

  before do
    allow(Rails).to receive(:root).and_return(root)
    root.join("config/shopify").mkpath

    ShopifyToolkit::Schema::OWNER_TYPES.each do |owner_type|
      allow(schema).to receive(:fetch_definitions).with(
        owner_type: owner_type
      ).and_return(definitions_by_owner.fetch(owner_type, []))
    end
  end

  describe "#dump!" do
    let(:product_definition) do
      {
        "id" => "gid://shopify/MetafieldDefinition/1",
        "name" => "My Metafield",
        "key" => "my_metafield",
        "type" => {
          "name" => "single_line_text_field"
        },
        "namespace" => "custom",
        "description" => "My description",
        "validations" => [
          { "name" => "min_length", "value" => "1" },
          { "name" => "max_length", "value" => "10" }
        ],
        "capabilities" => {
          "smartCollectionCondition" => {
            "enabled" => true
          },
          "adminFilterable" => {
            "enabled" => false
          }
        },
        "access" => {
          "admin" => true,
          "customerAccount" => false,
          "storefront" => false
        },
        "ownerType" => "PRODUCT"
      }
    end

    let(:article_definition) do
      {
        "id" => "gid://shopify/MetafieldDefinition/2",
        "name" => "My Metafield 2",
        "key" => "my_metafield_2",
        "type" => {
          "name" => "integer"
        },
        "namespace" => "my_namespace",
        "description" => nil,
        "capabilities" => {
          "smartCollectionCondition" => {
            "enabled" => false
          },
          "adminFilterable" => {
            "enabled" => true
          }
        },
        "access" => {
          "admin" => true,
          "customerAccount" => true,
          "storefront" => true
        },
        "ownerType" => "ARTICLE"
      }
    end

    it "dumps the schema to a file" do
      expect { schema.dump! }.to output(/Generating schema/).to_stdout

      expect(root.join("config/shopify/schema.rb").read).to eq(<<~RUBY)
        # This file is auto-generated from the current state of the Shopify metafields.
        # Instead of editing this file, please use the metafields migration feature of ShopifyToolkit
        # to incrementally modify your metafields, and then regenerate this schema definition.
        #
        # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
        #
        # It's strongly recommended that you check this file into your version control system.
        ShopifyToolkit::Schema.define do
          create_metafield :articles, :my_metafield_2, :integer, name: "My Metafield 2", namespace: :my_namespace, capabilities: {:smartCollectionCondition=>{:enabled=>false}, :adminFilterable=>{:enabled=>true}}
          create_metafield :products, :my_metafield, :single_line_text_field, name: "My Metafield", description: "My description", validations: [{:name=>"min_length", :value=>"1"}, {:name=>"max_length", :value=>"10"}], capabilities: {:smartCollectionCondition=>{:enabled=>true}, :adminFilterable=>{:enabled=>false}}
        end
      RUBY
    end
  end
end
