# frozen_string_literal: true

require_relative "search_field"

module RR
  module DSL
    # DSL for building search index schemas
    #
    # @example
    #   schema = SchemaBuilder.new
    #   schema.instance_eval do
    #     text :name, sortable: true, weight: 5.0
    #     numeric :price, sortable: true
    #     tag :category
    #   end
    class SchemaBuilder
      attr_reader :fields

      def initialize
        @fields = []
      end

      # Define a TEXT field
      #
      # @param name [Symbol, String] Field name (or JSON path for JSON indexes)
      # @param options [Hash] Field options
      # @option options [Boolean] :sortable Make field sortable
      # @option options [Boolean] :noindex Don't index this field
      # @option options [Boolean] :nostem Don't stem this field
      # @option options [Float] :weight Field weight for scoring (default 1.0)
      # @option options [String] :phonetic Phonetic algorithm (dm:en, dm:fr, dm:pt, dm:es)
      # @option options [Boolean] :withsuffixtrie Enable suffix trie
      # @option options [String, Symbol] :as Alias name (for JSON path fields, this becomes the searchable field name)
      def text(name, **options)
        # For JSON indexes, if :as is provided, name is the JSON path and :as is the alias
        # For HASH indexes, name is the field name and :as is not typically used
        @fields << SearchField.new(name, :text, **options)
      end

      # Define a NUMERIC field
      #
      # @param name [Symbol, String] Field name (or JSON path for JSON indexes)
      # @param options [Hash] Field options
      # @option options [Boolean] :sortable Make field sortable
      # @option options [Boolean] :noindex Don't index this field
      # @option options [String, Symbol] :as Alias name (for JSON path fields)
      def numeric(name, **options)
        @fields << SearchField.new(name, :numeric, **options)
      end

      # Define a TAG field
      #
      # @param name [Symbol, String] Field name (or JSON path for JSON indexes)
      # @param options [Hash] Field options
      # @option options [Boolean] :sortable Make field sortable
      # @option options [Boolean] :noindex Don't index this field
      # @option options [String] :separator Tag separator (default ",")
      # @option options [Boolean] :casesensitive Case-sensitive tags
      # @option options [String, Symbol] :as Alias name (for JSON path fields)
      def tag(name, **options)
        @fields << SearchField.new(name, :tag, **options)
      end

      # Define a GEO field
      #
      # @param name [Symbol, String] Field name (or JSON path for JSON indexes)
      # @param options [Hash] Field options
      # @option options [Boolean] :sortable Make field sortable
      # @option options [Boolean] :noindex Don't index this field
      # @option options [String, Symbol] :as Alias name (for JSON path fields)
      def geo(name, **options)
        @fields << SearchField.new(name, :geo, **options)
      end

      # Define a VECTOR field
      #
      # @param name [Symbol, String] Field name
      # @param options [Hash] Field options
      # @option options [Symbol] :algorithm Algorithm (:flat or :hnsw)
      # @option options [Symbol] :vector_type Vector type (:float32, :float64)
      # @option options [Integer] :dim Vector dimensions
      # @option options [Symbol] :distance_metric Distance metric (:l2, :ip, :cosine)
      # @option options [Integer] :initial_cap Initial capacity (FLAT only)
      # @option options [Integer] :m Number of connections (HNSW only)
      # @option options [Integer] :ef_construction EF construction (HNSW only)
      # @option options [Integer] :ef_runtime EF runtime (HNSW only)
      # @option options [String] :as Alias for JSON path fields
      def vector(name, **options)
        @fields << SearchField.new(name, :vector, **options)
      end

      # Define a GEOSHAPE field
      #
      # @param name [Symbol, String] Field name
      # @param options [Hash] Field options
      # @option options [Boolean] :sortable Make field sortable
      # @option options [Boolean] :noindex Don't index this field
      # @option options [String] :as Alias for JSON path fields
      def geoshape(name, **options)
        @fields << SearchField.new(name, :geoshape, **options)
      end
    end
  end
end

