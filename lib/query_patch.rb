require_dependency 'query'

# Mixin for introducing new Issue filters
module QueryPatch
  def self.included(base)
    base.extend(ClassMethods)
    base.send(:include, InstanceMethods)

    base.class_eval do
      unloadable

      # Introduce new "Artifacts Count" column
      artifacts_count_col = QueryColumn.new(:re_artifacts_count, :caption => :re_linked_artifacts_count)
      self.add_available_column(artifacts_count_col)

      # Wrap some methods
      alias_method_chain :available_filters, :re_filters
      alias_method_chain :sql_for_field, :re_filters
    end
  end

  module ClassMethods
  end

  module InstanceMethods
    # Overwrites and wraps the available_filters method to add custom filters
    def available_filters_with_re_filters
      @filters = available_filters_without_re_filters
      @filters["re_artifact_id"] = { :name => l(:re_linked_artifact),
                                     :type => :list,
                                     :order => 20,
                                     :values => selectable_artifact_types_and_names }
      @filters["re_artifact_type"] = { :name => l(:re_linked_artifact_type),
                                       :type => :list,
                                       :order => 21,
                                       :values => selectable_artifact_types }
      @filters
    end

    # Overwrites and wraps the sql_for_field method to introduce custom SQL conditions for specific filters
    def sql_for_field_with_re_filters(field, operator, value, db_table, db_field, is_custom_filter = false)
      case db_field
        when "re_artifact_id" # Filter for artifact
          sql_for_artifact_field(db_table, "id", value, true, operator == "!")
        when "re_artifact_type" # Filter for artifact type
          sql_for_artifact_field(db_table, "artifact_type", value, false, operator == "!")
        else
          sql_for_field_without_re_filters(field, operator, value, db_table, db_field, is_custom_filter)
      end
    end
  end

  private

  # Returns the localized name of the supplied artifact
  def localized_artifact_type(artifact_property)
    l artifact_property.artifact_type.underscore
  end

  # Outputs all artifacts' names prefixed by the particular artifact type (formatted for select box compatibility)
  def selectable_artifact_types_and_names
    artifacts = ReArtifactProperties.all(:conditions => ["artifact_type != ?", "Project"])
    artifacts.collect { |p| [ "[#{localized_artifact_type(p)}] #{p.name}", p.id.to_s ] }.sort! { |a, b| a.first <=> b.first }
  end

  # Outputs all artifact types (formatted for select box compatibility)
  def selectable_artifact_types
    artifacts = ReArtifactProperties.all(:conditions => ["artifact_type != ?", "Project"],
                                         :select => "DISTINCT(artifact_type)")
    artifacts.collect { |p| [ localized_artifact_type(p), p.artifact_type ] }.sort! { |a, b| a.first <=> b.first }
  end

  # Builds a SQL condition to filter for artifact properties
  def sql_for_artifact_field(db_table, db_field, value, is_numeric_value, invert)
    inner_sql = %{SELECT DISTINCT(#{db_table}.id) FROM realizations
                  INNER JOIN issues ON issues.id = realizations.issue_id
                  INNER JOIN re_artifact_properties ON re_artifact_properties.id = realizations.re_artifact_properties_id
                  WHERE re_artifact_properties.#{db_field}
                  IN (#{(is_numeric_value ? value : value.collect { |v| "'#{connection.quote_string(v)}'" }).join(",")})}
    "#{db_table}.id #{invert ? "NOT " : ""}IN (#{inner_sql})"
  end
end

Query.send(:include, QueryPatch)