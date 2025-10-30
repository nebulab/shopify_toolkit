# frozen_string_literal: true

require "active_support/concern"

module ShopifyToolkit::MetaobjectStatements
  extend ActiveSupport::Concern
  include ShopifyToolkit::Migration::Logging
  include ShopifyToolkit::AdminClient
  include ShopifyToolkit::MetaobjectUtilities

  @@pending_field_validations = []

  def self.log_time(method_name)
    current_method = instance_method(method_name)
    define_method(method_name) do |*args, **kwargs, &block|
      say_with_time("#{method_name}(#{args.map(&:inspect).join(', ')})") { current_method.bind(self).call(*args, **kwargs, &block) }
    end
  end

  def apply_pending_field_validations
    return if @@pending_field_validations.empty?
    
    say "Applying #{@@pending_field_validations.size} pending field validations"
    
    @@pending_field_validations.reject! do |item|
      metaobject_type = item[:metaobject_type]
      field_key = item[:field_key]
      validations = item[:validations]
      
      begin
        success = add_field_validations_to_metaobject(metaobject_type, field_key, validations, item)
        unless success
          say "-- Deferring field '#{field_key}' in '#{metaobject_type}' (missing dependencies)"
        end
        success
      rescue StandardError => e
        say "-- Failed to process field '#{field_key}' in '#{metaobject_type}': #{e.message}"
        true # Remove from array (don't retry errors)
      end
    end
  end

  log_time \
  def create_metaobject_definition(type, **options)
    # Skip creation if metaobject already exists
    existing_gid = get_metaobject_definition_gid(type)
    if existing_gid
      say "Metaobject #{type} already exists, skipping creation"
      return existing_gid
    end

    # Transform options for GraphQL API
    definition = options.merge(type: type.to_s)

    begin
      # Convert field_definitions to fieldDefinitions and transform field structure
      if options[:field_definitions]
        definition[:fieldDefinitions] = options[:field_definitions].filter_map do |field|
          field_def = build_field_definition(field)
          field_needs_validations = is_metaobject_reference_type?(field[:type])
          
          if field[:validations]
            begin
              converted_validations = convert_validations_types_to_gids(field[:validations])
              field_def[:validations] = converted_validations if converted_validations&.any?
            rescue RuntimeError => e
              if e.message.include?("not found")
                @@pending_field_validations << {
                  metaobject_type: type,
                  field_key: field[:key],
                  field_definition: field,
                  validations: field[:validations]
                }
                say "Deferring field '#{field[:key]}' in '#{type}' (missing dependency)"
                
                if field_needs_validations
                  next # Skip this field entirely
                end
              end
            end
          elsif field_needs_validations
            next # Skip fields that need validations but don't have any
          end

          field_def
        end
        
        definition.delete(:field_definitions)
      end

      # Remove admin access to avoid API restrictions
      if definition[:access]&.is_a?(Hash)
        definition[:access] = definition[:access].dup
        definition[:access].delete("admin") if definition[:access]["admin"]
        definition.delete(:access) if definition[:access].empty?
      end

      # Clean up empty validations arrays that cause API errors
      if definition[:fieldDefinitions]
        definition[:fieldDefinitions].each do |field_def|
          field_def.delete(:validations) if field_def[:validations]&.empty?
        end
      end
      
      result = create_metaobject_definition_immediate(definition)
      result
    end
  end

  def add_field_validations_to_metaobject(metaobject_type, field_key, validations, item = nil)
    # Get the existing metaobject definition
    existing_gid = get_metaobject_definition_gid(metaobject_type)
    unless existing_gid
      say "Error: Cannot add validations to '#{metaobject_type}' - metaobject not found"
      return false
    end

    begin
      converted_validations = convert_validations_types_to_gids(validations)
      
      if converted_validations&.any?
        # Use the passed item, or try to find it (for backward compatibility)
        if item.nil?
          item = @@pending_field_validations.find { |pending_item| 
            pending_item[:metaobject_type] == metaobject_type && pending_item[:field_key] == field_key 
          }
        end
        
        if item && item[:field_definition]
          field_def = item[:field_definition]
          new_field = build_field_definition(field_def, converted_validations)
          
          field_operation = { create: new_field }
          update_metaobject_definition(metaobject_type, fieldDefinitions: [field_operation])
          
          say "Added field '#{field_key}' to '#{metaobject_type}'"
          return true
        else
          return false
        end
      else
        return false
      end
      
    rescue RuntimeError
      return false # Keep trying later or don't retry errors
    end
  end

  private

  def build_field_definition(field, validations = nil)
    field_def = {
      key: field[:key].to_s,
      name: field[:name],
      type: field[:type].to_s
    }
    field_def[:description] = field[:description] if field[:description]
    field_def[:required] = field[:required] if field[:required]
    field_def[:validations] = validations if validations&.any?
    field_def
  end

  def create_metaobject_definition_immediate(definition)
    # https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metaobjectDefinitionCreate
    query =
      "# GraphQL
      mutation CreateMetaobjectDefinition($definition: MetaobjectDefinitionCreateInput!) {
        metaobjectDefinitionCreate(definition: $definition) {
          metaobjectDefinition {
            id
            name
            type
            fieldDefinitions {
              name
              key
            }
          }
          userErrors {
            field
            message
            code
          }
        }
      }
      "
    variables = { definition: definition }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectDefinitionCreate.userErrors") }
  end

  def update_metaobject_definition(type, **options)
    existing_gid = get_metaobject_definition_gid(type)

    raise "Metaobject #{type} does not exist" unless existing_gid

    # https://shopify.dev/docs/api/admin-graphql/2024-10/mutations/metaobjectDefinitionUpdate
    query =
      "# GraphQL
      mutation UpdateMetaobjectDefinition($id: ID!, $definition: MetaobjectDefinitionUpdateInput!) {
        metaobjectDefinitionUpdate(id: $id, definition: $definition) {
          metaobjectDefinition {
            id
            name
            type
            fieldDefinitions {
              name
              key
            }
          }
          userErrors {
            field
            message
            code
          }
        }
      }
    "
    variables = { id: existing_gid, definition: { **options } }

    shopify_admin_client
      .query(query:, variables:)
      .tap { handle_shopify_admin_client_errors(_1, "data.metaobjectDefinitionUpdate.userErrors") }
  end

  def self.define(&block)
    context = Object.new
    context.extend(self)

    context.instance_eval(&block) if block_given?(&block)
    context
  end
end
