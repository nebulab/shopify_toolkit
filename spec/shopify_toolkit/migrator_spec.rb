# frozen_string_literal: true

require "spec_helper"

RSpec.describe ShopifyToolkit::Migrator do
  subject(:migrator) { described_class.allocate }

  describe "#current_version" do
    it "returns the latest migrated version" do
      migrator.instance_variable_set(:@migrated_versions, [20250501000000, 20250627144019])

      expect(migrator.current_version).to eq(20250627144019)
    end

    it "returns zero when no migration has run" do
      migrator.instance_variable_set(:@migrated_versions, [])

      expect(migrator.current_version).to eq(0)
    end
  end

  describe "#assume_migrated_upto_version" do
    it "tracks the schema version and every earlier local migration" do
      migrations = [
        instance_double(ShopifyToolkit::Migrator::MigrationProxy, version: 20250501000000),
        instance_double(ShopifyToolkit::Migrator::MigrationProxy, version: 20250601000000),
        instance_double(ShopifyToolkit::Migrator::MigrationProxy, version: 20250701000000)
      ]

      migrator.instance_variable_set(:@migrations, migrations)
      migrator.instance_variable_set(:@migrated_versions, [20250401000000])

      expect(migrator).to receive(:update_metafield).once

      migrator.assume_migrated_upto_version(20250627144019)

      expect(migrator.migrated_versions).to contain_exactly(
        20250401000000,
        20250501000000,
        20250601000000,
        20250627144019
      )
    end

    it "does not persist when every assumed version is already tracked" do
      migrations = [
        instance_double(ShopifyToolkit::Migrator::MigrationProxy, version: 20250501000000),
        instance_double(ShopifyToolkit::Migrator::MigrationProxy, version: 20250627144019)
      ]

      migrator.instance_variable_set(:@migrations, migrations)
      migrator.instance_variable_set(:@migrated_versions, [20250501000000, 20250627144019])

      expect(migrator).not_to receive(:update_metafield)

      migrator.assume_migrated_upto_version(20250627144019)
    end
  end
end
