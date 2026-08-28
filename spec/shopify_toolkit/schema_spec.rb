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

  let(:metaobject_definitions) do
    [
      {
        "id" => "gid://shopify/MetaobjectDefinition/123",
        "type" => "color_pattern",
        "name" => "Color Pattern",
        "description" => "Product color patterns",
        "fieldDefinitions" => [
          {
            "key" => "name",
            "name" => "Pattern Name",
            "description" => "The name of the pattern",
            "type" => {
              "name" => "single_line_text_field"
            },
            "required" => true,
            "validations" => [{ "name" => "min_length", "value" => "1" }]
          },
          {
            "key" => "related_pattern",
            "name" => "Related Pattern",
            "description" => nil,
            "type" => {
              "name" => "metaobject_reference"
            },
            "required" => false,
            "validations" => [
              {
                "name" => "metaobject_definition_id",
                "value" => "gid://shopify/MetaobjectDefinition/456"
              }
            ]
          }
        ],
        "access" => {
          "admin" => "MERCHANT_READ_WRITE",
          "storefront" => "NONE"
        },
        "capabilities" => {
          "publishable" => {
            "enabled" => true
          },
          "translatable" => {
            "enabled" => false
          }
        }
      }
    ]
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

    # Mock metaobject definitions fetch
    allow(schema).to receive(:fetch_metaobject_definitions).and_return(
      metaobject_definitions
    )
  end

  describe "#dump!" do
    let(:migrator) do
      instance_double(
        ShopifyToolkit::Migrator,
        current_version: 20250627144019
      )
    end

    before do
      allow(ShopifyToolkit::Migrator).to receive(:new).and_return(migrator)

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
          "admin" => "MERCHANT_READ_WRITE",
          "customerAccount" => "NONE",
          "storefront" => "NONE"
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
          "admin" => "MERCHANT_READ_WRITE",
          "customerAccount" => "PUBLIC_READ",
          "storefront" => "PUBLIC_READ"
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
          "admin" => "MERCHANT_READ_WRITE",
          "customerAccount" => "NONE",
          "storefront" => "NONE"
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
          "admin" => "MERCHANT_READ_WRITE",
          "customerAccount" => "NONE",
          "storefront" => "NONE"
        },
        "ownerType" => "PRODUCT"
      }
    end

    SCHEMA_FIXTURE_BEFORE_RUBY_3_4 = <<~RUBY.freeze
      # This file is auto-generated from the current state of the Shopify metafields and metaobjects.
      # Instead of editing this file, please use the migration features of ShopifyToolkit
      # to incrementally modify your metafields and metaobjects, and then regenerate this schema definition.
      #
      # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
      #
      # It's strongly recommended that you check this file into your version control system.
      ShopifyToolkit::Schema.define(version: 2025_06_27_144019) do
        create_metaobject_definition :color_pattern, name: "Color Pattern", description: "Product color patterns", field_definitions: [{:key=>:name, :type=>:single_line_text_field, :name=>"Pattern Name", :description=>"The name of the pattern", :required=>true, :validations=>[{:name=>"min_length", :value=>"1"}]}, {:key=>:related_pattern, :type=>:metaobject_reference, :name=>"Related Pattern", :validations=>[{:name=>"metaobject_definition_type", :value=>"size_chart"}]}], access: {"admin"=>"MERCHANT_READ_WRITE", "storefront"=>"NONE"}, capabilities: {:publishable=>{:enabled=>true}, :translatable=>{:enabled=>false}}

        create_metafield :articles, :my_metafield_2, :integer, name: "My Metafield 2", namespace: :my_namespace, capabilities: {:smartCollectionCondition=>{:enabled=>false}, :adminFilterable=>{:enabled=>true}}
        create_metafield :products, :allowed_patterns, :"list.metaobject_reference", name: "Allowed Patterns", description: "List of allowed patterns", validations: [{:name=>"metaobject_definition_types", :value=>["color_pattern", "size_chart"]}]
        create_metafield :products, :color_pattern, :metaobject_reference, name: "Color Pattern", description: "Product color pattern", validations: [{:name=>"metaobject_definition_type", :value=>"color_pattern"}]
        create_metafield :products, :my_metafield, :single_line_text_field, name: "My Metafield", description: "My description", validations: [{:name=>"min_length", :value=>"1"}, {:name=>"max_length", :value=>"10"}], capabilities: {:smartCollectionCondition=>{:enabled=>true}, :adminFilterable=>{:enabled=>false}}
      end
    RUBY

    SCHEMA_FIXTURE = <<~RUBY.freeze
      # This file is auto-generated from the current state of the Shopify metafields and metaobjects.
      # Instead of editing this file, please use the migration features of ShopifyToolkit
      # to incrementally modify your metafields and metaobjects, and then regenerate this schema definition.
      #
      # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
      #
      # It's strongly recommended that you check this file into your version control system.
      ShopifyToolkit::Schema.define(version: 2025_06_27_144019) do
        create_metaobject_definition :color_pattern, name: "Color Pattern", description: "Product color patterns", field_definitions: [{key: :name, type: :single_line_text_field, name: "Pattern Name", description: "The name of the pattern", required: true, validations: [{name: "min_length", value: "1"}]}, {key: :related_pattern, type: :metaobject_reference, name: "Related Pattern", validations: [{name: "metaobject_definition_type", value: "size_chart"}]}], access: {"admin" => "MERCHANT_READ_WRITE", "storefront" => "NONE"}, capabilities: {publishable: {enabled: true}, translatable: {enabled: false}}

        create_metafield :articles, :my_metafield_2, :integer, name: "My Metafield 2", namespace: :my_namespace, capabilities: {smartCollectionCondition: {enabled: false}, adminFilterable: {enabled: true}}
        create_metafield :products, :allowed_patterns, :"list.metaobject_reference", name: "Allowed Patterns", description: "List of allowed patterns", validations: [{name: "metaobject_definition_types", value: ["color_pattern", "size_chart"]}]
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

    context "with Shopify-proprietary metafields" do
      let(:shopify_metafield) do
        {
          "id" => "gid://shopify/MetafieldDefinition/3",
          "name" => "Dog age group",
          "key" => "dog-age-group",
          "type" => { "name" => "list.metaobject_reference" },
          "namespace" => "shopify",
          "description" => "Helps sort dog supplies",
          "validations" => [],
          "capabilities" => {},
          "access" => { "admin" => true, "customerAccount" => false, "storefront" => false },
          "ownerType" => "PRODUCT"
        }
      end

      let(:shopify_discovery_metafield) do
        {
          "id" => "gid://shopify/MetafieldDefinition/4",
          "name" => "Related products",
          "key" => "related_products",
          "type" => { "name" => "list.product_reference" },
          "namespace" => "shopify--discovery--product_recommendation",
          "description" => "List of related products",
          "validations" => [],
          "capabilities" => {},
          "access" => { "admin" => true, "customerAccount" => false, "storefront" => true },
          "ownerType" => "PRODUCT"
        }
      end

      let(:definitions_by_owner) do
        {
          products: [product_definition, shopify_metafield, shopify_discovery_metafield],
          articles: [article_definition]
        }
      end

      it "excludes Shopify-proprietary metafields from the dump" do
        schema.dump!

        dumped_schema = root.join("config/shopify/schema.rb").read

        # Should include custom metafields
        expect(dumped_schema).to include("create_metafield :products, :my_metafield")
        expect(dumped_schema).to include("create_metafield :articles, :my_metafield_2")

        # Should NOT include Shopify-proprietary metafields
        expect(dumped_schema).not_to include("dog-age-group")
        expect(dumped_schema).not_to include("related_products")
        expect(dumped_schema).not_to include("namespace: :shopify")
        expect(dumped_schema).not_to include("shopify--discovery")
      end
    end
  end

  describe "#load!" do
    let(:migrator) { instance_double(ShopifyToolkit::Migrator) }
    let(:schema_path) { root.join(ShopifyToolkit::Schema::SCHEMA_PATH) }
    let(:schema_header) do
      <<~RUBY
        # This file is auto-generated from the current state of the Shopify metafields and metaobjects.
        # Instead of editing this file, please use the migration features of ShopifyToolkit
        # to incrementally modify your metafields and metaobjects, and then regenerate this schema definition.
        #
        # This file is the source used to define your metafields when running `bin/rails shopify:schema:load`.
        #
        # It's strongly recommended that you check this file into your version control system.
      RUBY
    end

    it "marks migrations through the schema version as migrated" do
      schema_path.write(<<~RUBY)
        #{schema_header}ShopifyToolkit::Schema.define(version: 2025_06_27_144019) do
        end
      RUBY

      allow(ShopifyToolkit::Migrator).to receive(:new).and_return(migrator)
      expect(migrator).to receive(:assume_migrated_upto_version).with(20250627144019).once

      schema.load!
    end

    it "does not update the migration version when a schema statement fails" do
      schema_path.write(<<~RUBY)
        #{schema_header}ShopifyToolkit::Schema.define(version: 2025_06_27_144019) do
          create_metafield :products, :broken, :single_line_text_field, name: "Broken"
        end
      RUBY

      allow(schema).to receive(:create_metafield).and_raise("schema failure")
      expect(ShopifyToolkit::Migrator).not_to receive(:new)

      expect { schema.load! }.to raise_error("schema failure")
    end

    it "continues to load schema files without a version" do
      schema_path.write(<<~RUBY)
        #{schema_header}ShopifyToolkit::Schema.define do
        end
      RUBY

      expect(ShopifyToolkit::Migrator).not_to receive(:new)

      expect { schema.load! }.not_to raise_error
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
            "name" => "metaobject_definition_types",
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
            "name" => "metaobject_definition_types",
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

    it "converts array of metaobject definition IDs using plural name for list.mixed_reference fields" do
      validations = [
        {
          "name" => "metaobject_definition_ids",
          "value" => %w[
            gid://shopify/MetaobjectDefinition/123
            gid://shopify/MetaobjectDefinition/456
          ]
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "list.mixed_reference"
        )

      expect(result).to eq(
        [
          {
            "name" => "metaobject_definition_types",
            "value" => %w[color_pattern size_chart]
          }
        ]
      )
    end

    it "handles JSON string arrays for metaobject_definition_ids" do
      validations = [
        {
          "name" => "metaobject_definition_ids",
          "value" =>
            "[\"gid://shopify/MetaobjectDefinition/123\",\"gid://shopify/MetaobjectDefinition/456\"]"
        }
      ]
      result =
        schema.convert_validations_gids_to_types(
          validations,
          "list.mixed_reference"
        )

      expect(result).to eq(
        [
          {
            "name" => "metaobject_definition_types",
            "value" => %w[color_pattern size_chart]
          }
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

    it "returns true for mixed_reference" do
      expect(schema.is_metaobject_reference_type?("mixed_reference")).to be true
      expect(schema.is_metaobject_reference_type?(:mixed_reference)).to be true
    end

    it "returns true for list.mixed_reference" do
      expect(
        schema.is_metaobject_reference_type?("list.mixed_reference")
      ).to be true
      expect(
        schema.is_metaobject_reference_type?(:"list.mixed_reference")
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
