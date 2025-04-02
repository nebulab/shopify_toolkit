# frozen_string_literal: true

module ShopifyToolkit::Migration::Logging
  def write(text = "")
    puts(text)
  end

  def announce(message)
    text = "#{version} #{name}: #{message}"
    length = [0, 75 - text.length].max
    write "== %s %s" % [text, "=" * length]
  end

  # Takes a message argument and outputs it as is.
  # A second boolean argument can be passed to specify whether to indent or not.
  def say(message, subitem = false)
    write "#{subitem ? "   ->" : "--"} #{message}"
  end

  # Outputs text along with how long it took to run its block.
  # If the block returns an integer it assumes it is the number of rows affected.
  def say_with_time(message)
    say(message)
    result = nil
    time_elapsed = ActiveSupport::Benchmark.realtime { result = yield }
    say "%.4fs" % time_elapsed, :subitem
    result
  end
end
