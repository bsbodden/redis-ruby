# frozen_string_literal: true

require_relative "schema_builder"

module RR
  module DSL
    # DSL builder for creating search indexes
    #
    # @example
    #   builder = SearchIndexBuilder.new(:products, client)
    #   builder.instance_eval do
    #     on :hash
    #     prefix "product:"
    #     schema do
    #       text :name, sortable: true
    #       numeric :price, sortable: true
    #     end
    #   end
    #   builder.create
    class SearchIndexBuilder
      attr_reader :index_name

      def initialize(index_name, client)
        @index_name = index_name.to_s
        @client = client
        @on = :hash
        @prefixes = []
        @filter = nil
        @language = nil
        @language_field = nil
        @score = nil
        @score_field = nil
        @payload_field = nil
        @maxtextfields = nil
        @temporary = nil
        @nooffsets = false
        @nohl = false
        @nofields = false
        @nofreqs = false
        @stopwords = nil
        @skipinitialscan = false
        @schema_builder = nil
      end

      # Set the data type to index
      #
      # @param type [Symbol] :hash or :json
      def on(type)
        @on = type
      end

      # Add prefix(es) for keys to index
      #
      # @param prefixes [Array<String>] Key prefixes
      def prefix(*prefixes)
        @prefixes.concat(prefixes.map(&:to_s))
      end

      # Set filter expression
      #
      # @param expression [String] Filter expression
      def filter(expression)
        @filter = expression
      end

      # Set default language
      #
      # @param lang [String, Symbol] Language code
      def language(lang)
        @language = lang.to_s
      end

      # Set language field name
      #
      # @param field [String, Symbol] Field name
      def language_field(field)
        @language_field = field.to_s
      end

      # Set default score
      #
      # @param score [Float] Default score
      def score(score)
        @score = score
      end

      # Set score field name
      #
      # @param field [String, Symbol] Field name
      def score_field(field)
        @score_field = field.to_s
      end

      # Set payload field name
      #
      # @param field [String, Symbol] Field name
      def payload_field(field)
        @payload_field = field.to_s
      end

      # Set max text fields
      #
      # @param max [Integer] Maximum number of text fields
      def maxtextfields(max)
        @maxtextfields = max
      end

      # Set temporary index with TTL
      #
      # @param seconds [Integer] TTL in seconds
      def temporary(seconds)
        @temporary = seconds
      end

      # Disable offset vectors
      def nooffsets
        @nooffsets = true
      end

      # Disable highlighting
      def nohl
        @nohl = true
      end

      # Disable field names in results
      def nofields
        @nofields = true
      end

      # Disable frequency tracking
      def nofreqs
        @nofreqs = true
      end

      # Set custom stopwords
      #
      # @param words [Array<String>] Stopwords list
      def stopwords(*words)
        @stopwords = words
      end

      # Skip initial scan
      def skipinitialscan
        @skipinitialscan = true
      end

      # Define schema using DSL
      #
      # @yield Block for schema definition
      def schema(&block)
        @schema_builder = SchemaBuilder.new
        @schema_builder.instance_eval(&block)
      end

      # Create the index
      #
      # @return [String] "OK"
      def create
        raise ArgumentError, "Schema not defined" unless @schema_builder

        args = build_args
        @client.ft_create(@index_name, *args)
      end

      private

      def build_args
        args = []

        # ON clause
        args.push("ON", @on.to_s.upcase)

        # PREFIX clause
        if @prefixes.any?
          args.push("PREFIX", @prefixes.size, *@prefixes)
        end

        # Optional clauses
        args.push("FILTER", @filter) if @filter
        args.push("LANGUAGE", @language) if @language
        args.push("LANGUAGE_FIELD", @language_field) if @language_field
        args.push("SCORE", @score) if @score
        args.push("SCORE_FIELD", @score_field) if @score_field
        args.push("PAYLOAD_FIELD", @payload_field) if @payload_field
        args.push("MAXTEXTFIELDS", @maxtextfields) if @maxtextfields
        args.push("TEMPORARY", @temporary) if @temporary
        args << "NOOFFSETS" if @nooffsets
        args << "NOHL" if @nohl
        args << "NOFIELDS" if @nofields
        args << "NOFREQS" if @nofreqs

        if @stopwords
          args.push("STOPWORDS", @stopwords.size, *@stopwords)
        end

        args << "SKIPINITIALSCAN" if @skipinitialscan

        # SCHEMA clause
        args << "SCHEMA"
        @schema_builder.fields.each do |field|
          args.concat(field.to_args)
        end

        args
      end
    end
  end
end

