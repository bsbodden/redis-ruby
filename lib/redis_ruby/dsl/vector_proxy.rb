# frozen_string_literal: true

module RedisRuby
  module DSL
    # Chainable proxy for vector set operations
    #
    # Provides a fluent interface for working with vector sets, inspired by
    # Pinecone, Weaviate, and other vector database APIs.
    #
    # @example Add vectors with metadata
    #   redis.vectors("embeddings")
    #     .add("doc1", [0.1, 0.2, 0.3], category: "tech", price: 99.99)
    #     .add("doc2", [0.2, 0.3, 0.4], category: "books", price: 19.99)
    #
    # @example Search for similar vectors
    #   results = redis.vectors("embeddings")
    #     .search([0.1, 0.2, 0.3])
    #     .filter(".category == 'tech'")
    #     .limit(10)
    #     .with_scores
    #     .execute
    class VectorProxy
      attr_reader :client, :key

      def initialize(client, *key_parts)
        @client = client
        @key = key_parts.map(&:to_s).join(":")
      end

      # Add a vector with optional metadata
      #
      # @param id [String] Element ID
      # @param vector [Array<Float>] Vector data
      # @param metadata [Hash] Optional metadata attributes
      # @param quantization [Symbol, String] Quantization method
      # @param reduce_dim [Integer] Reduce dimensions
      # @return [self] For method chaining
      #
      # @example
      #   vectors.add("item1", [1.0, 2.0, 3.0], category: "electronics")
      def add(id, vector, **metadata)
        options = extract_vector_options(metadata)
        attributes = metadata.reject { |k, _v| options.key?(k) }

        @client.vadd(
          @key,
          vector,
          id.to_s,
          **options,
          attributes: attributes.empty? ? nil : attributes,
        )
        self
      end

      # Alias for add
      alias_method :upsert, :add

      # Add multiple vectors in batch
      #
      # @param vectors [Array<Hash>] Array of vector hashes with :id, :vector, and optional metadata
      # @return [self]
      #
      # @example
      #   vectors.add_many([
      #     { id: "doc1", vector: [0.1, 0.2], category: "tech" },
      #     { id: "doc2", vector: [0.3, 0.4], category: "books" }
      #   ])
      def add_many(vectors)
        vectors.each do |vec|
          id = vec.delete(:id) || vec.delete("id")
          vector_data = vec.delete(:vector) || vec.delete("vector")
          add(id, vector_data, **vec)
        end
        self
      end

      # Remove a vector by ID
      #
      # @param id [String] Element ID
      # @return [Integer] Number of elements removed
      def remove(id)
        @client.vrem(@key, id.to_s)
      end

      # Alias for remove
      alias_method :delete, :remove

      # Get vector by ID
      #
      # @param id [String] Element ID
      # @param raw [Boolean] Return raw quantization info
      # @return [Array<Float>, Hash, nil] Vector data or nil if not found
      def get(id, raw: false)
        @client.vemb(@key, id.to_s, raw: raw)
      end

      # Alias for get
      alias_method :fetch, :get

      # Get metadata for a vector
      #
      # @param id [String] Element ID
      # @return [Hash, nil] Metadata attributes or nil
      def metadata(id)
        @client.vgetattr(@key, id.to_s)
      end

      # Set metadata for a vector
      #
      # @param id [String] Element ID
      # @param attributes [Hash] Metadata attributes
      # @return [Integer] 1 if successful
      def set_metadata(id, **attributes)
        @client.vsetattr(@key, id.to_s, attributes)
      end

      # Get vector set dimension
      #
      # @return [Integer] Vector dimension
      def dimension
        @client.vdim(@key)
      end

      # Alias for dimension
      alias_method :dim, :dimension

      # Get number of vectors in set
      #
      # @return [Integer] Number of vectors
      def count
        @client.vcard(@key)
      end

      # Alias for count
      alias_method :size, :count
      alias_method :cardinality, :count

      # Get vector set info
      #
      # @return [Hash] Vector set information
      def info
        @client.vinfo(@key)
      end

      # Create a search query builder
      #
      # @param query_vector [Array<Float>, String] Query vector or element ID
      # @return [VectorSearchBuilder] Search builder for chaining
      #
      # @example
      #   results = vectors.search([0.1, 0.2, 0.3])
      #     .filter(".price < 50")
      #     .limit(10)
      #     .with_scores
      #     .execute
      def search(query_vector)
        VectorSearchBuilder.new(@client, @key, query_vector)
      end

      private

      # Extract vector-specific options from metadata hash
      def extract_vector_options(metadata)
        options = {}
        options[:quantization] = metadata.delete(:quantization) if metadata.key?(:quantization)
        options[:reduce_dim] = metadata.delete(:reduce_dim) if metadata.key?(:reduce_dim)
        options[:ef] = metadata.delete(:ef) if metadata.key?(:ef)
        options[:numlinks] = metadata.delete(:numlinks) if metadata.key?(:numlinks)
        options[:cas] = metadata.delete(:cas) if metadata.key?(:cas)
        options
      end
    end
  end
end

