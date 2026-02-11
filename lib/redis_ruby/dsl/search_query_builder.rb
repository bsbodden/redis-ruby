# frozen_string_literal: true

module RedisRuby
  module DSL
    # Fluent builder for search queries
    #
    # @example
    #   redis.search(:products)
    #     .query("laptop")
    #     .filter(:price, 0..1000)
    #     .sort_by(:price, :asc)
    #     .limit(20)
    #     .with_scores
    #     .execute
    class SearchQueryBuilder
      def initialize(index_name, client)
        @index_name = index_name.to_s
        @client = client
        @query = "*"
        @options = {}
      end

      # Set the query string
      #
      # @param query_string [String] Query string
      # @return [self]
      def query(query_string)
        @query = query_string
        self
      end

      # Add numeric filter
      #
      # @param field [Symbol, String] Field name
      # @param range [Range, Array] Range or [min, max]
      # @return [self]
      def filter(field, range)
        @options[:filter] ||= {}
        min, max = range.is_a?(Range) ? [range.begin, range.end] : range
        @options[:filter][field.to_sym] = [min, max]
        self
      end

      # Add geo filter
      #
      # @param field [Symbol, String] Field name
      # @param lon [Float] Longitude
      # @param lat [Float] Latitude
      # @param radius [Float] Radius
      # @param unit [Symbol] Unit (:m, :km, :mi, :ft)
      # @return [self]
      def geofilter(field, lon, lat, radius, unit = :km)
        @options[:geofilter] ||= {}
        @options[:geofilter][field.to_sym] = [lon, lat, radius, unit.to_s]
        self
      end

      # Limit results to specific keys
      #
      # @param keys [Array<String>] Key names
      # @return [self]
      def in_keys(*keys)
        @options[:inkeys] = keys
        self
      end

      # Limit search to specific fields
      #
      # @param fields [Array<Symbol, String>] Field names
      # @return [self]
      def in_fields(*fields)
        @options[:infields] = fields.map(&:to_s)
        self
      end

      # Specify fields to return
      #
      # @param fields [Array<Symbol, String>] Field names
      # @return [self]
      def return_fields(*fields)
        @options[:return] = fields.map(&:to_s)
        self
      end

      # Sort results
      #
      # @param field [Symbol, String] Field name
      # @param direction [Symbol] :asc or :desc
      # @return [self]
      def sort_by(field, direction = :asc)
        @options[:sortby] = field.to_s
        @options[:sortasc] = (direction == :asc)
        self
      end

      # Limit number of results
      #
      # @param count [Integer] Maximum results
      # @param offset [Integer] Offset (default 0)
      # @return [self]
      def limit(count, offset = 0)
        @options[:limit] = [offset, count]
        self
      end

      # Include scores in results
      #
      # @return [self]
      def with_scores
        @options[:withscores] = true
        self
      end

      # Include payloads in results
      #
      # @return [self]
      def with_payloads
        @options[:withpayloads] = true
        self
      end

      # Include sort keys in results
      #
      # @return [self]
      def with_sortkeys
        @options[:withsortkeys] = true
        self
      end

      # Return only document IDs (no content)
      #
      # @return [self]
      def nocontent
        @options[:nocontent] = true
        self
      end

      # Use verbatim search (no stemming)
      #
      # @return [self]
      def verbatim
        @options[:verbatim] = true
        self
      end

      # Disable stopwords
      #
      # @return [self]
      def nostopwords
        @options[:nostopwords] = true
        self
      end

      # Require terms in order
      #
      # @return [self]
      def in_order
        @options[:inorder] = true
        self
      end

      # Set language
      #
      # @param lang [String, Symbol] Language code
      # @return [self]
      def language(lang)
        @options[:language] = lang.to_s
        self
      end

      # Set slop (distance between terms)
      #
      # @param slop [Integer] Slop value
      # @return [self]
      def slop(slop)
        @options[:slop] = slop
        self
      end

      # Execute the query
      #
      # @return [Array] Search results
      def execute
        @client.ft_search(@index_name, @query, **@options)
      end

      # Alias for execute
      alias call execute
      alias run execute
    end
  end
end

