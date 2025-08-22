# frozen_string_literal: true

require "spec_helper"

RSpec.describe ShopifyToolkit::BulkOperations do
  let(:bulk_operations) { Class.new { include ShopifyToolkit::BulkOperations }.new }
  let(:sample_query) do
    <<~GRAPHQL
      {
        products {
          edges {
            node {
              id
              title
              handle
            }
          }
        }
      }
    GRAPHQL
  end
  let(:sample_mutation) do
    <<~GRAPHQL
      mutation createProduct($input: ProductInput!) {
        productCreate(input: $input) {
          product {
            id
            title
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL
  end
  let(:sample_variables) do
    [
      { input: { title: "Product 1", productType: "Apparel" } },
      { input: { title: "Product 2", productType: "Apparel" } }
    ]
  end

  before do
    # Mock logger to avoid output during tests
    allow(bulk_operations).to receive(:logger).and_return(double("Logger", info: nil, warn: nil, error: nil))
  end

  describe "#run_bulk_query" do
    let(:successful_response) do
      {
        "bulkOperationRunQuery" => {
          "bulkOperation" => {
            "id" => "gid://shopify/BulkOperation/123456",
            "status" => "CREATED",
            "query" => sample_query.strip,
            "createdAt" => "2024-01-15T10:00:00Z",
            "completedAt" => nil,
            "objectCount" => "0",
            "fileSize" => nil,
            "url" => nil,
            "partialDataUrl" => nil,
            "errorCode" => nil,
            "type" => "QUERY"
          },
          "userErrors" => []
        }
      }
    end

    let(:error_response) do
      {
        "bulkOperationRunQuery" => {
          "bulkOperation" => nil,
          "userErrors" => [
            {
              "field" => ["query"],
              "message" => "Query is invalid",
              "code" => "INVALID"
            }
          ]
        }
      }
    end

    let(:operation_in_progress_response) do
      {
        "bulkOperationRunQuery" => {
          "bulkOperation" => nil,
          "userErrors" => [
            {
              "field" => [],
              "message" => "A bulk operation is already running",
              "code" => "OPERATION_IN_PROGRESS"
            }
          ]
        }
      }
    end

    it "submits a bulk query successfully" do
      expect(bulk_operations).to receive(:query).with(
        anything, 
        query: sample_query,
        groupObjects: false
      ).and_return(successful_response)

      result = bulk_operations.run_bulk_query(sample_query)

      expect(result).to eq(successful_response["bulkOperationRunQuery"])
      expect(result["bulkOperation"]["id"]).to eq("gid://shopify/BulkOperation/123456")
      expect(result["bulkOperation"]["status"]).to eq("CREATED")
    end

    it "submits a bulk query with group_objects option" do
      expect(bulk_operations).to receive(:query).with(
        anything,
        query: sample_query,
        groupObjects: true
      ).and_return(successful_response)

      bulk_operations.run_bulk_query(sample_query, group_objects: true)
    end

    it "raises BulkOperationError on query validation error" do
      expect(bulk_operations).to receive(:query).and_return(error_response)

      expect {
        bulk_operations.run_bulk_query(sample_query)
      }.to raise_error(ShopifyToolkit::BulkOperations::BulkOperationError, /Query is invalid/)
    end

    it "raises OperationInProgressError when another operation is running" do
      expect(bulk_operations).to receive(:query).and_return(operation_in_progress_response)

      expect {
        bulk_operations.run_bulk_query(sample_query)
      }.to raise_error(ShopifyToolkit::BulkOperations::OperationInProgressError, /already in progress/)
    end

    it "raises BulkOperationError on GraphQL query failure" do
      expect(bulk_operations).to receive(:query).and_raise(StandardError, "Network error")

      expect {
        bulk_operations.run_bulk_query(sample_query)
      }.to raise_error(ShopifyToolkit::BulkOperations::BulkOperationError, /GraphQL query failed.*Network error/)
    end
  end

  describe "#run_bulk_mutation" do
    let(:successful_staged_upload_response) do
      {
        "stagedUploadsCreate" => {
          "stagedTargets" => [
            {
              "url" => "https://example.com/upload",
              "resourceUrl" => nil,
              "parameters" => [
                { "name" => "key", "value" => "tmp/12345/bulk_vars" },
                { "name" => "Content-Type", "value" => "text/jsonl" }
              ]
            }
          ],
          "userErrors" => []
        }
      }
    end

    let(:successful_mutation_response) do
      {
        "bulkOperationRunMutation" => {
          "bulkOperation" => {
            "id" => "gid://shopify/BulkOperation/789012",
            "status" => "CREATED",
            "query" => sample_mutation,
            "createdAt" => "2024-01-15T10:00:00Z",
            "completedAt" => nil,
            "objectCount" => "0",
            "fileSize" => nil,
            "url" => nil,
            "partialDataUrl" => nil,
            "errorCode" => nil,
            "type" => "MUTATION"
          },
          "userErrors" => []
        }
      }
    end

    it "submits a bulk mutation successfully" do
      # Mock staged upload creation
      expect(bulk_operations).to receive(:query).with(
        anything,
        input: [{
          resource: "BULK_MUTATION_VARIABLES",
          filename: "bulk_mutation_variables.jsonl", 
          mimeType: "text/jsonl",
          httpMethod: "POST"
        }]
      ).and_return(successful_staged_upload_response)

      # Mock file upload
      expect(bulk_operations).to receive(:upload_to_staged_target).with(
        "https://example.com/upload",
        [
          { "name" => "key", "value" => "tmp/12345/bulk_vars" },
          { "name" => "Content-Type", "value" => "text/jsonl" }
        ],
        sample_variables.map { |vars| JSON.generate(vars) }.join("\n")
      )

      # Mock bulk mutation submission  
      expect(bulk_operations).to receive(:query).with(
        anything,
        mutation: sample_mutation,
        stagedUploadPath: "tmp/12345/bulk_vars",
        groupObjects: false
      ).and_return(successful_mutation_response)

      result = bulk_operations.run_bulk_mutation(sample_mutation, sample_variables)

      expect(result).to eq(successful_mutation_response["bulkOperationRunMutation"])
      expect(result["bulkOperation"]["id"]).to eq("gid://shopify/BulkOperation/789012")
    end

    it "raises BulkOperationError on staged upload failure" do
      failed_upload_response = {
        "stagedUploadsCreate" => {
          "stagedTargets" => [],
          "userErrors" => [
            {
              "field" => ["input"],
              "message" => "File size exceeds limit"
            }
          ]
        }
      }

      expect(bulk_operations).to receive(:query).and_return(failed_upload_response)

      expect {
        bulk_operations.run_bulk_mutation(sample_mutation, sample_variables)
      }.to raise_error(ShopifyToolkit::BulkOperations::BulkOperationError, /Failed to create staged upload/)
    end
  end

  describe "#current_bulk_operation" do
    let(:current_operation_response) do
      {
        "currentBulkOperation" => {
          "id" => "gid://shopify/BulkOperation/555555",
          "status" => "RUNNING",
          "query" => sample_query,
          "createdAt" => "2024-01-15T10:00:00Z",
          "completedAt" => nil,
          "objectCount" => "150",
          "fileSize" => nil,
          "url" => nil,
          "partialDataUrl" => nil,
          "errorCode" => nil,
          "type" => "QUERY"
        }
      }
    end

    let(:no_operation_response) do
      { "currentBulkOperation" => nil }
    end

    it "returns current bulk operation details" do
      expect(bulk_operations).to receive(:query).with(anything).and_return(current_operation_response)

      result = bulk_operations.current_bulk_operation

      expect(result).to eq(current_operation_response["currentBulkOperation"])
      expect(result["id"]).to eq("gid://shopify/BulkOperation/555555")
      expect(result["status"]).to eq("RUNNING")
    end

    it "returns nil when no operation exists" do
      expect(bulk_operations).to receive(:query).and_return(no_operation_response)

      result = bulk_operations.current_bulk_operation

      expect(result).to be_nil
    end

    it "filters by operation type" do
      expect(bulk_operations).to receive(:query).with(anything, type: "QUERY").and_return(current_operation_response)

      result = bulk_operations.current_bulk_operation(type: "QUERY")

      expect(result).to eq(current_operation_response["currentBulkOperation"])
    end
  end

  describe "#cancel_bulk_operation" do
    let(:operation_id) { "gid://shopify/BulkOperation/123456" }
    let(:successful_cancel_response) do
      {
        "bulkOperationCancel" => {
          "bulkOperation" => {
            "id" => operation_id,
            "status" => "CANCELED",
            "errorCode" => nil
          },
          "userErrors" => []
        }
      }
    end

    let(:failed_cancel_response) do
      {
        "bulkOperationCancel" => {
          "bulkOperation" => nil,
          "userErrors" => [
            {
              "field" => ["id"],
              "message" => "Operation not found"
            }
          ]
        }
      }
    end

    it "cancels a bulk operation successfully" do
      expect(bulk_operations).to receive(:query).with(
        anything,
        id: operation_id
      ).and_return(successful_cancel_response)

      result = bulk_operations.cancel_bulk_operation(operation_id)

      expect(result).to eq(successful_cancel_response["bulkOperationCancel"])
      expect(result["bulkOperation"]["status"]).to eq("CANCELED")
    end

    it "raises BulkOperationError on cancellation failure" do
      expect(bulk_operations).to receive(:query).and_return(failed_cancel_response)

      expect {
        bulk_operations.cancel_bulk_operation(operation_id)
      }.to raise_error(ShopifyToolkit::BulkOperations::BulkOperationError, /Failed to cancel.*Operation not found/)
    end
  end

  describe "#download_results" do
    let(:sample_jsonl) do
      <<~JSONL.strip
        {"id":"gid://shopify/Product/1","title":"Product 1","handle":"product-1"}
        {"id":"gid://shopify/Product/2","title":"Product 2","handle":"product-2"}
      JSONL
    end
    let(:results_url) { "https://storage.googleapis.com/shopify/results.jsonl" }
    let(:operation_with_url) { { "url" => results_url } }

    it "downloads and parses JSONL results from URL" do
      uri_double = double("URI")
      allow(URI).to receive(:parse).with(results_url).and_return(uri_double)
      mock_response = double("HTTPResponse", is_a?: true, body: sample_jsonl)
      expect(Net::HTTP).to receive(:get_response).with(uri_double).and_return(mock_response)

      results = bulk_operations.download_results(results_url)

      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
      expect(results[0]["title"]).to eq("Product 1")
      expect(results[1]["title"]).to eq("Product 2")
    end

    it "downloads and parses JSONL results from operation hash" do
      uri_double = double("URI")
      allow(URI).to receive(:parse).with(results_url).and_return(uri_double)
      mock_response = double("HTTPResponse", is_a?: true, body: sample_jsonl)
      expect(Net::HTTP).to receive(:get_response).with(uri_double).and_return(mock_response)

      results = bulk_operations.download_results(operation_with_url)

      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
    end

    it "returns raw JSONL when parse_results is false" do
      uri_double = double("URI")
      allow(URI).to receive(:parse).with(results_url).and_return(uri_double)
      mock_response = double("HTTPResponse", is_a?: true, body: sample_jsonl)
      expect(Net::HTTP).to receive(:get_response).with(uri_double).and_return(mock_response)

      result = bulk_operations.download_results(results_url, parse_results: false)

      expect(result).to be_a(String)
      expect(result).to eq(sample_jsonl)
    end

    it "returns nil when no URL is provided" do
      result = bulk_operations.download_results({ "url" => nil })
      expect(result).to be_nil

      result = bulk_operations.download_results(nil)
      expect(result).to be_nil
    end

    it "raises BulkOperationError on download failure" do
      uri_double = double("URI")
      allow(URI).to receive(:parse).with(results_url).and_return(uri_double)
      mock_response = double("HTTPResponse", is_a?: false, code: "404", message: "Not Found")
      expect(Net::HTTP).to receive(:get_response).with(uri_double).and_return(mock_response)

      expect {
        bulk_operations.download_results(results_url)
      }.to raise_error(ShopifyToolkit::BulkOperations::BulkOperationError, /Failed to download results: 404 Not Found/)
    end
  end

  describe "#poll_until_complete" do
    let(:operation_id) { "gid://shopify/BulkOperation/123456" }
    let(:running_operation) do
      {
        "id" => operation_id,
        "status" => "RUNNING",
        "createdAt" => "2024-01-15T10:00:00Z",
        "objectCount" => "50"
      }
    end
    let(:completed_operation) do
      running_operation.merge("status" => "COMPLETED", "completedAt" => "2024-01-15T10:05:00Z")
    end

    it "polls until operation completes" do
      expect(bulk_operations).to receive(:get_bulk_operation_by_id).with(operation_id).and_return(running_operation, completed_operation)

      yielded_statuses = []
      result = bulk_operations.poll_until_complete(operation_id, poll_interval: 0.1) do |status|
        yielded_statuses << status["status"]
      end

      expect(yielded_statuses).to eq(["RUNNING", "COMPLETED"])
      expect(result).to eq(completed_operation)
    end

    it "raises timeout error when operation takes too long" do
      expect(bulk_operations).to receive(:get_bulk_operation_by_id).with(operation_id).and_return(running_operation).at_least(:twice)

      expect {
        bulk_operations.poll_until_complete(operation_id, poll_interval: 0.1, timeout: 0.2)
      }.to raise_error(ShopifyToolkit::BulkOperations::BulkOperationError, /Polling timeout exceeded/)
    end

    it "returns immediately for failed operations" do
      failed_operation = running_operation.merge("status" => "FAILED", "errorCode" => "TIMEOUT")
      expect(bulk_operations).to receive(:get_bulk_operation_by_id).with(operation_id).and_return(failed_operation)

      result = bulk_operations.poll_until_complete(operation_id)

      expect(result).to eq(failed_operation)
    end
  end

  describe "private methods" do
    describe "#parse_jsonl" do
      let(:valid_jsonl) do
        <<~JSONL.strip
          {"id": 1, "name": "Product 1"}
          {"id": 2, "name": "Product 2"}
        JSONL
      end

      let(:invalid_jsonl) do
        <<~JSONL.strip
          {"id": 1, "name": "Product 1"}
          {invalid json line}
          {"id": 2, "name": "Product 2"}
        JSONL
      end

      it "parses valid JSONL content" do
        results = bulk_operations.send(:parse_jsonl, valid_jsonl)

        expect(results).to be_an(Array)
        expect(results.size).to eq(2)
        expect(results[0]).to eq({ "id" => 1, "name" => "Product 1" })
        expect(results[1]).to eq({ "id" => 2, "name" => "Product 2" })
      end

      it "skips invalid JSON lines and logs warnings" do
        expect(bulk_operations.logger).to receive(:warn).with(/Failed to parse JSONL line/)

        results = bulk_operations.send(:parse_jsonl, invalid_jsonl)

        expect(results).to be_an(Array)
        expect(results.size).to eq(2)
        expect(results.map { |r| r["id"] }).to eq([1, 2])
      end

      it "handles empty lines" do
        jsonl_with_empty_lines = "#{valid_jsonl}\n\n\n"
        
        results = bulk_operations.send(:parse_jsonl, jsonl_with_empty_lines)
        
        expect(results.size).to eq(2)
      end
    end
  end

  describe "error classes" do
    describe ShopifyToolkit::BulkOperations::BulkOperationError do
      it "stores error code and user errors" do
        user_errors = [{ "field" => ["query"], "message" => "Invalid query" }]
        error = ShopifyToolkit::BulkOperations::BulkOperationError.new(
          "Test error",
          error_code: "INVALID",
          user_errors: user_errors
        )

        expect(error.message).to eq("Test error")
        expect(error.error_code).to eq("INVALID")
        expect(error.user_errors).to eq(user_errors)
      end
    end

    describe ShopifyToolkit::BulkOperations::OperationInProgressError do
      it "inherits from BulkOperationError" do
        error = ShopifyToolkit::BulkOperations::OperationInProgressError.new("Operation in progress")
        expect(error).to be_a(ShopifyToolkit::BulkOperations::BulkOperationError)
      end
    end
  end
end