# ShopifyToolkit

A toolkit for working with Custom Shopify Apps built on Rails.

### Assumptions

- You are using Rails 7.0 or later
- The custom app is only installed on a single store
- In order for the schema dump/load to work, you need to have the `shopify_app` gem installed and configured

## Features/Roadmap

- [x] Shopify/Matrixify CSV tools
- [x] Metafield/Metaobject migrations (just like ActiveRecord migrations, but for Shopify!)
- [x] Metafield Definitions management API
- [x] Metaobject Definitions management API
  - [x] Create
  - [x] Update
  - [x] Find
  - [ ] Delete
- [ ] Metaobject Instances management API
- [ ] GraphQL Admin API code generation (syntax checking, etc)
- [ ] GraphQL Admin API client with built-in rate limiting
- [ ] GraphQL Admin API client with built-in caching
- [ ] GraphQL Admin API client with built-in error handling
- [ ] GraphQL Admin API client with built-in logging
- [x] Bulk Operations
  - [x] Interface for uploading and getting results for query / mutation
  - [x] Error handling and Logging
  - [x] Callbacks
  - [x] CLI commands

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add shopify_toolkit
```

## Usage

### Migrating Metafields and Metaobjects

Within a Rails application created with ShopifyApp, generate a new migration file:

```bash
bundle exec shopify-toolkit generate_migration AddProductPressReleases
```

Then, add the following code to the migration file:

```ruby
# config/shopify/migrate/20250528130134_add_product_press_releases.rb
class AddProductPressReleases < ShopifyToolkit::Migration
  def up
    create_metaobject_definition :press_release,
      name: "Press Release",
      displayNameKey: "name",
      access: { storefront: "PUBLIC_READ" },
      capabilities: {
        onlineStore: { enabled: false },
        publishable: { enabled: true },
        translatable: { enabled: true },
        renderable: { enabled: false },
      },
      fieldDefinitions: [
        { key: "name", name: "Title", required: true, type: "single_line_text_field" },
        { key: "body", name: "Body", required: true, type: "multi_line_text_field" },
      ]

    metaobject_definition_id = get_metaobject_definition_gid :press_release

    create_metafield :products, :press_release, :metaobject_reference, name: "Press Release", validations: [
      { name: "metaobject_definition_id", value: metaobject_definition_id }
    ]
  end

  def down
    # Noop. We don't want to remove the metaobject definition, since it might be populated with data.
  end
end
```

Then run the migrations:

```bash
bundle exec shopify-toolkit migrate
```

### Creating a Metafield Schema Definition

You can also create a metafield schema definition file to define your metafields in a more structured way. This is useful for keeping track of your metafields and their definitions.

```rb
# config/shopify/schema.rb

ShopifyToolkit::MetafieldSchema.define do
  # Define your metafield schema here
  # For example:
  create_metafield :products, :my_metafield, :single_line_text_field, name: "My Metafield"
end
```

### Analyzing a Matrixify CSV Result files

Matrixify is a popular Shopify app that allows you to import/export data from Shopify using CSV files. The CSV files that Matrixify generates are very verbose and can be difficult to work with. This tool allows you to analyze the CSV files and extract the data you need.

The tool will import the file into a local SQLite database
and open a console for you to run queries against the data
using ActiveRecord.

> Note: To use it with `bundle exec`, sqlite3 must be included in the project’s bundle

```shell
shopify-toolkit analyze products-result.csv --force-import
==> Importing products-result.csv into /var/folders/hn/z7b7s1kj3js4k7_qk3lj27kr0000gn/T/shopify-toolkit-analyze-products_result_csv.sqlite3
-- create_table(:results, {:force=>true})
   -> 0.0181s
-- add_index(:results, :import_result)
   -> 0.0028s
........................
==> Starting console for products-result.csv
>> comments
=>
["UPDATE: Found by Handle | Assuming MERGE for Variant Command | Assuming MERGE for Tags Command | Variants updated by SKU: 1",
 "UPDATE: Found by Handle | Assuming MERGE for Variant Command | Assuming MERGE for Tags Command | Variants updated by SKU: 1 | Warning: The following media were not uploaded to Shopify: [https://mymedia.com/image.jpg: Error downloading from Web: 302 Moved Temporarily]",
 ...]
>> first
#<ShopifyToolkit::Result:0x0000000300bf1668
 id: 1,
 data: nil,
 handle: "my-product",
 title: "My Product",
 import_result: "OK",
 import_comment: "UPDATE: Found by Handle | Assuming MERGE for Varia...">
