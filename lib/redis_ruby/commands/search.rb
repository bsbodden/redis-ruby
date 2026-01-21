# frozen_string_literal: true

module RedisRuby
  module Commands
    # RediSearch commands module
    #
    # Provides full-text search capabilities including:
    # - Index creation and management
    # - Full-text search with scoring
    # - Aggregations and grouping
    # - Autocomplete suggestions
    # - Spell checking
    # - Synonyms and dictionaries
    #
    # @example Basic search
    #   redis.ft_create("idx", "SCHEMA", "title", "TEXT", "body", "TEXT")
    #   redis.hset("doc:1", "title", "Hello", "body", "World")
    #   redis.ft_search("idx", "Hello")
    #
    # @see https://redis.io/docs/interact/search-and-query/
    module Search
      # Create a new search index
      #
      # @param index_name [String] Name of the index
      # @param args [Array] Schema definition and options
      # @option options [String] :on Storage type ("HASH" or "JSON")
      # @option options [Array<String>] :prefix Key prefixes to index
      # @option options [Array<String>] :stopwords Custom stopwords (empty array disables)
      # @option options [Boolean] :maxtextfields Optimize for many text fields
      # @option options [Integer] :temporary Index auto-expiration in seconds
      # @option options [Boolean] :nooffsets Don't store term offsets
      # @option options [Boolean] :nohl Disable highlighting
      # @option options [Boolean] :nofields Don't store field bits
      # @option options [Boolean] :nofreqs Don't store term frequencies
      # @option options [Boolean] :skipinitialscan Don't scan existing keys
      # @return [String] "OK"
      #
      # @example Create index on hash documents
      #   redis.ft_create("products", "ON", "HASH",
      #     "PREFIX", 1, "product:",
      #     "SCHEMA",
      #       "name", "TEXT", "SORTABLE",
      #       "price", "NUMERIC", "SORTABLE",
      #       "category", "TAG")
      #
      # @example Create index on JSON documents
      #   redis.ft_create("users", "ON", "JSON",
      #     "PREFIX", 1, "user:",
      #     "SCHEMA",
      #       "$.name", "AS", "name", "TEXT",
      #       "$.age", "AS", "age", "NUMERIC")
      def ft_create(index_name, *args)
        call("FT.CREATE", index_name, *args)
      end

      # Search the index
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param options [Hash] Search options
      # @option options [Boolean] :nocontent Return only document IDs
      # @option options [Boolean] :verbatim Don't expand query terms
      # @option options [Boolean] :nostopwords Don't filter stopwords
      # @option options [Boolean] :withscores Return document scores
      # @option options [Boolean] :withpayloads Return document payloads
      # @option options [Integer] :slop Maximum distance between query terms
      # @option options [Boolean] :inorder Terms must appear in order
      # @option options [String] :language Document language
      # @option options [String] :scorer Custom scoring function
      # @option options [Boolean] :explainscore Include score explanation
      # @option options [Integer] :offset Result offset
      # @option options [Integer] :limit Maximum results (default 10)
      # @option options [Array<String>] :return Fields to return
      # @option options [String] :sortby Field to sort by
      # @option options [Boolean] :sortasc Sort ascending (default)
      # @option options [Hash] :filter Numeric filter {field: [min, max]}
      # @option options [Hash] :geofilter Geo filter {field: [lon, lat, radius, unit]}
      # @option options [Hash] :params Query parameters
      # @option options [Integer] :dialect Search dialect version
      # @return [Array] [total, doc_id1, fields1, doc_id2, fields2, ...]
      #
      # @example Basic search
      #   redis.ft_search("idx", "hello world")
      #
      # @example Search with options
      #   redis.ft_search("idx", "hello",
      #     withscores: true,
      #     limit: [0, 20],
      #     sortby: "timestamp",
      #     sortasc: false)
      def ft_search(index_name, query, **options)
        args = [index_name, query]

        args << "NOCONTENT" if options[:nocontent]
        args << "VERBATIM" if options[:verbatim]
        args << "NOSTOPWORDS" if options[:nostopwords]
        args << "WITHSCORES" if options[:withscores]
        args << "WITHPAYLOADS" if options[:withpayloads]
        args.push("WITHSORTKEYS") if options[:withsortkeys]

        args.push("SCORER", options[:scorer]) if options[:scorer]
        args << "EXPLAINSCORE" if options[:explainscore]

        args.push("LANGUAGE", options[:language]) if options[:language]

        args.push("SLOP", options[:slop]) if options[:slop]
        args << "INORDER" if options[:inorder]

        # Numeric filter
        if options[:filter]
          options[:filter].each do |field, (min, max)|
            args.push("FILTER", field.to_s, min, max)
          end
        end

        # Geo filter
        if options[:geofilter]
          options[:geofilter].each do |field, (lon, lat, radius, unit)|
            args.push("GEOFILTER", field.to_s, lon, lat, radius, unit || "km")
          end
        end

        # Limit to specific keys
        if options[:inkeys]
          args.push("INKEYS", options[:inkeys].size, *options[:inkeys])
        end

        # Limit to specific fields
        if options[:infields]
          args.push("INFIELDS", options[:infields].size, *options[:infields])
        end

        # Return specific fields
        if options[:return]
          fields = Array(options[:return])
          args.push("RETURN", fields.size, *fields)
        end

        # Summarize
        if options[:summarize]
          args << "SUMMARIZE"
          if options[:summarize].is_a?(Hash)
            if options[:summarize][:fields]
              fields = Array(options[:summarize][:fields])
              args.push("FIELDS", fields.size, *fields)
            end
            args.push("FRAGS", options[:summarize][:frags]) if options[:summarize][:frags]
            args.push("LEN", options[:summarize][:len]) if options[:summarize][:len]
            args.push("SEPARATOR", options[:summarize][:separator]) if options[:summarize][:separator]
          end
        end

        # Highlight
        if options[:highlight]
          args << "HIGHLIGHT"
          if options[:highlight].is_a?(Hash)
            if options[:highlight][:fields]
              fields = Array(options[:highlight][:fields])
              args.push("FIELDS", fields.size, *fields)
            end
            if options[:highlight][:tags]
              args.push("TAGS", options[:highlight][:tags][0], options[:highlight][:tags][1])
            end
          end
        end

        # Sort by field
        if options[:sortby]
          args.push("SORTBY", options[:sortby])
          args << (options[:sortasc] == false ? "DESC" : "ASC")
        end

        # Pagination
        if options[:limit]
          offset, count = options[:limit]
          args.push("LIMIT", offset, count)
        end

        # Parameters
        if options[:params]
          args.push("PARAMS", options[:params].size * 2)
          options[:params].each do |k, v|
            args.push(k.to_s, v.to_s)
          end
        end

        # Dialect
        args.push("DIALECT", options[:dialect]) if options[:dialect]

        # Timeout
        args.push("TIMEOUT", options[:timeout]) if options[:timeout]

        call("FT.SEARCH", *args)
      end

      # Run an aggregation query
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param args [Array] Aggregation pipeline steps
      # @return [Array] Aggregation results
      #
      # @example Group by category with count
      #   redis.ft_aggregate("products", "*",
      #     "GROUPBY", 1, "@category",
      #     "REDUCE", "COUNT", 0, "AS", "count")
      #
      # @example With cursor
      #   redis.ft_aggregate("idx", "*",
      #     "WITHCURSOR", "COUNT", 100,
      #     "GROUPBY", 1, "@category")
      def ft_aggregate(index_name, query, *args)
        call("FT.AGGREGATE", index_name, query, *args)
      end

      # Read next batch of cursor results
      #
      # @param index_name [String] Index name
      # @param cursor_id [Integer] Cursor ID
      # @param count [Integer] Number of results to fetch
      # @return [Array] [results, cursor_id]
      def ft_cursor_read(index_name, cursor_id, count: nil)
        args = [index_name, cursor_id]
        args.push("COUNT", count) if count
        call("FT.CURSOR", "READ", *args)
      end

      # Delete a cursor
      #
      # @param index_name [String] Index name
      # @param cursor_id [Integer] Cursor ID
      # @return [String] "OK"
      def ft_cursor_del(index_name, cursor_id)
        call("FT.CURSOR", "DEL", index_name, cursor_id)
      end

      # Get index information
      #
      # @param index_name [String] Index name
      # @return [Hash] Index metadata
      def ft_info(index_name)
        result = call("FT.INFO", index_name)
        # Convert array to hash (pairs of key, value)
        result.each_slice(2).to_h
      end

      # List all indexes
      #
      # @return [Array<String>] Index names
      def ft_list
        call("FT._LIST")
      end

      # Drop an index
      #
      # @param index_name [String] Index name
      # @param dd [Boolean] Delete indexed documents (default: false)
      # @return [String] "OK"
      def ft_dropindex(index_name, dd: false)
        args = [index_name]
        args << "DD" if dd
        call("FT.DROPINDEX", *args)
      end

      # Alter an index schema
      #
      # @param index_name [String] Index name
      # @param args [Array] Fields to add
      # @return [String] "OK"
      #
      # @example Add a new field
      #   redis.ft_alter("idx", "SCHEMA", "ADD", "new_field", "TEXT")
      def ft_alter(index_name, *args)
        call("FT.ALTER", index_name, *args)
      end

      # Add an alias to an index
      #
      # @param alias_name [String] Alias name
      # @param index_name [String] Index name
      # @return [String] "OK"
      def ft_aliasadd(alias_name, index_name)
        call("FT.ALIASADD", alias_name, index_name)
      end

      # Update an alias to point to a different index
      #
      # @param alias_name [String] Alias name
      # @param index_name [String] Index name
      # @return [String] "OK"
      def ft_aliasupdate(alias_name, index_name)
        call("FT.ALIASUPDATE", alias_name, index_name)
      end

      # Remove an alias
      #
      # @param alias_name [String] Alias name
      # @return [String] "OK"
      def ft_aliasdel(alias_name)
        call("FT.ALIASDEL", alias_name)
      end

      # Explain a search query
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param dialect [Integer] Dialect version
      # @return [String] Query execution plan
      def ft_explain(index_name, query, dialect: nil)
        args = [index_name, query]
        args.push("DIALECT", dialect) if dialect
        call("FT.EXPLAIN", *args)
      end

      # Explain query with CLI-friendly output
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param dialect [Integer] Dialect version
      # @return [Array] Query execution plan
      def ft_explaincli(index_name, query, dialect: nil)
        args = [index_name, query]
        args.push("DIALECT", dialect) if dialect
        call("FT.EXPLAINCLI", *args)
      end

      # Profile a search or aggregate command
      #
      # @param index_name [String] Index name
      # @param type [String] "SEARCH" or "AGGREGATE"
      # @param limited [Boolean] Return limited results
      # @param query [String] Query to profile
      # @param args [Array] Additional query arguments
      # @return [Array] Profile results
      def ft_profile(index_name, type, query, *args, limited: false)
        cmd = [index_name, type.to_s.upcase]
        cmd << "LIMITED" if limited
        cmd.push("QUERY", query, *args)
        call("FT.PROFILE", *cmd)
      end

      # Perform spell checking on a query
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param distance [Integer] Levenshtein distance (1-4)
      # @param include [String] Dictionary to include terms from
      # @param exclude [String] Dictionary to exclude terms from
      # @param dialect [Integer] Dialect version
      # @return [Array] Spelling suggestions
      def ft_spellcheck(index_name, query, distance: nil, include: nil, exclude: nil, dialect: nil)
        args = [index_name, query]
        args.push("DISTANCE", distance) if distance
        args.push("TERMS", "INCLUDE", include) if include
        args.push("TERMS", "EXCLUDE", exclude) if exclude
        args.push("DIALECT", dialect) if dialect
        call("FT.SPELLCHECK", *args)
      end

      # Get all distinct tag values
      #
      # @param index_name [String] Index name
      # @param field_name [String] Tag field name
      # @return [Array<String>] Distinct tag values
      def ft_tagvals(index_name, field_name)
        call("FT.TAGVALS", index_name, field_name)
      end

      # Update synonym group
      #
      # @param index_name [String] Index name
      # @param group_id [String] Synonym group ID
      # @param terms [Array<String>] Synonym terms
      # @param skipinitialscan [Boolean] Skip initial scan
      # @return [String] "OK"
      def ft_synupdate(index_name, group_id, *terms, skipinitialscan: false)
        args = [index_name, group_id]
        args << "SKIPINITIALSCAN" if skipinitialscan
        args.concat(terms)
        call("FT.SYNUPDATE", *args)
      end

      # Dump synonym groups
      #
      # @param index_name [String] Index name
      # @return [Hash] Synonym groups
      def ft_syndump(index_name)
        result = call("FT.SYNDUMP", index_name)
        Hash[*result]
      end

      # Add terms to a dictionary
      #
      # @param dict_name [String] Dictionary name
      # @param terms [Array<String>] Terms to add
      # @return [Integer] Number of terms added
      def ft_dictadd(dict_name, *terms)
        call("FT.DICTADD", dict_name, *terms)
      end

      # Delete terms from a dictionary
      #
      # @param dict_name [String] Dictionary name
      # @param terms [Array<String>] Terms to delete
      # @return [Integer] Number of terms deleted
      def ft_dictdel(dict_name, *terms)
        call("FT.DICTDEL", dict_name, *terms)
      end

      # Dump dictionary contents
      #
      # @param dict_name [String] Dictionary name
      # @return [Array<String>] Dictionary terms
      def ft_dictdump(dict_name)
        call("FT.DICTDUMP", dict_name)
      end

      # Add a suggestion to an autocomplete dictionary
      #
      # @param key [String] Suggestion dictionary key
      # @param string [String] Suggestion string
      # @param score [Float] Suggestion score
      # @param incr [Boolean] Increment existing score
      # @param payload [String] Optional payload
      # @return [Integer] Current dictionary size
      def ft_sugadd(key, string, score, incr: false, payload: nil)
        args = [key, string, score]
        args << "INCR" if incr
        args.push("PAYLOAD", payload) if payload
        call("FT.SUGADD", *args)
      end

      # Get autocomplete suggestions
      #
      # @param key [String] Suggestion dictionary key
      # @param prefix [String] Prefix to search
      # @param fuzzy [Boolean] Allow fuzzy matching
      # @param withscores [Boolean] Include scores
      # @param withpayloads [Boolean] Include payloads
      # @param max [Integer] Maximum suggestions
      # @return [Array] Suggestions
      def ft_sugget(key, prefix, fuzzy: false, withscores: false, withpayloads: false, max: nil)
        args = [key, prefix]
        args << "FUZZY" if fuzzy
        args << "WITHSCORES" if withscores
        args << "WITHPAYLOADS" if withpayloads
        args.push("MAX", max) if max
        call("FT.SUGGET", *args)
      end

      # Get suggestion dictionary size
      #
      # @param key [String] Suggestion dictionary key
      # @return [Integer] Number of suggestions
      def ft_suglen(key)
        call("FT.SUGLEN", key)
      end

      # Delete a suggestion
      #
      # @param key [String] Suggestion dictionary key
      # @param string [String] Suggestion to delete
      # @return [Integer] 1 if deleted, 0 otherwise
      def ft_sugdel(key, string)
        call("FT.SUGDEL", key, string)
      end

      # Get RediSearch configuration
      #
      # @param option [String] Configuration option (or "*" for all)
      # @return [Hash] Configuration values
      def ft_config_get(option = "*")
        result = call("FT.CONFIG", "GET", option)
        result.to_h
      end

      # Set RediSearch configuration
      #
      # @param option [String] Configuration option
      # @param value [String] Configuration value
      # @return [String] "OK"
      def ft_config_set(option, value)
        call("FT.CONFIG", "SET", option, value)
      end
    end
  end
end
