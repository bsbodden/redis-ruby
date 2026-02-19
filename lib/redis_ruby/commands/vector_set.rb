# frozen_string_literal: true

require "json"
require_relative "../dsl/vector_set_builder"
require_relative "../dsl/vector_proxy"
require_relative "../dsl/vector_search_builder"

module RR
  module Commands
    # Redis Vector Set commands module (Redis 8.0+)
    #
    # Provides vector similarity search capabilities:
    # - Store vectors with elements
    # - Similarity search using various algorithms
    # - Vector quantization options
    # - Attribute storage and filtering
    #
    # @see https://redis.io/docs/data-types/vector-sets/
    module VectorSet
      # Frozen command constants to avoid string allocations
      CMD_VADD = "VADD"
      CMD_VSIM = "VSIM"
      CMD_VDIM = "VDIM"
      CMD_VCARD = "VCARD"
      CMD_VREM = "VREM"
      CMD_VEMB = "VEMB"
      CMD_VLINKS = "VLINKS"
      CMD_VINFO = "VINFO"
      CMD_VSETATTR = "VSETATTR"
      CMD_VGETATTR = "VGETATTR"
      CMD_VRANDMEMBER = "VRANDMEMBER"

      # Frozen options
      OPT_REDUCE = "REDUCE"
      OPT_FP32 = "FP32"
      OPT_VALUES = "VALUES"
      OPT_ELE = "ELE"
      OPT_CAS = "CAS"
      OPT_EF = "EF"
      OPT_SETATTR = "SETATTR"
      OPT_M = "M"
      OPT_WITHSCORES = "WITHSCORES"
      OPT_WITHATTRIBS = "WITHATTRIBS"
      OPT_COUNT = "COUNT"
      OPT_EPSILON = "EPSILON"
      OPT_FILTER = "FILTER"
      OPT_FILTER_EF = "FILTER-EF"
      OPT_TRUTH = "TRUTH"
      OPT_NOTHREAD = "NOTHREAD"
      OPT_RAW = "RAW"
      # Add a vector to a vector set
      #
      # @param key [String] Vector set key
      # @param vector [Array<Float>, String] Vector as array of floats or FP32 blob
      # @param element [String] Element name
      # @param reduce_dim [Integer] Reduce dimensions (optional)
      # @param cas [Boolean] Use check-and-set
      # @param quantization [String] Quantization type (NOQUANT, BIN, Q8)
      # @param ef [Integer, Float] Exploration factor
      # @param attributes [Hash] JSON attributes for the element
      # @param numlinks [Integer] Number of links (M parameter)
      # @return [Integer] 1 if added, 0 if updated
      #
      # @example Add vector with VALUES format
      #   redis.vadd("vectors", [1.0, 2.0, 3.0], "item1")
      #
      # @example Add vector with attributes
      #   redis.vadd("vectors", [1.0, 2.0, 3.0], "item1",
      #     attributes: { category: "electronics", price: 99.99 })
      def vadd(key, vector, element, reduce_dim: nil, cas: false, quantization: nil,
               ef: nil, attributes: nil, numlinks: nil)
        args = [key]
        args.push(OPT_REDUCE, reduce_dim) if reduce_dim
        append_vector_format(args, vector)
        args << element
        append_vadd_options(args, cas: cas, quantization: quantization,
                                  ef: ef, attributes: attributes, numlinks: numlinks)
        call(CMD_VADD, *args)
      end

      # Find similar vectors in a vector set
      #
      # @param key [String] Vector set key
      # @param input [Array<Float>, String] Query vector, FP32 blob, or element name
      # @param with_scores [Boolean] Return similarity scores
      # @param with_attribs [Boolean] Return attributes
      # @param count [Integer] Number of results to return
      # @param ef [Integer, Float] Exploration factor
      # @param filter [String] Filter expression
      # @param filter_ef [String] Max filtering effort
      # @param truth [Boolean] Force linear scan
      # @param no_thread [Boolean] Execute in main thread
      # @param epsilon [Float] Distance threshold (0-1)
      # @return [Array, Hash] Elements or hash with scores/attributes
      #
      # @example Basic similarity search
      #   redis.vsim("vectors", [1.0, 2.0, 3.0], count: 10)
      #
      # @example Search with scores and filter
      #   redis.vsim("vectors", [1.0, 2.0, 3.0],
      #     with_scores: true,
      #     count: 10,
      #     filter: ".category == 'electronics'")
      def vsim(key, input, with_scores: false, with_attribs: false, count: nil,
               ef: nil, filter: nil, filter_ef: nil, truth: false, no_thread: false,
               epsilon: nil)
        args = [key]
        append_vsim_input(args, input)
        append_vsim_options(args, with_scores: with_scores, with_attribs: with_attribs,
                                  count: count, epsilon: epsilon, ef: ef,
                                  filter: filter, filter_ef: filter_ef,
                                  truth: truth, no_thread: no_thread)
        result = call(CMD_VSIM, *args)
        parse_vsim_response(result, with_scores, with_attribs)
      end

      # Get the dimension of a vector set
      #
      # @param key [String] Vector set key
      # @return [Integer] Vector dimension
      def vdim(key)
        call_1arg(CMD_VDIM, key)
      end

      # Get the cardinality (number of elements) of a vector set
      #
      # @param key [String] Vector set key
      # @return [Integer] Number of elements
      def vcard(key)
        call_1arg(CMD_VCARD, key)
      end

      # Remove an element from a vector set
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @return [Integer] 1 if removed, 0 if not found
      def vrem(key, element)
        call_2args(CMD_VREM, key, element)
      end

      # Get the approximated vector of an element
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @param raw [Boolean] Return internal representation
      # @return [Array<Float>, Hash, nil] Vector or nil if not found
      def vemb(key, element, raw: false)
        result = if raw
                   call(CMD_VEMB, key, element, OPT_RAW)
                 else
                   call_2args(CMD_VEMB, key, element)
                 end

        return nil unless result

        parse_vemb_result(result, raw)
      end

      # Get the neighbors for each level an element exists in
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @param with_scores [Boolean] Return scores
      # @return [Array<Array>, Array<Hash>, nil] Neighbors per level
      def vlinks(key, element, with_scores: false)
        result = if with_scores
                   call(CMD_VLINKS, key, element, OPT_WITHSCORES)
                 else
                   call_2args(CMD_VLINKS, key, element)
                 end

        return nil unless result

        parse_vlinks_result(result, with_scores)
      end

      # Get information about a vector set
      #
      # @param key [String] Vector set key
      # @return [Hash] Vector set information
      def vinfo(key)
        result = call_1arg(CMD_VINFO, key)
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # Set or remove JSON attributes of an element
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @param attributes [Hash, String] Attributes (empty hash to remove)
      # @return [Integer] 1 on success
      def vsetattr(key, element, attributes)
        attrs_json = if attributes.is_a?(Hash)
                       attributes.empty? ? "{}" : ::JSON.generate(attributes)
                     else
                       attributes
                     end

        call_3args(CMD_VSETATTR, key, element, attrs_json)
      end

      # Get the JSON attributes of an element
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @return [Hash, nil] Attributes or nil if not found
      def vgetattr(key, element)
        result = call_2args(CMD_VGETATTR, key, element)
        return nil unless result

        attrs = ::JSON.parse(result)
        attrs.empty? ? nil : attrs
      rescue ::JSON::ParserError
        nil
      end

      # Get random elements from a vector set
      #
      # @param key [String] Vector set key
      # @param count [Integer] Number of elements (optional)
      # @return [String, Array<String>, nil] Random element(s)
      def vrandmember(key, count = nil)
        # Fast path: no count
        return call_1arg(CMD_VRANDMEMBER, key) unless count

        call(CMD_VRANDMEMBER, key, count)
      end

      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create or configure a vector set with a fluent DSL
      #
      # @param key [String, Symbol] Vector set key
      # @yield [builder] Configuration block
      # @yieldparam builder [DSL::VectorSetBuilder] Builder instance
      # @return [DSL::VectorSetBuilder] Builder instance
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
      def vector_set(key, &)
        builder = DSL::VectorSetBuilder.new(key.to_s)
        builder.instance_eval(&) if block_given?
        builder
      end

      # Get a chainable proxy for vector operations
      #
      # @param key_parts [Array<String, Symbol>] Key parts to join with ':'
      # @return [DSL::VectorProxy] Chainable proxy for vector operations
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
      def vectors(*key_parts)
        DSL::VectorProxy.new(self, *key_parts)
      end

      private

      # Append vector data in FP32 or VALUES format
      def append_vector_format(args, vector)
        if vector.is_a?(String) && vector.encoding == Encoding::BINARY
          args.push(OPT_FP32, vector)
        elsif vector.is_a?(Array)
          args.push(OPT_VALUES, vector.length, *vector)
        else
          raise ArgumentError, "Vector must be a binary String (FP32) or an Array of floats"
        end
      end

      # Append optional arguments for VADD command
      def append_vadd_options(args, cas:, quantization:, ef:, attributes:, numlinks:)
        args << OPT_CAS if cas
        args << quantization.to_s.upcase if quantization
        args.push(OPT_EF, ef) if ef
        append_setattr(args, attributes) if attributes
        args.push(OPT_M, numlinks) if numlinks
      end

      # Append SETATTR JSON for an attributes hash or string
      def append_setattr(args, attributes)
        attrs_json = attributes.is_a?(Hash) ? ::JSON.generate(attributes) : attributes
        args.push(OPT_SETATTR, attrs_json)
      end

      # Append input vector/element for VSIM command
      def append_vsim_input(args, input)
        if input.is_a?(String) && input.encoding == Encoding::BINARY
          args.push(OPT_FP32, input)
        elsif input.is_a?(Array)
          args.push(OPT_VALUES, input.length, *input)
        elsif input.is_a?(String)
          args.push(OPT_ELE, input)
        else
          raise ArgumentError, "Input must be Array, FP32 binary String, or element name String"
        end
      end

      # Append optional arguments for VSIM command
      def append_vsim_options(args, with_scores:, with_attribs:, count:, epsilon:,
                              ef:, filter:, filter_ef:, truth:, no_thread:)
        args << OPT_WITHSCORES if with_scores
        args << OPT_WITHATTRIBS if with_attribs
        args.push(OPT_COUNT, count) if count
        args.push(OPT_EPSILON, epsilon) if epsilon
        args.push(OPT_EF, ef) if ef
        append_vsim_filter_options(args, filter: filter, filter_ef: filter_ef,
                                         truth: truth, no_thread: no_thread)
      end

      # Append filter and execution options for VSIM command
      def append_vsim_filter_options(args, filter:, filter_ef:, truth:, no_thread:)
        args.push(OPT_FILTER, filter) if filter
        args.push(OPT_FILTER_EF, filter_ef) if filter_ef
        args << OPT_TRUTH if truth
        args << OPT_NOTHREAD if no_thread
      end

      # Parse VEMB result based on raw flag
      def parse_vemb_result(result, raw)
        if raw && result.is_a?(Array) && result.length >= 3
          build_raw_vemb_hash(result)
        elsif result.is_a?(Array)
          result.map(&:to_f)
        else
          result
        end
      end

      # Build hash from raw VEMB response
      def build_raw_vemb_hash(result)
        {
          "quantization" => result[0],
          "raw" => result[1],
          "l2" => result[2].to_f,
          "range" => result.length > 3 ? result[3].to_f : nil,
        }.compact
      end

      # Parse VLINKS result based on with_scores flag
      def parse_vlinks_result(result, with_scores)
        return result unless with_scores && result.is_a?(Array)

        result.map { |level| parse_vlinks_level(level) }
      end

      def parse_vlinks_level(level)
        return level.transform_values(&:to_f) if level.is_a?(Hash)
        return Hash[*level].transform_values(&:to_f) if level.is_a?(Array)

        level
      end

      # Parse VSIM response based on options
      def parse_vsim_response(result, with_scores, with_attribs)
        return result.transform_values(&:to_f) if with_scores && result.is_a?(Hash)
        return result unless result.is_a?(Array)

        parse_vsim_array(result, with_scores, with_attribs)
      end

      def parse_vsim_array(result, with_scores, with_attribs)
        return parse_vsim_scores_and_attribs(result) if with_scores && with_attribs
        return Hash[*result].transform_values(&:to_f) if with_scores
        return parse_vsim_attribs_only(result) if with_attribs

        result
      end

      # Parse VSIM response with both scores and attributes
      def parse_vsim_scores_and_attribs(result)
        output = {}
        result.each_slice(3) do |element, score, attribs|
          output[element] = { "score" => score.to_f, "attributes" => parse_json_attrs(attribs) }
        end
        output
      end

      # Parse VSIM response with attributes only
      def parse_vsim_attribs_only(result)
        output = {}
        result.each_slice(2) do |element, attribs|
          output[element] = parse_json_attrs(attribs)
        end
        output
      end

      def parse_json_attrs(attribs)
        return nil unless attribs

        attrs = ::JSON.parse(attribs)
        attrs.empty? ? nil : attrs
      rescue ::JSON::ParserError
        nil
      end
    end
  end
end
