# frozen_string_literal: true

require_relative "shopify_toolkit/version"
require "zeitwerk"

module ShopifyToolkit

  def self.loader
    @loader ||= Zeitwerk::Loader.for_gem
  end

  loader.setup
  # loader.eager_load # optionally
end
