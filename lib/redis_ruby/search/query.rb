# frozen_string_literal: true

module RR
  module Search
    # Object-oriented query builder for RediSearch
    #
    # Provides a fluent interface for constructing FT.SEARCH queries
    # with support for filters, sorting, pagination, and highlighting.
    #
    # @example Basic query
    #   query = Query.new("hello world")
    #   client.ft_search("myindex", query.to_s)
    #
    # @example With filters and pagination
    #   query = Query.new("*")
    #     .filter("price", 10, 100)
    #     .filter("category", "electronics")
    #     .sort_by("price", :asc)
    #     .limit(0, 10)
    #   client.ft_search("myindex", query.to_s, **query.options)
    #
    # @example With highlighting
    #   query = Query.new("hello")
    #     .highlight(fields: ["title", "body"], tags: ["<b>", "</b>"])
    #     .summarize(fields: ["body"], frags: 3)
    #
    # @example Vector similarity search
    #   query = Query.new("*=>[KNN 10 @embedding $vec AS score]")
    #     .params(vec: embedding_bytes)
    #     .dialect(2)
    #
    class Query
      attr_reader :query_string

      # Initialize a new query
      #
      # @param query_string [String] The search query
      def initialize(query_string = "*")
        @query_string = query_string
        @filters = []
        @params = {}
        initialize_field_options
        initialize_flags
      end

      private

      # Initialize field, sort, and pagination options
      def initialize_field_options
        @return_fields = nil
        @sort_by = nil
        @limit_offset = 0
        @limit_num = 10
        @highlight_opts = nil
        @summarize_opts = nil
      end

      # Initialize boolean flags and advanced search options
      def initialize_flags
        @dialect = nil
        @verbatim = false
        @no_content = false
        @no_stopwords = false
        @with_scores = false
        @with_payloads = false
        @with_sort_keys = false
        @in_order = false
        @scorer = nil
        @expander = nil
        @slop = nil
        @language = nil
        @geo_filter = nil
      end

      public

      # Add a numeric filter
      #
      # @param field [String] Field name
      # @param min [Numeric, String] Minimum value (use "-inf" for no min)
      # @param max [Numeric, String] Maximum value (use "+inf" for no max)
      # @return [self]
      def filter_numeric(field, min, max)
        @filters << { type: :numeric, field: field, min: min, max: max }
        self
      end

      # Add a tag filter
      #
      # @param field [String] Field name
      # @param tags [Array<String>, String] Tag value(s)
      # @return [self]
      def filter_tag(field, *tags)
        tag_values = tags.flatten.map { |t| t.include?(" ") ? "\"#{t}\"" : t }
        @filters << { type: :tag, field: field, values: tag_values }
        self
      end

      # Add a geo filter
      #
      # @param field [String] Field name
      # @param lon [Float] Longitude
      # @param lat [Float] Latitude
      # @param radius [Numeric] Search radius
      # @param unit [Symbol] Unit (:km, :m, :mi, :ft)
      # @return [self]
      def filter_geo(field, lon, lat, radius, unit: :km)
        @geo_filter = { field: field, lon: lon, lat: lat, radius: radius, unit: unit }
        self
      end

      # Specify fields to return
      #
      # @param fields [Array<String>] Field names
      # @return [self]
      def return_fields(*fields)
        @return_fields = fields.flatten
        self
      end

      # Sort results by a field
      #
      # @param field [String] Field name
      # @param order [Symbol] :asc or :desc
      # @return [self]
      def sort_by(field, order = :asc)
        @sort_by = { field: field, order: order }
        self
      end

      # Set pagination limits
      #
      # @param offset [Integer] Starting position
      # @param num [Integer] Number of results
      # @return [self]
      def limit(offset, num)
        @limit_offset = offset
        @limit_num = num
        self
      end

      # Alias for limit with page semantics
      #
      # @param page [Integer] Page number (0-indexed)
      # @param per_page [Integer] Results per page
      # @return [self]
      def paginate(page, per_page)
        limit(page * per_page, per_page)
      end

      # Enable highlighting
      #
      # @param fields [Array<String>, nil] Fields to highlight (nil = all)
      # @param tags [Array<String>] Open/close tags (default: <b></b>)
      # @return [self]
      def highlight(fields: nil, tags: ["<b>", "</b>"])
        @highlight_opts = { fields: fields, tags: tags }
        self
      end

      # Enable summarization
      #
      # @param fields [Array<String>, nil] Fields to summarize (nil = all)
      # @param frags [Integer] Number of fragments
      # @param len [Integer] Fragment length
      # @param separator [String] Fragment separator
      # @return [self]
      def summarize(fields: nil, frags: 3, len: 20, separator: "...")
        @summarize_opts = { fields: fields, frags: frags, len: len, separator: separator }
        self
      end

      # Add query parameters (for parameterized queries)
      # @param params [Hash] Parameter name => value
      # @return [self]
      def params(params)
        @params.merge!(params)
        self
      end

      # Set query dialect
      # @param version [Integer] Dialect version (1, 2, or 3)
      # @return [self]
      def dialect(version)
        @dialect = version
        self
      end

      # Enable verbatim mode (no stemming)
      # @return [self]
      def verbatim
        @verbatim = true
        self
      end

      # Don't return document content
      # @return [self]
      def no_content
        @no_content = true
        self
      end

      # Disable stopword filtering
      #
      # @return [self]
      def no_stopwords
        @no_stopwords = true
        self
      end

      # Include scores in results
      #
      # @return [self]
      def with_scores
        @with_scores = true
        self
      end

      # Include payloads in results
      #
      # @return [self]
      def with_payloads
        @with_payloads = true
        self
      end

      # Include sort keys in results
      #
      # @return [self]
      def with_sort_keys
        @with_sort_keys = true
        self
      end

      # Set custom scorer
      #
      # @param name [String] Scorer name
      # @return [self]
      def scorer(name)
        @scorer = name
        self
      end

      # Set query expander
      #
      # @param name [String] Expander name
      # @return [self]
      def expander(name)
        @expander = name
        self
      end

      # Set slop (word distance)
      #
      # @param value [Integer] Maximum word distance
      # @return [self]
      def slop(value)
        @slop = value
        self
      end

      # Require terms in order
      #
      # @return [self]
      def in_order
        @in_order = true
        self
      end

      # Set query language
      #
      # @param lang [String] Language code
      # @return [self]
      def language(lang)
        @language = lang
        self
      end

      # Build the full query string with filters
      #
      # @return [String]
      def to_s
        parts = [@query_string]

        @filters.each do |filter|
          case filter[:type]
          when :numeric
            parts << "@#{filter[:field]}:[#{filter[:min]} #{filter[:max]}]"
          when :tag
            parts << "@#{filter[:field]}:{#{filter[:values].join(" | ")}}"
          end
        end

        parts.join(" ")
      end

      # Get options hash for ft_search
      #
      # @return [Hash]
      def options
        opts = {}
        build_field_and_sort_options(opts)
        build_highlight_options(opts)
        build_summarize_options(opts)
        build_query_flags(opts)
        build_advanced_options(opts)
        opts
      end

      private

      # Build return fields, sorting, and pagination options
      def build_field_and_sort_options(opts)
        opts[:return] = @return_fields if @return_fields
        if @sort_by
          opts[:sortby] = @sort_by[:field]
          opts[:sortby_order] = @sort_by[:order]
        end
        opts[:limit] = [@limit_offset, @limit_num]
      end

      # Build highlight options
      def build_highlight_options(opts)
        return unless @highlight_opts

        opts[:highlight] = true
        opts[:highlight_fields] = @highlight_opts[:fields] if @highlight_opts[:fields]
        opts[:highlight_tags] = @highlight_opts[:tags]
      end

      # Build summarize options
      def build_summarize_options(opts)
        return unless @summarize_opts

        opts[:summarize] = true
        opts[:summarize_fields] = @summarize_opts[:fields] if @summarize_opts[:fields]
        opts[:summarize_frags] = @summarize_opts[:frags]
        opts[:summarize_len] = @summarize_opts[:len]
        opts[:summarize_separator] = @summarize_opts[:separator]
      end

      # Build params and dialect options
      def build_query_flags(opts)
        opts[:params] = @params unless @params.empty?
        opts[:dialect] = @dialect if @dialect
        build_boolean_flags(opts)
      end

      # Build boolean on/off flags
      def build_boolean_flags(opts)
        opts[:verbatim] = true if @verbatim
        opts[:nocontent] = true if @no_content
        opts[:nostopwords] = true if @no_stopwords
        opts[:withscores] = true if @with_scores
        opts[:withpayloads] = true if @with_payloads
        opts[:withsortkeys] = true if @with_sort_keys
      end

      # Build advanced search options (scorer, expander, slop, geo)
      def build_advanced_options(opts)
        opts[:scorer] = @scorer if @scorer
        opts[:expander] = @expander if @expander
        opts[:slop] = @slop if @slop
        opts[:inorder] = true if @in_order
        opts[:language] = @language if @language
        return unless @geo_filter

        gf = @geo_filter
        opts[:geofilter] = [gf[:field], gf[:lon], gf[:lat], gf[:radius], gf[:unit].to_s]
      end

      public

      # Execute the query
      #
      # @param [RR::Client] Redis client
      # @param index [String] Index name
      # @return [Array] Search results
      def execute(client, index)
        client.ft_search(index, to_s, **options)
      end
    end

    # Aggregation query builder for RediSearch
    #
    # @example
    #   agg = AggregateQuery.new("*")
    #     .group_by("@category", reducers: [
    #       Reducer.count.as("count"),
    #       Reducer.avg("@price").as("avg_price")
    #     ])
    #     .sort_by("@count", :desc)
    #     .limit(0, 10)
    #
    class AggregateQuery
      # Initialize a new aggregation query
      #
      # @param query_string [String] Filter query
      def initialize(query_string = "*")
        @query_string = query_string
        @load_fields = nil
        @group_by = []
        @sort_by = nil
        @limit_offset = 0
        @limit_num = 10
        @apply = []
        @filter = []
        @dialect = nil
      end

      # Load specific fields
      #
      # @param fields [Array<String>] Field names
      # @return [self]
      def load(*fields)
        @load_fields = fields.flatten
        self
      end

      # Group by fields with reducers
      #
      # @param fields [Array<String>] Fields to group by
      # @param reducers [Array<Reducer>] Reducer functions
      # @return [self]
      def group_by(*fields, reducers: [])
        @group_by << { fields: fields.flatten, reducers: reducers }
        self
      end

      # Sort results
      #
      # @param field [String] Field to sort by
      # @param order [Symbol] :asc or :desc
      # @return [self]
      def sort_by(field, order = :asc)
        @sort_by = { field: field, order: order }
        self
      end

      # Set pagination
      #
      # @param offset [Integer] Starting position
      # @param num [Integer] Number of results
      # @return [self]
      def limit(offset, num)
        @limit_offset = offset
        @limit_num = num
        self
      end

      # Apply a transformation
      #
      # @param expression [String] Expression to apply
      # @param as [String] Result field name
      # @return [self]
      def apply(expression, as:)
        @apply << { expression: expression, as: as }
        self
      end

      # Add a filter step
      #
      # @param expression [String] Filter expression
      # @return [self]
      def filter(expression)
        @filter << expression
        self
      end

      # Set dialect version
      #
      # @param version [Integer] Dialect version
      # @return [self]
      def dialect(version)
        @dialect = version
        self
      end

      # Get the query string
      #
      # @return [String]
      def to_s
        @query_string
      end

      # Get aggregation options
      #
      # @return [Hash]
      def options
        opts = {}
        build_aggregate_load_and_group(opts)
        build_aggregate_sort_and_limit(opts)
        build_aggregate_pipeline_options(opts)
        opts
      end

      private

      # Build load and groupby options
      def build_aggregate_load_and_group(opts)
        opts[:load] = @load_fields if @load_fields
        return if @group_by.empty?

        opts[:groupby] = @group_by.map do |g|
          { fields: g[:fields], reducers: g[:reducers].map(&:to_args) }
        end
      end

      # Build sort and limit options
      def build_aggregate_sort_and_limit(opts)
        if @sort_by
          opts[:sortby] = @sort_by[:field]
          opts[:sortby_order] = @sort_by[:order]
        end
        opts[:limit] = [@limit_offset, @limit_num]
      end

      # Build apply, filter, and dialect pipeline options
      def build_aggregate_pipeline_options(opts)
        opts[:apply] = @apply unless @apply.empty?
        opts[:filter] = @filter unless @filter.empty?
        opts[:dialect] = @dialect if @dialect
      end

      public

      # Execute the aggregation
      #
      # @param [RR::Client] Redis client
      # @param index [String] Index name
      # @return [Array] Aggregation results
      def execute(client, index)
        client.ft_aggregate(index, to_s, **options)
      end
    end

    # Reducer functions for aggregation
    class Reducer
      attr_reader :function, :args, :alias_name

      def initialize(function, *args)
        @function = function
        @args = args
        @alias_name = nil
      end

      # Set the alias for this reducer
      #
      # @param name [String] Alias name
      # @return [self]
      def as(name)
        @alias_name = name
        self
      end

      # Convert to arguments array
      #
      # @return [Array]
      def to_args
        result = [@function] + @args
        result += ["AS", @alias_name] if @alias_name
        result
      end

      class << self
        def count
          Reducer.new("COUNT")
        end

        def count_distinct(field)
          Reducer.new("COUNT_DISTINCT", field)
        end

        def count_distinctish(field)
          Reducer.new("COUNT_DISTINCTISH", field)
        end

        def sum(field)
          Reducer.new("SUM", field)
        end

        def min(field)
          Reducer.new("MIN", field)
        end

        def max(field)
          Reducer.new("MAX", field)
        end

        def avg(field)
          Reducer.new("AVG", field)
        end

        def stddev(field)
          Reducer.new("STDDEV", field)
        end

        def quantile(field, percentile)
          Reducer.new("QUANTILE", field, percentile)
        end

        def tolist(field)
          Reducer.new("TOLIST", field)
        end

        def first_value(field, by: nil, order: :asc)
          args = [field]
          args += ["BY", by, order.to_s.upcase] if by
          Reducer.new("FIRST_VALUE", *args)
        end

        def random_sample(field, sample_size)
          Reducer.new("RANDOM_SAMPLE", field, sample_size)
        end
      end
    end
  end
end
