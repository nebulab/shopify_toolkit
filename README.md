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

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add shopify_toolkit
```

## Usage

### Migrating Metafields and Metaobjects

Within a Rails application created with ShopifyApp, generate a new migration file:

```bash
bundle exec shopify-toolkit generate migration AddProductPressReleases
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

```shell
shopify-csv analyze products-result.csv --force-import
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
#<ShopifyCSV::Result:0x0000000300bf1668
 id: 1,
 data: nil,
 handle: "my-product",
 title: "My Product",
 import_result: "OK",
 import_comment: "UPDATE: Found by Handle | Assuming MERGE for Varia...">
>> count
=> 116103
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nebulab/shopify_toolkit.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
