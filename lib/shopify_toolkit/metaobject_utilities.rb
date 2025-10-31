# frozen_string_literal: true

require "active_support/concern"

module ShopifyToolkit::MetaobjectUtilities
  extend ActiveSupport::Concern
  include ShopifyToolkit::AdminClient

  def is_metaobject_reference_type?(type)
    type.to_sym.in?([:metaobject_reference, :"list.metaobject_reference", :mixed_reference, :"list.mixed_reference"])
  end

  def convert_validations_types_to_gids(validations)
    return validations unless validations&.any?

    validations.filter_map do |validation|
      convert_metaobject_validation(validation)
    end
  end

  def get_metaobject_definition_gid(type)
    result =
      shopify_admin_client
        .query(
          query:
            "# GraphQL
              query GetMetaobjectDefinitionID($type: String!) {
                metaobjectDefinitionByType(type: $type) {
                  id
                }
              }",
          variables: { type: type.to_s },
        )
        .tap { handle_shopify_admin_client_errors(_1) }
        .body

    gid = result.dig("data", "metaobjectDefinitionByType", "id")

    return gid
  end

  def get_metaobject_definition_type_by_gid(gid)
    result =
      shopify_admin_client
        .query(
          query:
            "# GraphQL
              query GetMetaobjectDefinitionType($id: ID!) {
                metaobjectDefinition(id: $id) {
                  type
                }
              }",
          variables: { id: gid },
        )
        .tap { handle_shopify_admin_client_errors(_1) }
        .body

    result.dig("data", "metaobjectDefinition", "type")
  end

  private

  def convert_metaobject_validation(validation)
    name = validation[:name] || validation["name"]
    value = validation[:value] || validation["value"]

    return validation unless metaobject_type_validation?(name) && value

    parsed_value = parse_json_if_needed(value)
    convert_types_to_gids(parsed_value)
  end

  def metaobject_type_validation?(name)
    name.in?(["metaobject_definition_type", "metaobject_definition_types"])
  end

  def parse_json_if_needed(value)
    return value unless value.is_a?(String) && value.start_with?("[") && value.end_with?("]")

    JSON.parse(value)
  rescue JSON::ParserError
    value
  end

  def convert_types_to_gids(value)
    if value.is_a?(Array)
      convert_array_types_to_gids(value)
    else
      convert_single_type_to_gid(value)
    end
  end

  def convert_array_types_to_gids(types)
    gids = types.map do |type|
      gid = get_metaobject_definition_gid(type)
      raise "Metaobject type '#{type}' not found" unless gid
      gid
    end
    { name: "metaobject_definition_ids", value: gids.to_json }
  end

  def convert_single_type_to_gid(type)
    gid = get_metaobject_definition_gid(type)
    raise "Metaobject type '#{type}' not found" unless gid
    { name: "metaobject_definition_id", value: gid }
  end
end
