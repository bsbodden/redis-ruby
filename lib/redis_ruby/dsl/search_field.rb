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
      # Format: fieldname [AS alias] TYPE [type-options] [SORTABLE] [NOINDEX] [NOSTEM]
      def to_args
        args = []

        # For JSON paths, format is: $.path AS alias TYPE options
        # For regular fields, format is: name TYPE options
        if @options[:as]
          args.push(@name, "AS", @options[:as].to_s)
        else
          args.push(@name)
        end

        # Add type
        args << type_string

        # Type-specific options (must come before general options)
        case @type
        when :text
          args.push("WEIGHT", @options[:weight]) if @options[:weight]
          args.push("PHONETIC", @options[:phonetic]) if @options[:phonetic]
          args << "WITHSUFFIXTRIE" if @options[:withsuffixtrie]
        when :numeric
          # No additional options for numeric
        when :tag
          args.push("SEPARATOR", @options[:separator]) if @options[:separator]
          args << "CASESENSITIVE" if @options[:casesensitive]
        when :geo
          # No additional options for geo
        when :vector
          build_vector_args(args)
        when :geoshape
          # No additional options for geoshape
        end

        # General field options (must come after type-specific options)
        args << "SORTABLE" if @options[:sortable]
        args << "NOINDEX" if @options[:noindex]
        args << "NOSTEM" if @options[:nostem]

        args
      end

      private

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

        # Vector attributes
        attrs = []
        attrs.push("TYPE", @options[:vector_type].to_s.upcase) if @options[:vector_type]
        attrs.push("DIM", @options[:dim]) if @options[:dim]
        attrs.push("DISTANCE_METRIC", @options[:distance_metric].to_s.upcase) if @options[:distance_metric]

        # Algorithm-specific parameters
        if @options[:algorithm] == :flat
          attrs.push("INITIAL_CAP", @options[:initial_cap]) if @options[:initial_cap]
        elsif @options[:algorithm] == :hnsw
          attrs.push("M", @options[:m]) if @options[:m]
          attrs.push("EF_CONSTRUCTION", @options[:ef_construction]) if @options[:ef_construction]
          attrs.push("EF_RUNTIME", @options[:ef_runtime]) if @options[:ef_runtime]
        end

        args.push(attrs.size, *attrs) if attrs.any?
      end
    end
  end
end

