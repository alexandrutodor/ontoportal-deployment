require "ontologies_linked_data/utils/ontology_csv_writer"

begin
  require "rdf"
rescue LoadError
end

module LinkedData
  module Utils
    class OntologyCSVWriter
      def get_parent_ids(parents)
        Array(parents)
          .filter_map { |parent| matportal_parent_identifier(parent) }
          .uniq
          .join("|")
      end

      private

      def matportal_parent_identifier(parent)
        case parent
        when nil
          nil
        when Array
          candidates = parent.reverse_each.filter_map do |value|
            matportal_parent_identifier(value)
          end
          candidates.find { |value| matportal_probable_parent_identifier?(value) } || candidates.first
        else
          value = if parent.respond_to?(:id) && !parent.id.nil?
                    parent.id.to_s.strip
                  elsif defined?(RDF::URI) && parent.is_a?(RDF::URI)
                    parent.to_s.strip
                  elsif parent.respond_to?(:to_uri)
                    parent.to_uri.to_s.strip
                  elsif parent.is_a?(String)
                    parent.strip
                  else
                    parent.to_s.strip
                  end
          return nil if value.empty? || value.start_with?("@") || value.start_with?("#<")
          return value if matportal_probable_parent_identifier?(value)

          parent.is_a?(String) ? nil : value
        end
      rescue StandardError
        nil
      end

      def matportal_probable_parent_identifier?(value)
        return false if value.nil? || value.empty?

        value.include?("://") ||
          value.start_with?("urn:", "obo:", "doi:") ||
          value.match?(/\A[a-z][a-z0-9+.-]*:[^\s]+\z/i)
      end
    end
  end
end
