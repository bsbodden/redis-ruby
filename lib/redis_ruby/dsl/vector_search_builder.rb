# frozen_string_literal: true

module RR
  module DSL
    # Fluent builder for vector similarity search queries
    #
    # Provides a chainable interface for building complex vector search queries
    # with filtering, scoring, and result customization.
    #
    # @example Basic search
    #   results = builder.search([0.1, 0.2, 0.3]).limit(10).execute
    #
    # @example Search with filtering and scores
    #   results = builder.search([0.1, 0.2, 0.3])
    #     .filter(".category == 'electronics'")
    #     .limit(10)
    #     .with_scores
    #     .with_metadata
    #     .execute
    class VectorSearchBuilder
      attr_reader :client, :key, :query_vector

      def initialize(client, key, query_vector)
        @client = client
        @key = key
        @query_vector = query_vector
        @options = {}
      end

      # Set maximum number of results
      #
      # @param n [Integer] Number of results
      # @return [self]
      def limit(n)
        @options[:count] = n
        self
      end

      # Alias for limit
      alias_method :top_k, :limit

      # Include similarity scores in results
      #
      # @return [self]
      def with_scores
        @options[:with_scores] = true
        self
      end

      # Include metadata attributes in results
      #
      # @return [self]
      def with_metadata
        @options[:with_attribs] = true
        self
      end

      # Alias for with_metadata
      alias_method :with_attributes, :with_metadata

      # Add a filter expression
      #
      # @param expression [String] Filter expression (e.g., ".price < 50")
      # @return [self]
      def filter(expression)
        @options[:filter] = expression
        self
      end

      # Alias for filter
      alias_method :where, :filter

      # Set exploration factor (ef parameter)
      #
      # @param value [Integer, Float] Exploration factor
      # @return [self]
      def exploration_factor(value)
        @options[:ef] = value
        self
      end

      # Alias for exploration_factor
      alias_method :ef, :exploration_factor

      # Set distance threshold (epsilon)
      #
      # @param value [Float] Distance threshold (0-1)
      # @return [self]
      def threshold(value)
        @options[:epsilon] = value
        self
      end

      # Alias for threshold
      alias_method :epsilon, :threshold

      # Set filter exploration factor
      #
      # @param value [String] Max filtering effort
      # @return [self]
      def filter_ef(value)
        @options[:filter_ef] = value
        self
      end

      # Force linear scan (truth parameter)
      #
      # @return [self]
      def linear_scan
        @options[:truth] = true
        self
      end

      # Execute in main thread (no_thread parameter)
      #
      # @return [self]
      def single_threaded
        @options[:no_thread] = true
        self
      end

      # Execute the search query
      #
      # @return [Array, Hash] Search results
      def execute
        @client.vsim(@key, @query_vector, **@options)
      end

      # Alias for execute
      alias_method :run, :execute
      alias_method :results, :execute
    end
  end
end

