# frozen_string_literal: true

require "active_support/benchmark"

class ShopifyToolkit::Migration
  include ShopifyToolkit::AdminClient
  include ShopifyToolkit::MetafieldStatements
  include ShopifyToolkit::MetaobjectStatements
  include ShopifyToolkit::Migration::Logging

  class IrreversibleMigration < StandardError
  end

  def logger
    @logger ||= ActiveSupport::Logger.new(STDOUT).tap do |logger|
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{severity}: #{msg}\n"
      end
    end
  end

  def self.[](api_version)
    klass = Class.new(self)
    klass.const_set(:API_VERSION, api_version)
    klass
  end

  attr_reader :name, :version

  def initialize(name, version)
    @name    = name
    @version = version
  end

  def announce(message)
    super "#{version} #{name}: #{message}"
  end

  def migrate(direction)
    case direction
    when :up
      announce("migrating")
      time_elapsed = ActiveSupport::Benchmark.realtime { up }
      announce("migrated (%.4fs)" % time_elapsed)

    when :down
      announce("reverting")
      time_elapsed = ActiveSupport::Benchmark.realtime { down }
      announce("reverted (%.4fs)" % time_elapsed)

    else
      raise ArgumentError, "Unknown migration direction: #{direction}"
    end
  end

  def up
    # Implement in subclass
  end

  def down
    raise IrreversibleMigration
  end
end
