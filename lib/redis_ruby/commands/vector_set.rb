# frozen_string_literal: true

require "json"

module RedisRuby
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

        # Add REDUCE option
        args.push("REDUCE", reduce_dim) if reduce_dim

        # Add vector in FP32 or VALUES format
        if vector.is_a?(String) && vector.encoding == Encoding::BINARY
          args.push("FP32", vector)
        elsif vector.is_a?(Array)
          args.push("VALUES", vector.length, *vector)
        else
          raise ArgumentError, "Vector must be a binary String (FP32) or an Array of floats"
        end

        # Element name
        args << element

        # CAS option
        args << "CAS" if cas

        # Quantization
        args << quantization.to_s.upcase if quantization

        # EF option
        args.push("EF", ef) if ef

        # Attributes
        if attributes
          attrs_json = attributes.is_a?(Hash) ? ::JSON.generate(attributes) : attributes
          args.push("SETATTR", attrs_json)
        end

        # M parameter (numlinks)
        args.push("M", numlinks) if numlinks

        call("VADD", *args)
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

        # Add input in FP32, VALUES, or ELE format
        if input.is_a?(String) && input.encoding == Encoding::BINARY
          args.push("FP32", input)
        elsif input.is_a?(Array)
          args.push("VALUES", input.length, *input)
        elsif input.is_a?(String)
          args.push("ELE", input)
        else
          raise ArgumentError, "Input must be Array, FP32 binary String, or element name String"
        end

        args << "WITHSCORES" if with_scores
        args << "WITHATTRIBS" if with_attribs
        args.push("COUNT", count) if count
        args.push("EPSILON", epsilon) if epsilon
        args.push("EF", ef) if ef
        args.push("FILTER", filter) if filter
        args.push("FILTER-EF", filter_ef) if filter_ef
        args << "TRUTH" if truth
        args << "NOTHREAD" if no_thread

        result = call("VSIM", *args)

        # Parse response based on options
        parse_vsim_response(result, with_scores, with_attribs)
      end

      # Get the dimension of a vector set
      #
      # @param key [String] Vector set key
      # @return [Integer] Vector dimension
      def vdim(key)
        call("VDIM", key)
      end

      # Get the cardinality (number of elements) of a vector set
      #
      # @param key [String] Vector set key
      # @return [Integer] Number of elements
      def vcard(key)
        call("VCARD", key)
      end

      # Remove an element from a vector set
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @return [Integer] 1 if removed, 0 if not found
      def vrem(key, element)
        call("VREM", key, element)
      end

      # Get the approximated vector of an element
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @param raw [Boolean] Return internal representation
      # @return [Array<Float>, Hash, nil] Vector or nil if not found
      def vemb(key, element, raw: false)
        args = [key, element]
        args << "RAW" if raw

        result = call("VEMB", *args)

        return nil unless result

        if raw && result.is_a?(Array) && result.length >= 3
          {
            "quantization" => result[0],
            "raw" => result[1],
            "l2" => result[2].to_f,
            "range" => result.length > 3 ? result[3].to_f : nil
          }.compact
        elsif result.is_a?(Array)
          result.map(&:to_f)
        else
          result
        end
      end

      # Get the neighbors for each level an element exists in
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @param with_scores [Boolean] Return scores
      # @return [Array<Array>, Array<Hash>, nil] Neighbors per level
      def vlinks(key, element, with_scores: false)
        args = [key, element]
        args << "WITHSCORES" if with_scores

        result = call("VLINKS", *args)

        return nil unless result

        if with_scores && result.is_a?(Array)
          result.map do |level|
            if level.is_a?(Array)
              Hash[*level].transform_values(&:to_f)
            else
              level
            end
          end
        else
          result
        end
      end

      # Get information about a vector set
      #
      # @param key [String] Vector set key
      # @return [Hash] Vector set information
      def vinfo(key)
        result = call("VINFO", key)
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

        call("VSETATTR", key, element, attrs_json)
      end

      # Get the JSON attributes of an element
      #
      # @param key [String] Vector set key
      # @param element [String] Element name
      # @return [Hash, nil] Attributes or nil if not found
      def vgetattr(key, element)
        result = call("VGETATTR", key, element)
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
        args = [key]
        args << count if count
        call("VRANDMEMBER", *args)
      end

      private

      # Parse VSIM response based on options
      def parse_vsim_response(result, with_scores, with_attribs)
        return result unless result.is_a?(Array)

        if with_scores && with_attribs
          # [element, score, attribs, element, score, attribs, ...]
          output = {}
          result.each_slice(3) do |element, score, attribs|
            parsed_attribs = parse_json_attrs(attribs)
            output[element] = {
              "score" => score.to_f,
              "attributes" => parsed_attribs
            }
          end
          output
        elsif with_scores
          # [element, score, element, score, ...]
          Hash[*result].transform_values(&:to_f)
        elsif with_attribs
          # [element, attribs, element, attribs, ...]
          output = {}
          result.each_slice(2) do |element, attribs|
            output[element] = parse_json_attrs(attribs)
          end
          output
        else
          result
        end
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
