# ShopifyToolkit

A toolkit for working with Custom Shopify Apps built on Rails.

## Features/Roadmap

- [ ] Metafield/Metaobject migrations (just like ActiveRecord migrations, but for Shopify!)
- [ ] Shopify CSV Import/Export tools
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
