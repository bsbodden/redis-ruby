# frozen_string_literal: true

module RedisRuby
  module DSL
    # Builder for creating and configuring vector sets with a fluent API
    #
    # @example Create a vector set with configuration
    #   redis.vector_set("embeddings") do
    #     dimension 384
    #     quantization :binary
    #     metadata_schema do
    #       field :category, type: :string
    #       field :price, type: :number
    #     end
    #   end
    class VectorSetBuilder
      attr_reader :key, :config

      def initialize(key)
        @key = key
        @config = {
          dimension: nil,
          quantization: nil,
          metadata_fields: {},
        }
      end

      # Set the vector dimension
      #
      # @param dim [Integer] Vector dimension
      # @return [self]
      def dimension(dim)
        @config[:dimension] = dim
        self
      end

      # Set quantization method
      #
      # @param method [Symbol, String] Quantization method (:binary, :q8, :noquant)
      # @return [self]
      def quantization(method)
        @config[:quantization] = method
        self
      end

      # Define metadata schema (for documentation purposes)
      #
      # @yield Block for defining metadata fields
      # @return [self]
      def metadata_schema(&block)
        schema = MetadataSchema.new
        schema.instance_eval(&block) if block_given?
        @config[:metadata_fields] = schema.fields
        self
      end

      # Metadata schema builder
      class MetadataSchema
        attr_reader :fields

        def initialize
          @fields = {}
        end

        # Define a metadata field
        #
        # @param name [Symbol] Field name
        # @param type [Symbol] Field type (:string, :number, :boolean)
        # @return [void]
        def field(name, type: :string)
          @fields[name] = type
        end
      end
    end
  end
end

