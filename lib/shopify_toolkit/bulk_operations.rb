# frozen_string_literal: true

require "net/http"
require "json"
require "tempfile"

module ShopifyToolkit
  # Bulk Operations module provides methods to submit, track, and retrieve results
  # from Shopify Admin GraphQL API bulk operations including bulk queries and mutations.
  #
  # This module handles:
  # - Bulk query operations (bulkOperationRunQuery)
  # - Bulk mutation operations with staged uploads (bulkOperationRunMutation)  
  # - Status tracking and polling (currentBulkOperation)
  # - Result retrieval and JSONL parsing
  # - Operation cancellation (bulkOperationCancel)
  # - Error handling and logging
  module BulkOperations
    include AdminClient

    # Error raised when a bulk operation fails
    class BulkOperationError < StandardError
      attr_reader :error_code, :user_errors

      def initialize(message, error_code: nil, user_errors: [])
        @error_code = error_code
        @user_errors = user_errors
        super(message)
      end
    end

    # Error raised when attempting to run a bulk operation when one is already in progress
    class OperationInProgressError < BulkOperationError; end

    # Submits a bulk query operation to retrieve large volumes of data asynchronously
    #
    # @param query [String] The GraphQL query to run in bulk
    # @param group_objects [Boolean] Whether to group objects by type (default: false)
    # @return [Hash] The bulk operation response containing id and status
    #
    # @example
    #   bulk_ops = BulkOperations.new
    #   query = <<~GRAPHQL
    #     {
    #       products {
    #         edges {
    #           node {
    #             id
    #             title
    #             handle
    #           }
    #         }
    #       }
    #     }
    #   GRAPHQL
    #   
    #   operation = bulk_ops.run_bulk_query(query)
    #   puts operation.dig("bulkOperation", "id")
    def run_bulk_query(query, group_objects: false)
      mutation = <<~GRAPHQL
        mutation bulkOperationRunQuery($query: String!, $groupObjects: Boolean!) {
          bulkOperationRunQuery(query: $query, groupObjects: $groupObjects) {
            bulkOperation {
              id
              status
              query
              createdAt
              completedAt
              objectCount
              fileSize
              url
              partialDataUrl
              errorCode
              type
            }
            userErrors {
              field
              message
              code
            }
          }
        }
      GRAPHQL

      variables = { query: query, groupObjects: group_objects }
      
      response = query_admin_api(mutation, variables)
      handle_bulk_operation_response(response, "bulkOperationRunQuery")
    end

    # Submits a bulk mutation operation to import large volumes of data asynchronously
    #
    # @param mutation [String] The GraphQL mutation to run in bulk
    # @param variables_data [Array<Hash>] Array of variable objects for each mutation call
    # @param group_objects [Boolean] Whether to group objects by type (default: false) 
    # @param client_identifier [String] Optional client identifier for tracking
    # @return [Hash] The bulk operation response containing id and status
    #
    # @example
    #   bulk_ops = BulkOperations.new
    #   mutation_query = <<~GRAPHQL
    #     mutation createProduct($input: ProductInput!) {
    #       productCreate(input: $input) {
    #         product {
    #           id
    #           title
    #         }
    #         userErrors {
    #           field
    #           message
    #         }
    #       }
    #     }
    #   GRAPHQL
    #   
    #   variables = [
    #     { input: { title: "Product 1", productType: "Apparel" } },
    #     { input: { title: "Product 2", productType: "Apparel" } }
    #   ]
    #   
    #   operation = bulk_ops.run_bulk_mutation(mutation_query, variables)
    #   puts operation.dig("bulkOperation", "id")
    def run_bulk_mutation(mutation, variables_data, group_objects: false, client_identifier: nil)
      # First, create staged upload for variables
      staged_upload_path = create_staged_upload(variables_data)
      
      mutation_query = <<~GRAPHQL
        mutation bulkOperationRunMutation(
          $mutation: String!
          $stagedUploadPath: String!
          $groupObjects: Boolean!
          $clientIdentifier: String
        ) {
          bulkOperationRunMutation(
            mutation: $mutation
            stagedUploadPath: $stagedUploadPath  
            groupObjects: $groupObjects
            clientIdentifier: $clientIdentifier
          ) {
            bulkOperation {
              id
              status
              query
              createdAt
              completedAt
              objectCount
              fileSize
              url
              partialDataUrl
              errorCode
              type
            }
            userErrors {
              field
              message
              code
            }
          }
        }
      GRAPHQL

      variables = {
        mutation: mutation,
        stagedUploadPath: staged_upload_path,
        groupObjects: group_objects,
        clientIdentifier: client_identifier
      }.compact

      response = query_admin_api(mutation_query, variables)
      handle_bulk_operation_response(response, "bulkOperationRunMutation")
    end

    # Retrieves the current bulk operation status and details
    #
    # @param type [String] Type of operation to check ("QUERY" or "MUTATION")
    # @return [Hash, nil] The current bulk operation or nil if none exists
    #
    # @example
    #   bulk_ops = BulkOperations.new
    #   status = bulk_ops.current_bulk_operation
    #   puts status["status"] if status
    def current_bulk_operation(type: nil)
      query = if type
        <<~GRAPHQL
          query currentBulkOperation($type: BulkOperationType!) {
            currentBulkOperation(type: $type) {
              id
              status
              query
              createdAt
              completedAt
              objectCount
              fileSize
              url
              partialDataUrl
              errorCode
              type
            }
          }
        GRAPHQL
      else
        <<~GRAPHQL
          query currentBulkOperation {
            currentBulkOperation {
              id
              status
              query
              createdAt
              completedAt
              objectCount
              fileSize
              url
              partialDataUrl
              errorCode
              type
            }
          }
        GRAPHQL
      end

      variables = type ? { type: type } : {}
      response = query_admin_api(query, variables)
      response.dig("currentBulkOperation")
    end

    # Cancels a running bulk operation
    #
    # @param operation_id [String] The ID of the bulk operation to cancel
    # @return [Hash] The cancelled bulk operation details
    #
    # @example
    #   bulk_ops = BulkOperations.new
    #   result = bulk_ops.cancel_bulk_operation("gid://shopify/BulkOperation/1234")
    #   puts result.dig("bulkOperation", "status")
    def cancel_bulk_operation(operation_id)
      mutation = <<~GRAPHQL
        mutation bulkOperationCancel($id: ID!) {
          bulkOperationCancel(id: $id) {
            bulkOperation {
              id
              status
              errorCode
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = { id: operation_id }
      response = query_admin_api(mutation, variables)
      
      if response.dig("bulkOperationCancel", "userErrors")&.any?
        raise BulkOperationError.new(
          "Failed to cancel bulk operation: #{response.dig("bulkOperationCancel", "userErrors").map { |e| e["message"] }.join(", ")}",
          user_errors: response.dig("bulkOperationCancel", "userErrors")
        )
      end

      response.dig("bulkOperationCancel")
    end

    # Downloads and parses the JSONL results from a completed bulk operation
    #
    # @param operation_or_url [Hash, String] Either a bulk operation hash with 'url' key or direct URL string
    # @param parse_results [Boolean] Whether to parse JSON lines (default: true)
    # @return [Array, String] Parsed results array or raw JSONL string
    #
    # @example
    #   bulk_ops = BulkOperations.new
    #   operation = bulk_ops.current_bulk_operation
    #   if operation && operation["status"] == "COMPLETED"
    #     results = bulk_ops.download_results(operation)
    #     puts "Downloaded #{results.size} results"
    #   end
    def download_results(operation_or_url, parse_results: true)
      url = operation_or_url.is_a?(Hash) ? operation_or_url["url"] : operation_or_url
      
      return nil unless url
      
      logger.info "Downloading bulk operation results from: #{url}"
      
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      
      unless response.is_a?(Net::HTTPSuccess)
        raise BulkOperationError, "Failed to download results: #{response.code} #{response.message}"
      end

      content = response.body
      logger.info "Downloaded #{content.bytesize} bytes of results"

      if parse_results
        parse_jsonl(content)
      else
        content
      end
    end

    # Polls a bulk operation until completion, yielding status updates
    #
    # @param operation_id [String] The bulk operation ID to monitor
    # @param poll_interval [Integer] Seconds between status checks (default: 5)
    # @param timeout [Integer] Maximum seconds to wait (default: 1800 - 30 minutes)
    # @param &block [Proc] Optional block to call with status updates
    # @return [Hash] The completed bulk operation details
    #
    # @example
    #   bulk_ops = BulkOperations.new
    #   operation = bulk_ops.run_bulk_query(query)
    #   
    #   completed = bulk_ops.poll_until_complete(operation["bulkOperation"]["id"]) do |status|
    #     puts "Status: #{status["status"]}, Objects: #{status["objectCount"]}"
    #   end
    #   
    #   if completed["status"] == "COMPLETED"
    #     results = bulk_ops.download_results(completed)
    #   end
    def poll_until_complete(operation_id, poll_interval: 5, timeout: 1800, &block)
      start_time = Time.now
      
      loop do
        operation = get_bulk_operation_by_id(operation_id)
        
        yield operation if block_given?
        
        case operation["status"]
        when "COMPLETED", "FAILED", "CANCELED", "EXPIRED"
          return operation
        end
        
        if Time.now - start_time > timeout
          raise BulkOperationError, "Polling timeout exceeded (#{timeout}s)"
        end
        
        sleep poll_interval
      end
    end

    # Logger instance 
    def logger
      @logger ||= Logger.new($stdout)
    end

    private

    # Queries the Admin API with error handling
    def query_admin_api(query, variables = {})
      response = query(query, **variables)
      response
    rescue => e
      logger.error "GraphQL query failed: #{e.message}"
      raise BulkOperationError, "GraphQL query failed: #{e.message}"
    end

    # Creates a staged upload for bulk mutation variables
    def create_staged_upload(variables_data)
      # Convert variables to JSONL format
      jsonl_content = variables_data.map { |vars| JSON.generate(vars) }.join("\n")
      
      # Create staged upload
      mutation = <<~GRAPHQL
        mutation stagedUploadsCreate($input: [StagedUploadInput!]!) {
          stagedUploadsCreate(input: $input) {
            stagedTargets {
              url
              resourceUrl
              parameters {
                name
                value
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        input: [{
          resource: "BULK_MUTATION_VARIABLES",
          filename: "bulk_mutation_variables.jsonl",
          mimeType: "text/jsonl", 
          httpMethod: "POST"
        }]
      }

      response = query_admin_api(mutation, variables)
      
      if response.dig("stagedUploadsCreate", "userErrors")&.any?
        raise BulkOperationError.new(
          "Failed to create staged upload: #{response.dig("stagedUploadsCreate", "userErrors").map { |e| e["message"] }.join(", ")}",
          user_errors: response.dig("stagedUploadsCreate", "userErrors")
        )
      end

      staged_target = response.dig("stagedUploadsCreate", "stagedTargets", 0)
      upload_url = staged_target["url"] 
      upload_params = staged_target["parameters"]

      # Upload the JSONL content
      upload_to_staged_target(upload_url, upload_params, jsonl_content)
      
      # Extract the path from parameters (typically the 'key' parameter)
      key_param = upload_params.find { |p| p["name"] == "key" }
      key_param ? key_param["value"] : nil
    end

    # Uploads content to a staged upload target
    def upload_to_staged_target(url, parameters, content)
      require "net/http/post/multipart" rescue nil
      
      uri = URI(url)
      
      # Create multipart form data
      form_data = {}
      parameters.each { |param| form_data[param["name"]] = param["value"] }
      form_data["file"] = content
      
      # Use basic form encoding since we don't have multipart gem
      boundary = "----formdata-shopify-#{Time.now.to_i}"
      post_body = []
      
      form_data.each do |key, value|
        if key == "file"
          post_body << "--#{boundary}\r\n"
          post_body << "Content-Disposition: form-data; name=\"file\"; filename=\"bulk_mutation_variables.jsonl\"\r\n"
          post_body << "Content-Type: text/jsonl\r\n\r\n"
          post_body << value
          post_body << "\r\n"
        else
          post_body << "--#{boundary}\r\n"
          post_body << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
          post_body << value.to_s
          post_body << "\r\n"
        end
      end
      post_body << "--#{boundary}--\r\n"
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      
      request = Net::HTTP::Post.new(uri)
      request.body = post_body.join
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      
      response = http.request(request)
      
      unless response.is_a?(Net::HTTPSuccess) || response.code == "201"
        raise BulkOperationError, "Failed to upload staged file: #{response.code} #{response.message}"
      end
      
      logger.info "Successfully uploaded #{content.bytesize} bytes to staged upload"
    end

    # Handles bulk operation response and error checking
    def handle_bulk_operation_response(response, operation_name)
      operation_data = response.dig(operation_name)
      
      if operation_data.nil?
        raise BulkOperationError, "No #{operation_name} data in response"
      end

      user_errors = operation_data["userErrors"] || []
      
      if user_errors.any?
        # Check for operation in progress error
        if user_errors.any? { |e| e["code"] == "OPERATION_IN_PROGRESS" }
          raise OperationInProgressError.new(
            "Another bulk operation is already in progress",
            user_errors: user_errors
          )
        end
        
        error_messages = user_errors.map { |e| e["message"] }.join(", ")
        raise BulkOperationError.new(
          "Bulk operation failed: #{error_messages}",
          user_errors: user_errors
        )
      end

      operation_data
    end

    # Gets a bulk operation by ID using the node query
    def get_bulk_operation_by_id(operation_id)
      query = <<~GRAPHQL
        query getBulkOperation($id: ID!) {
          node(id: $id) {
            ... on BulkOperation {
              id
              status
              query
              createdAt
              completedAt
              objectCount
              fileSize
              url
              partialDataUrl
              errorCode
              type
            }
          }
        }
      GRAPHQL

      variables = { id: operation_id }
      response = query_admin_api(query, variables)
      response.dig("node")
    end

    # Parses JSONL content into an array of objects
    def parse_jsonl(content)
      results = []
      content.each_line do |line|
        line = line.strip
        next if line.empty?
        
        begin
          parsed = JSON.parse(line)
          results << parsed
        rescue JSON::ParserError => e
          logger.warn "Failed to parse JSONL line: #{line[0..100]}... Error: #{e.message}"
        end
      end
      
      logger.info "Parsed #{results.size} JSONL records"
      results
    end
  end
end