>> count
=> 116103
```

### Working with Bulk Operations

Bulk Operations allow you to asynchronously run large GraphQL queries and mutations against the Shopify Admin API without worrying about rate limits or managing pagination manually.

#### Ruby API

Include the `ShopifyToolkit::BulkOperations` module in your class to access bulk operations functionality:

```ruby
class MyService
  include ShopifyToolkit::BulkOperations
  
  def export_all_products
    query = <<~GRAPHQL
      {
        products {
          edges {
            node {
              id
              title
              handle
              productType
              vendor
              createdAt
              variants {
                edges {
                  node {
                    id
                    title
                    price
                    inventoryQuantity
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL
    
    # Submit the bulk query
    operation = run_bulk_query(query)
    operation_id = operation.dig("bulkOperation", "id")
    
    # Poll until completion
    completed = poll_until_complete(operation_id) do |status|
      puts "Status: #{status["status"]}, Objects: #{status["objectCount"]}"
    end
    
    # Download and parse results
    if completed["status"] == "COMPLETED"
      results = download_results(completed)
      puts "Downloaded #{results.size} products"
      return results
    end
  end
  
  def bulk_create_products(products_data)
    mutation = <<~GRAPHQL
      mutation createProduct($input: ProductInput!) {
        productCreate(input: $input) {
          product {
            id
            title
            handle
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL
    
    # Prepare variables for each product
    variables = products_data.map { |product| { input: product } }
    
    # Submit bulk mutation
    operation = run_bulk_mutation(mutation, variables)
    operation_id = operation.dig("bulkOperation", "id")
    
    # Wait for completion
    completed = poll_until_complete(operation_id)
    
    if completed["status"] == "COMPLETED"
      results = download_results(completed)
      puts "Created #{results.size} products"
      return results
    end
  end
end
```

#### CLI Commands

The gem provides several CLI commands for working with bulk operations:

##### Bulk Query

Submit a bulk GraphQL query:

```bash
# Submit a query and get the operation ID
shopify-toolkit bulk_query examples/bulk_query_products.graphql

# Submit and poll until completion, then download results
shopify-toolkit bulk_query examples/bulk_query_products.graphql --poll --output results.json

# Submit with object grouping enabled
shopify-toolkit bulk_query examples/bulk_query_products.graphql --group-objects
```

##### Bulk Mutation

Submit a bulk GraphQL mutation with variables:

```bash
# Submit a mutation with JSON variables file
shopify-toolkit bulk_mutation examples/bulk_mutation_products.graphql examples/bulk_mutation_variables.json

# Submit with JSONL variables file and poll for completion
shopify-toolkit bulk_mutation examples/bulk_mutation_products.graphql examples/bulk_mutation_variables.jsonl --poll

# Submit with a client identifier for tracking
shopify-toolkit bulk_mutation examples/bulk_mutation_products.graphql examples/bulk_mutation_variables.json --client-identifier "my-import-job"
```

##### Check Status

Check the status of a bulk operation:

```bash
# Check current bulk operation status
shopify-toolkit bulk_status

# Check status of specific operation
shopify-toolkit bulk_status gid://shopify/BulkOperation/123456

# Filter by operation type
shopify-toolkit bulk_status --type QUERY
```

##### Cancel Operation

Cancel a running bulk operation:

```bash
shopify-toolkit bulk_cancel gid://shopify/BulkOperation/123456
```

##### Download Results

Download and display results from a completed operation:

```bash
# Download results by operation ID
shopify-toolkit bulk_results gid://shopify/BulkOperation/123456 --output results.json

# Download results by direct URL
shopify-toolkit bulk_results "https://storage.googleapis.com/shopify/results.jsonl"

# Download raw JSONL without parsing
shopify-toolkit bulk_results gid://shopify/BulkOperation/123456 --raw --output results.jsonl
```

#### Example Files

The gem includes example files in the `examples/` directory:

- `bulk_query_products.graphql` - Query to fetch all products with variants
- `bulk_mutation_products.graphql` - Mutation to create products  
- `bulk_mutation_variables.json` - JSON format variables for mutations
- `bulk_mutation_variables.jsonl` - JSONL format variables for mutations

#### Error Handling

The module provides specific error classes:

- `ShopifyToolkit::BulkOperations::BulkOperationError` - General bulk operation errors
- `ShopifyToolkit::BulkOperations::OperationInProgressError` - Thrown when trying to start an operation while another is running

```ruby
begin
  operation = run_bulk_query(query)
rescue ShopifyToolkit::BulkOperations::OperationInProgressError
  puts "Another bulk operation is already running"
rescue ShopifyToolkit::BulkOperations::BulkOperationError => e
  puts "Bulk operation failed: #{e.message}"
  puts "Error code: #{e.error_code}" if e.error_code
  puts "User errors: #{e.user_errors}" if e.user_errors.any?
end
```

#### Features

- **Automatic staged file uploads** for bulk mutations
- **JSONL parsing and streaming** to handle large result files efficiently  
- **Comprehensive error handling** with specific error types
- **Progress polling** with customizable intervals and timeouts
- **Result downloading** with parsing options
- **Operation cancellation** support
- **CLI integration** for all bulk operations
- **Logging** for debugging and monitoring

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nebulab/shopify_toolkit.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
