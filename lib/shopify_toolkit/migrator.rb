# frozen_string_literal: true

require "active_support/benchmarkable"
require "active_support/core_ext/module/delegation"

class ShopifyToolkit::Migrator # :nodoc:
  include ShopifyToolkit::AdminClient
  include ShopifyToolkit::MetafieldStatements
  include ShopifyToolkit::MetaobjectStatements

  singleton_class.attr_accessor :migrations_paths
  self.migrations_paths = ["config/shopify/migrate"]

  attr_reader :migrated_versions, :migrations, :migrations_paths

  def initialize(migrations_paths: self.class.migrations_paths)
    @migrations_paths  = migrations_paths
    @migrated_versions = read_or_create_metafield["migrated_versions"]
    @migrations        = load_migrations # [MigrationProxy<Migration1>, MigrationProxy<Migration2>, ...]
  end

  def current_version
    migrated.max || 0
  end

  def up
    pending_migrations = migrations.reject { migrated_versions.include?(_1.version) }

    pending_migrations.each do |migration|
      migration.migrate(:up)
      migrated_versions << migration.version
    end
  ensure
    update_metafield
  end

  def executed_migrations
    migrations.select { migrated_versions.include?(_1.version) }
  end

  def down
    # For now we'll just rollback the last one
    executed_migrations.last(1).each do |migration|
      migration.migrate(:down)
      migrated_versions.delete(migration.version)
    end
  ensure
    update_metafield
  end

  def query(query, **variables)
    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1) }
      .body
      .dig("data")
  end

  def update_metafield
    namespace = :shopify_toolkit
    key = :migrations

    value = { "migrated_versions" => migrated_versions.to_a.sort }.to_json

    owner_id = query(%(query GetShopGId { shop { id } })).dig("shop", "id")

    query = <<~GRAPHQL
      mutation metafieldsSet($metafields: [MetafieldsSetInput!]!) {
        metafieldsSet(metafields: $metafields) {
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL
    query(query, metafields: [{ namespace:, key:, ownerId: owner_id, value: }])

    nil
  end

  def read_or_create_metafield
    namespace = :shopify_toolkit
    key = :migrations

    value = query(
      "query ShopMetafield($namespace: String!, $key: String!) {shop {metafield(namespace: $namespace, key: $key) {value}}}",
      namespace:, key:,
    ).dig("shop", "metafield", "value")

    if value.nil?
      create_metafield :shop, key, :json, namespace:, name: "Migrations metadata"
      return { "migrated_versions" => [] }
    end

    JSON.parse(value)
  end

  def redo
    down
    up
  end

  def migration_files
    paths = Array(migrations_paths)
    Dir[*paths.flat_map { |path| "#{path}/**/[0-9]*_*.rb" }]
  end

  def parse_migration_filename(filename)
    File.basename(filename).scan(/\A([0-9]+)_([_a-z0-9]*)\.?([_a-z0-9]*)?\.rb\z/).first
  end

  def load_migrations
    migrations = migration_files.map do |file|
      version, name, scope = parse_migration_filename(file)
      raise "missing version #{file}" unless version
      raise "missing name #{file}" unless name
      version = version.to_i
      name = name.camelize

      MigrationProxy.new(name, version, file, scope)
    end

    migrations.sort_by(&:version)
  end

  # MigrationProxy is used to defer loading of the actual migration classes
  # until they are needed
  MigrationProxy = Struct.new(:name, :version, :filename, :scope) do
    def initialize(name, version, filename, scope)
      super
      @migration = nil
    end

    def basename
      File.basename(filename)
    end

    delegate :migrate, :up, :down, :announce, :say, :say_with_time, to: :migration

    private
      def migration
        @migration ||= load_migration
      end

      def load_migration
        Object.send(:remove_const, name) rescue nil

        load(File.expand_path(filename))
        name.constantize.new(name, version)
      end
  end
end
