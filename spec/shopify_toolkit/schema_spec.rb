# frozen_string_literal: true

require "spec_helper"

RSpec.describe ShopifyToolkit::Schema do
  let(:schema) { described_class }
  let(:root) { Pathname(Dir.mktmpdir) }

  let(:definitions_by_owner) do
    {
      products: [
        product_definition,
        metaobject_reference_definition,
        list_metaobject_reference_definition
      ],
      articles: [article_definition]
    }
  end

  before do
    allow(Rails).to receive(:root).and_return(root)
    root.join("config/shopify").mkpath

    # Mock metaobject type resolution
    allow(schema).to receive(:get_metaobject_definition_type_by_gid).with(
      "gid://shopify/MetaobjectDefinition/123"
    ).and_return("color_pattern")
    allow(schema).to receive(:get_metaobject_definition_type_by_gid).with(
      "gid://shopify/MetaobjectDefinition/456"
    ).and_return("size_chart")
  end

  describe "#dump!" do
    before do
      ShopifyToolkit::Schema::OWNER_TYPES.each do |owner_type|
        allow(schema).to receive(:fetch_definitions).with(
          owner_type: owner_type
        ).and_return(definitions_by_owner.fetch(owner_type, []))
      end
    end
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

    let(:metaobject_reference_definition) do
      {
        "id" => "gid://shopify/MetafieldDefinition/3",
        "name" => "Color Pattern",
        "key" => "color_pattern",
        "type" => {
          "name" => "metaobject_reference"
        },
        "namespace" => "custom",
        "description" => "Product color pattern",
        "validations" => [
          {
            "name" => "metaobject_definition_id",
            "value" => "gid://shopify/MetaobjectDefinition/123"
          }
        ],
        "capabilities" => {
          "smartCollectionCondition" => {
            "enabled" => false
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

    let(:list_metaobject_reference_definition) do
      {
        "id" => "gid://shopify/MetafieldDefinition/4",
        "name" => "Allowed Patterns",
        "key" => "allowed_patterns",
        "type" => {
          "name" => "list.metaobject_reference"
        },
        "namespace" => "custom",
        "description" => "List of allowed patterns",
        "validations" => [
          {
            "name" => "metaobject_definition_id",
            "value" => %w[
              gid://shopify/MetaobjectDefinition/123
              gid://shopify/MetaobjectDefinition/456
            ]
          }
        ],
        "capabilities" => {
          "smartCollectionCondition" => {
            "enabled" => false
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

    SCHEMA_FIXTURE_BEFORE_RUBY_3_4 = <<~RUBY.freeze
      # This file is auto-generated from the current state of the Shopify metafields.
      # Instead of editing this file, please use the metafields migration feature of ShopifyToolkit
      # to incrementally modify your metafields, and then regenerate this schema definition.
      #
      # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
      #
      # It's strongly recommended that you check this file into your version control system.
      ShopifyToolkit::Schema.define do
        create_metafield :articles, :my_metafield_2, :integer, name: "My Metafield 2", namespace: :my_namespace, capabilities: {:smartCollectionCondition=>{:enabled=>false}, :adminFilterable=>{:enabled=>true}}
        create_metafield :products, :allowed_patterns, :"list.metaobject_reference", name: "Allowed Patterns", description: "List of allowed patterns", validations: [{:name=>"metaobject_definition_type", :value=>["color_pattern", "size_chart"]}]
        create_metafield :products, :color_pattern, :metaobject_reference, name: "Color Pattern", description: "Product color pattern", validations: [{:name=>"metaobject_definition_type", :value=>"color_pattern"}]
        create_metafield :products, :my_metafield, :single_line_text_field, name: "My Metafield", description: "My description", validations: [{:name=>"min_length", :value=>"1"}, {:name=>"max_length", :value=>"10"}], capabilities: {:smartCollectionCondition=>{:enabled=>true}, :adminFilterable=>{:enabled=>false}}
      end
    RUBY

    SCHEMA_FIXTURE = <<~RUBY.freeze
      # This file is auto-generated from the current state of the Shopify metafields.
      # Instead of editing this file, please use the metafields migration feature of ShopifyToolkit
      # to incrementally modify your metafields, and then regenerate this schema definition.
      #
      # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
      #
      # It's strongly recommended that you check this file into your version control system.
      ShopifyToolkit::Schema.define do
        create_metafield :articles, :my_metafield_2, :integer, name: "My Metafield 2", namespace: :my_namespace, capabilities: {smartCollectionCondition: {enabled: false}, adminFilterable: {enabled: true}}
        create_metafield :products, :allowed_patterns, :"list.metaobject_reference", name: "Allowed Patterns", description: "List of allowed patterns", validations: [{name: "metaobject_definition_type", value: ["color_pattern", "size_chart"]}]
        create_metafield :products, :color_pattern, :metaobject_reference, name: "Color Pattern", description: "Product color pattern", validations: [{name: "metaobject_definition_type", value: "color_pattern"}]
        create_metafield :products, :my_metafield, :single_line_text_field, name: "My Metafield", description: "My description", validations: [{name: "min_length", value: "1"}, {name: "max_length", value: "10"}], capabilities: {smartCollectionCondition: {enabled: true}, adminFilterable: {enabled: false}}
      end
    RUBY

    it "dumps the schema to a file" do
      expect { schema.dump! }.to output(/Generating schema/).to_stdout

      expected_schema =
        (
          if RUBY_VERSION.to_f < 3.4
            SCHEMA_FIXTURE_BEFORE_RUBY_3_4
          else
            SCHEMA_FIXTURE
          end
        )
      expect(root.join("config/shopify/schema.rb").read).to eq(expected_schema)
    end
  end

  describe "#convert_validations_gids_to_types" do
    let(:schema) { described_class }

    before do
      allow(schema).to receive(:get_metaobject_definition_type_by_gid).with(
        "gid://shopify/MetaobjectDefinition/123"
      ).and_return("color_pattern")
      allow(schema).to receive(:get_metaobject_definition_type_by_gid).with(
        "gid://shopify/MetaobjectDefinition/456"
      ).and_return("size_chart")
    end

    it "converts single metaobject definition ID to type for metaobject_reference fields" do
      validations = [
        {
          "name" => "metaobject_definition_id",
          "value" => "gid://shopify/MetaobjectDefinition/123"
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "metaobject_reference"
        )

      expect(result).to eq(
        [{ "name" => "metaobject_definition_type", "value" => "color_pattern" }]
      )
    end

    it "converts array of metaobject definition IDs to types for list.metaobject_reference fields" do
      validations = [
        {
          "name" => "metaobject_definition_id",
          "value" => %w[
            gid://shopify/MetaobjectDefinition/123
            gid://shopify/MetaobjectDefinition/456
          ]
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "list.metaobject_reference"
        )

      expect(result).to eq(
        [
          {
            "name" => "metaobject_definition_type",
            "value" => %w[color_pattern size_chart]
          }
        ]
      )
    end

    it "preserves non-GID values in arrays" do
      validations = [
        {
          "name" => "metaobject_definition_id",
          "value" => %w[gid://shopify/MetaobjectDefinition/123 some_other_value]
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "list.metaobject_reference"
        )

      expect(result).to eq(
        [
          {
            "name" => "metaobject_definition_type",
            "value" => %w[color_pattern some_other_value]
          }
        ]
      )
    end

    it "does not convert validations for non-metaobject reference fields" do
      validations = [
        {
          "name" => "metaobject_definition_id",
          "value" => "gid://shopify/MetaobjectDefinition/123"
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "single_line_text_field"
        )

      expect(result).to eq(validations)
    end

    it "preserves other validation types unchanged" do
      validations = [
        { "name" => "min_length", "value" => "1" },
        {
          "name" => "metaobject_definition_id",
          "value" => "gid://shopify/MetaobjectDefinition/123"
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "metaobject_reference"
        )

      expect(result).to eq(
        [
          { "name" => "min_length", "value" => "1" },
          { "name" => "metaobject_definition_type", "value" => "color_pattern" }
        ]
      )
    end
  end

  describe "#is_metaobject_reference_type?" do
    let(:schema) { described_class }

    it "returns true for metaobject_reference" do
      expect(
        schema.is_metaobject_reference_type?("metaobject_reference")
      ).to be true
      expect(
        schema.is_metaobject_reference_type?(:metaobject_reference)
      ).to be true
    end

    it "returns true for list.metaobject_reference" do
      expect(
        schema.is_metaobject_reference_type?("list.metaobject_reference")
      ).to be true
      expect(
        schema.is_metaobject_reference_type?(:"list.metaobject_reference")
      ).to be true
    end

    it "returns false for other types" do
      expect(
        schema.is_metaobject_reference_type?("single_line_text_field")
      ).to be false
      expect(schema.is_metaobject_reference_type?("integer")).to be false
      expect(
        schema.is_metaobject_reference_type?("list.single_line_text_field")
      ).to be false
    end
  end
end
