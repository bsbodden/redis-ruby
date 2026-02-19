# frozen_string_literal: true

module RR
  module DSL
    # Represents a field in a search index schema
    class SearchField
      attr_reader :name, :type, :options

      def initialize(name, type, **options)
        @name = name.to_s
        @type = type.to_sym
        @options = options
      end

      # Convert field definition to Redis command arguments
      #
      # @return [Array<String>] Field arguments for FT.CREATE
      def to_args
        args = build_field_name_args
        args << type_string
        append_type_options(args)
        append_general_options(args)
        args
      end

      private

      def build_field_name_args
        if @options[:as]
          [@name, "AS", @options[:as].to_s]
        else
          [@name]
        end
      end

      def append_type_options(args)
        case @type
        when :text then append_text_options(args)
        when :tag then append_tag_options(args)
        when :vector then build_vector_args(args)
        end
      end

      def append_text_options(args)
        args.push("WEIGHT", @options[:weight]) if @options[:weight]
        args.push("PHONETIC", @options[:phonetic]) if @options[:phonetic]
        args << "WITHSUFFIXTRIE" if @options[:withsuffixtrie]
      end

      def append_tag_options(args)
        args.push("SEPARATOR", @options[:separator]) if @options[:separator]
        args << "CASESENSITIVE" if @options[:casesensitive]
      end

      def append_general_options(args)
        args << "SORTABLE" if @options[:sortable]
        args << "NOINDEX" if @options[:noindex]
        args << "NOSTEM" if @options[:nostem]
      end

      def type_string
        case @type
        when :text then "TEXT"
        when :numeric then "NUMERIC"
        when :tag then "TAG"
        when :geo then "GEO"
        when :vector then "VECTOR"
        when :geoshape then "GEOSHAPE"
        else
          raise ArgumentError, "Unknown field type: #{@type}"
        end
      end

      def build_vector_args(args)
        return unless @options[:algorithm]

        args << @options[:algorithm].to_s.upcase
        attrs = build_vector_attrs
        args.push(attrs.size, *attrs) if attrs.any?
      end

      def build_vector_attrs
        attrs = []
        attrs.push("TYPE", @options[:vector_type].to_s.upcase) if @options[:vector_type]
        attrs.push("DIM", @options[:dim]) if @options[:dim]
        attrs.push("DISTANCE_METRIC", @options[:distance_metric].to_s.upcase) if @options[:distance_metric]
        append_algorithm_attrs(attrs)
        attrs
      end

      def append_algorithm_attrs(attrs)
        case @options[:algorithm]
        when :flat
          attrs.push("INITIAL_CAP", @options[:initial_cap]) if @options[:initial_cap]
        when :hnsw
          attrs.push("M", @options[:m]) if @options[:m]
          attrs.push("EF_CONSTRUCTION", @options[:ef_construction]) if @options[:ef_construction]
          attrs.push("EF_RUNTIME", @options[:ef_runtime]) if @options[:ef_runtime]
        end
      end
    end
  end
end
