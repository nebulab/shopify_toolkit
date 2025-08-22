require 'csv'
require 'active_record'
require 'thor'
require 'thor/actions'
require 'tmpdir'
require 'json'

class ShopifyToolkit::CommandLine < Thor
  include Thor::Actions

  RESERVED_COLUMN_NAMES = %w[select type id]

  class Result < ActiveRecord::Base
    def self.comments
      distinct.pluck(:import_comment)
    end

    def self.with_comment(text)
      where("import_comment LIKE ?", "%#{text}%")
    end
  end

  desc "analyze CSV_PATH", "Analyze results file at path CSV_PATH"
  method_option :force_import, type: :boolean, default: false
  method_option :tmp_dir, type: :string, default: Dir.tmpdir
  def analyze(csv_path)
    csv_path = File.expand_path(csv_path)
    underscore = ->(string) { string.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/(^_+|_+$)/, "") }
    csv = CSV.open(csv_path, liberal_parsing:true )
    header_to_column = -> { RESERVED_COLUMN_NAMES.include?(_1.to_s) ? "#{_1}_1" : _1 }
    headers = csv.shift.map(&underscore).map(&header_to_column)
    basename = File.basename csv_path
    database = "#{options[:tmp_dir]}/shopify-toolkit-analyze-#{underscore[basename]}.sqlite3"
    should_import = options[:force_import] || !File.exist?(database)
    to_record = ->(row) { headers.zip(row.each{ |c| c.delete!("\u0000") if String === c }).to_h.transform_keys(&header_to_column) }

    File.delete(database) if should_import && File.exist?(database)

    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database:)

    if should_import
      puts "==> Importing #{csv_path} into #{database}"
      ActiveRecord::Schema.define do
        create_table :results, force: true do |t|
          t.json :data
          headers.each { |header| t.string header }
        end
        add_index :results, :import_result if headers.include?('import_result')
      end
      csv.each_slice(5000) { |rows| print "."; Result.insert_all(rows.map(&to_record)) }
      puts
    end

    puts "==> Starting console for #{basename}"
    require "irb"
    IRB.conf[:IRB_NAME] = basename
    Result.class_eval { binding.irb(show_code: false) }
  end

  desc "migrate", "Run migrations"
  def migrate
    require "./config/environment"
    ::Shop.sole.with_shopify_session { ShopifyToolkit::Migrator.new.up }
  end

  desc "rollback", "Rollback last migration"
  def rollback
    require "./config/environment"
    ::Shop.sole.with_shopify_session { ShopifyToolkit::Migrator.new.down }
  end

  desc "redo", "Run migrations down and up again"
  def redo
    require "./config/environment"
    ::Shop.sole.with_shopify_session { ShopifyToolkit::Migrator.new.redo }
  end

  desc "schema_load", 'Load schema from "config/shopify/schema.rb"'
  def schema_load
    require "./config/environment"
    ::Shop.sole.with_shopify_session { ShopifyToolkit::Schema.load! }
  end

  desc "schema_dump", 'Dump schema to "config/shopify/schema.rb"'
  def schema_dump
    require "./config/environment"
    ::Shop.sole.with_shopify_session { ShopifyToolkit::Schema.dump! }
  end

  desc "generate_migration NAME", "Generate a migration with the given NAME"
  def generate_migration(name)
    require "./config/environment"
    migrations_dir = Rails.root.join("config/shopify/migrate")
    file_name = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_#{name.underscore}.rb"

    if migrations_dir.entries.map(&:to_s).grep(/\A\d+_#{Regexp.escape name.underscore}\.rb\z/).any?
      raise Thor::Error, "Migration class already exists: #{file_name}"
    end

    create_file migrations_dir.join(file_name) do
      <<~RUBY
        class #{name.camelize} < ShopifyToolkit::Migration
          def up
            # Add your migration code here
          end

          def down
            # Add your rollback code here
          end
        end
      RUBY
    end
  end

  # Bulk Operations Commands
  
  desc "bulk_query QUERY_FILE", "Submit a bulk GraphQL query"
  method_option :group_objects, type: :boolean, default: false, desc: "Group objects by type in results"
  method_option :poll, type: :boolean, default: false, desc: "Poll until completion and download results"
  method_option :timeout, type: :numeric, default: 1800, desc: "Polling timeout in seconds"
  method_option :output, type: :string, desc: "Output file for results (defaults to stdout)"
  def bulk_query(query_file)
    require "./config/environment" if File.exist?("./config/environment.rb")
    
    unless File.exist?(query_file)
      puts "Error: Query file '#{query_file}' not found"
      exit 1
    end
    
    query = File.read(query_file)
    
    ::Shop.sole.with_shopify_session do
      bulk_ops = Class.new { include ShopifyToolkit::BulkOperations }.new
      
      puts "Submitting bulk query from #{query_file}..."
      operation = bulk_ops.run_bulk_query(query, group_objects: options[:group_objects])
      
      operation_id = operation.dig("bulkOperation", "id")
      status = operation.dig("bulkOperation", "status")
      
      puts "Bulk operation submitted: #{operation_id}"
      puts "Status: #{status}"
      
      if options[:poll]
        puts "Polling for completion (timeout: #{options[:timeout]}s)..."
        
        completed = bulk_ops.poll_until_complete(operation_id, timeout: options[:timeout]) do |current|
          puts "Status: #{current["status"]}, Objects: #{current["objectCount"]}, Elapsed: #{Time.now - Time.parse(current["createdAt"])}s"
        end
        
        if completed["status"] == "COMPLETED"
          puts "Operation completed successfully!"
          if completed["url"]
            results = bulk_ops.download_results(completed)
            output_results(results, options[:output])
          else
            puts "No results URL available (query may have returned no data)"
          end
        else
          puts "Operation finished with status: #{completed["status"]}"
          puts "Error code: #{completed["errorCode"]}" if completed["errorCode"]
        end
      else
        puts "Use 'shopify-toolkit bulk_status #{operation_id}' to check status"
      end
    end
  rescue ShopifyToolkit::BulkOperations::BulkOperationError => e
    puts "Bulk operation error: #{e.message}"
    exit 1
  end

  desc "bulk_mutation MUTATION_FILE VARIABLES_FILE", "Submit a bulk GraphQL mutation"
  method_option :group_objects, type: :boolean, default: false, desc: "Group objects by type in results"
  method_option :poll, type: :boolean, default: false, desc: "Poll until completion and download results"
  method_option :timeout, type: :numeric, default: 1800, desc: "Polling timeout in seconds"
  method_option :output, type: :string, desc: "Output file for results (defaults to stdout)"
  method_option :client_identifier, type: :string, desc: "Client identifier for tracking"
  def bulk_mutation(mutation_file, variables_file)
    require "./config/environment" if File.exist?("./config/environment.rb")
    
    unless File.exist?(mutation_file)
      puts "Error: Mutation file '#{mutation_file}' not found"
      exit 1
    end
    
    unless File.exist?(variables_file)
      puts "Error: Variables file '#{variables_file}' not found"
      exit 1
    end
    
    mutation = File.read(mutation_file)
    variables_content = File.read(variables_file)
    
    # Parse variables file (supports JSON array or JSONL)
    variables_data = begin
      if variables_file.end_with?('.jsonl')
        variables_content.lines.map { |line| JSON.parse(line.strip) }
      else
        JSON.parse(variables_content)
      end
    rescue JSON::ParserError => e
      puts "Error parsing variables file: #{e.message}"
      exit 1
    end
    
    ::Shop.sole.with_shopify_session do
      bulk_ops = Class.new { include ShopifyToolkit::BulkOperations }.new
      
      puts "Submitting bulk mutation from #{mutation_file} with #{variables_data.size} operations..."
      operation = bulk_ops.run_bulk_mutation(
        mutation, 
        variables_data, 
        group_objects: options[:group_objects],
        client_identifier: options[:client_identifier]
      )
      
      operation_id = operation.dig("bulkOperation", "id")
      status = operation.dig("bulkOperation", "status")
      
      puts "Bulk operation submitted: #{operation_id}"
      puts "Status: #{status}"
      
      if options[:poll]
        puts "Polling for completion (timeout: #{options[:timeout]}s)..."
        
        completed = bulk_ops.poll_until_complete(operation_id, timeout: options[:timeout]) do |current|
          puts "Status: #{current["status"]}, Objects: #{current["objectCount"]}, Elapsed: #{Time.now - Time.parse(current["createdAt"])}s"
        end
        
        if completed["status"] == "COMPLETED"
          puts "Operation completed successfully!"
          if completed["url"]
            results = bulk_ops.download_results(completed)
            output_results(results, options[:output])
          else
            puts "No results URL available"
          end
        else
          puts "Operation finished with status: #{completed["status"]}"
          puts "Error code: #{completed["errorCode"]}" if completed["errorCode"]
        end
      else
        puts "Use 'shopify-toolkit bulk_status #{operation_id}' to check status"
      end
    end
  rescue ShopifyToolkit::BulkOperations::BulkOperationError => e
    puts "Bulk operation error: #{e.message}"
    exit 1
  end

  desc "bulk_status [OPERATION_ID]", "Check the status of a bulk operation"
  method_option :type, type: :string, desc: "Operation type filter (QUERY or MUTATION)"
  def bulk_status(operation_id = nil)
    require "./config/environment" if File.exist?("./config/environment.rb")
    
    ::Shop.sole.with_shopify_session do
      bulk_ops = Class.new { include ShopifyToolkit::BulkOperations }.new
      
      if operation_id
        # Get specific operation by ID
        operation = bulk_ops.send(:get_bulk_operation_by_id, operation_id)
        unless operation
          puts "Operation not found: #{operation_id}"
          exit 1
        end
        
        display_operation_status(operation)
      else
        # Get current operation  
        operation = bulk_ops.current_bulk_operation(type: options[:type])
        if operation
          display_operation_status(operation)
        else
          puts "No current bulk operation found"
          if options[:type]
            puts "(filtered by type: #{options[:type]})"
          end
        end
      end
    end
  end

  desc "bulk_cancel OPERATION_ID", "Cancel a running bulk operation"
  def bulk_cancel(operation_id)
    require "./config/environment" if File.exist?("./config/environment.rb")
    
    ::Shop.sole.with_shopify_session do
      bulk_ops = Class.new { include ShopifyToolkit::BulkOperations }.new
      
      puts "Canceling bulk operation: #{operation_id}"
      result = bulk_ops.cancel_bulk_operation(operation_id)
      
      puts "Operation canceled successfully"
      puts "Final status: #{result.dig("bulkOperation", "status")}"
    end
  rescue ShopifyToolkit::BulkOperations::BulkOperationError => e
    puts "Cancel failed: #{e.message}"
    exit 1
  end

  desc "bulk_results OPERATION_ID_OR_URL", "Download and display results from a completed bulk operation"
  method_option :output, type: :string, desc: "Output file for results (defaults to stdout)"
  method_option :raw, type: :boolean, default: false, desc: "Output raw JSONL without parsing"
  def bulk_results(operation_id_or_url)
    require "./config/environment" if File.exist?("./config/environment.rb")
    
    ::Shop.sole.with_shopify_session do
      bulk_ops = Class.new { include ShopifyToolkit::BulkOperations }.new
      
      # Determine if input is operation ID or direct URL
      if operation_id_or_url.start_with?('http')
        url = operation_id_or_url
      else
        # Get operation and extract URL
        operation = bulk_ops.send(:get_bulk_operation_by_id, operation_id_or_url)
        unless operation
          puts "Operation not found: #{operation_id_or_url}"
          exit 1
        end
        
        unless operation["status"] == "COMPLETED"
          puts "Operation is not completed (status: #{operation["status"]})"
          exit 1
        end
        
        url = operation["url"] || operation["partialDataUrl"]
        unless url
          puts "No results URL available for operation"
          exit 1
        end
      end
      
      puts "Downloading results from: #{url}"
      results = bulk_ops.download_results(url, parse_results: !options[:raw])
      
      if options[:raw]
        output_content(results, options[:output])
      else
        output_results(results, options[:output])
      end
      
      puts "Downloaded #{options[:raw] ? results.bytesize : results.size} #{options[:raw] ? 'bytes' : 'records'}"
    end
  rescue ShopifyToolkit::BulkOperations::BulkOperationError => e
    puts "Download failed: #{e.message}"
    exit 1
  end

  private

  def display_operation_status(operation)
    puts "Operation ID: #{operation["id"]}"
    puts "Type: #{operation["type"]}"
    puts "Status: #{operation["status"]}"
    puts "Created: #{operation["createdAt"]}"
    puts "Completed: #{operation["completedAt"]}" if operation["completedAt"]
    puts "Objects: #{operation["objectCount"]}"
    puts "File Size: #{operation["fileSize"]} bytes" if operation["fileSize"]
    puts "Error Code: #{operation["errorCode"]}" if operation["errorCode"]
    puts "Results URL: #{operation["url"]}" if operation["url"]
    puts "Partial Results URL: #{operation["partialDataUrl"]}" if operation["partialDataUrl"]
  end

  def output_results(results, output_file = nil)
    content = results.map { |result| JSON.pretty_generate(result) }.join("\n")
    output_content(content, output_file)
  end

  def output_content(content, output_file = nil)
    if output_file
      File.write(output_file, content)
      puts "Results written to: #{output_file}"
    else
      puts content
    end
  end

  def self.exit_on_failure?
    true
  end
end
