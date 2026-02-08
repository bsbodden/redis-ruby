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
      # Frozen command constants to avoid string allocations
      CMD_FT_CREATE = "FT.CREATE"
      CMD_FT_SEARCH = "FT.SEARCH"
      CMD_FT_AGGREGATE = "FT.AGGREGATE"
      CMD_FT_CURSOR = "FT.CURSOR"
      CMD_FT_INFO = "FT.INFO"
      CMD_FT_LIST = "FT._LIST"
      CMD_FT_DROPINDEX = "FT.DROPINDEX"
      CMD_FT_ALTER = "FT.ALTER"
      CMD_FT_ALIASADD = "FT.ALIASADD"
      CMD_FT_ALIASUPDATE = "FT.ALIASUPDATE"
      CMD_FT_ALIASDEL = "FT.ALIASDEL"
      CMD_FT_EXPLAIN = "FT.EXPLAIN"
      CMD_FT_EXPLAINCLI = "FT.EXPLAINCLI"
      CMD_FT_PROFILE = "FT.PROFILE"
      CMD_FT_SPELLCHECK = "FT.SPELLCHECK"
      CMD_FT_TAGVALS = "FT.TAGVALS"
      CMD_FT_SYNUPDATE = "FT.SYNUPDATE"
      CMD_FT_SYNDUMP = "FT.SYNDUMP"
      CMD_FT_DICTADD = "FT.DICTADD"
      CMD_FT_DICTDEL = "FT.DICTDEL"
      CMD_FT_DICTDUMP = "FT.DICTDUMP"
      CMD_FT_SUGADD = "FT.SUGADD"
      CMD_FT_SUGGET = "FT.SUGGET"
      CMD_FT_SUGLEN = "FT.SUGLEN"
      CMD_FT_SUGDEL = "FT.SUGDEL"
      CMD_FT_CONFIG = "FT.CONFIG"

      # Frozen subcommands
      SUBCMD_READ = "READ"
      SUBCMD_DEL = "DEL"
      SUBCMD_GET = "GET"
      SUBCMD_SET = "SET"

      # Frozen options
      OPT_DD = "DD"
      OPT_NOCONTENT = "NOCONTENT"
      OPT_VERBATIM = "VERBATIM"
      OPT_NOSTOPWORDS = "NOSTOPWORDS"
      OPT_INORDER = "INORDER"
      OPT_WITHSCORES = "WITHSCORES"
      OPT_WITHPAYLOADS = "WITHPAYLOADS"
      OPT_WITHSORTKEYS = "WITHSORTKEYS"
      OPT_EXPLAINSCORE = "EXPLAINSCORE"
      OPT_SCORER = "SCORER"
      OPT_LANGUAGE = "LANGUAGE"
      OPT_SLOP = "SLOP"
      OPT_FILTER = "FILTER"
      OPT_GEOFILTER = "GEOFILTER"
      OPT_INKEYS = "INKEYS"
      OPT_INFIELDS = "INFIELDS"
      OPT_RETURN = "RETURN"
      OPT_SUMMARIZE = "SUMMARIZE"
      OPT_FIELDS = "FIELDS"
      OPT_FRAGS = "FRAGS"
      OPT_LEN = "LEN"
      OPT_SEPARATOR = "SEPARATOR"
      OPT_HIGHLIGHT = "HIGHLIGHT"
      OPT_TAGS = "TAGS"
      OPT_SORTBY = "SORTBY"
      OPT_ASC = "ASC"
      OPT_DESC = "DESC"
      OPT_LIMIT = "LIMIT"
      OPT_PARAMS = "PARAMS"
      OPT_DIALECT = "DIALECT"
      OPT_TIMEOUT = "TIMEOUT"
      OPT_COUNT = "COUNT"
      OPT_LIMITED = "LIMITED"
      OPT_QUERY = "QUERY"
      OPT_DISTANCE = "DISTANCE"
      OPT_TERMS = "TERMS"
      OPT_INCLUDE = "INCLUDE"
      OPT_EXCLUDE = "EXCLUDE"
      OPT_SKIPINITIALSCAN = "SKIPINITIALSCAN"
      OPT_INCR = "INCR"
      OPT_PAYLOAD = "PAYLOAD"
      OPT_FUZZY = "FUZZY"
      OPT_MAX = "MAX"
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
      def ft_create(index_name, *)
        call(CMD_FT_CREATE, index_name, *)
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

        build_search_flags(args, options)
        build_search_scorer_and_language(args, options)
        build_search_filters(args, options)
        build_search_field_limits(args, options)
        build_search_summarize(args, options)
        build_search_highlight(args, options)
        build_search_sort_and_pagination(args, options)
        build_search_params(args, options)

        call(CMD_FT_SEARCH, *args)
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
      def ft_aggregate(index_name, query, *)
        call(CMD_FT_AGGREGATE, index_name, query, *)
      end

      # Read next batch of cursor results
      #
      # @param index_name [String] Index name
      # @param cursor_id [Integer] Cursor ID
      # @param count [Integer] Number of results to fetch
      # @return [Array] [results, cursor_id]
      def ft_cursor_read(index_name, cursor_id, count: nil)
        # Fast path: no count
        return call_3args(CMD_FT_CURSOR, SUBCMD_READ, index_name, cursor_id) unless count

        call(CMD_FT_CURSOR, SUBCMD_READ, index_name, cursor_id, OPT_COUNT, count)
      end

      # Delete a cursor
      #
      # @param index_name [String] Index name
      # @param cursor_id [Integer] Cursor ID
      # @return [String] "OK"
      def ft_cursor_del(index_name, cursor_id)
        call_3args(CMD_FT_CURSOR, SUBCMD_DEL, index_name, cursor_id)
      end

      # Get index information
      #
      # @param index_name [String] Index name
      # @return [Hash] Index metadata
      def ft_info(index_name)
        result = call_1arg(CMD_FT_INFO, index_name)
        # Convert array to hash (pairs of key, value)
        result.each_slice(2).to_h
      end

      # List all indexes
      #
      # @return [Array<String>] Index names
      def ft_list
        call(CMD_FT_LIST)
      end

      # Drop an index
      #
      # @param index_name [String] Index name
      # @param delete_docs [Boolean] Delete indexed documents (default: false)
      # @return [String] "OK"
      def ft_dropindex(index_name, delete_docs: false)
        # Fast path: no delete docs
        return call_1arg(CMD_FT_DROPINDEX, index_name) unless delete_docs

        call(CMD_FT_DROPINDEX, index_name, OPT_DD)
      end

      # Alter an index schema
      #
      # @param index_name [String] Index name
      # @param args [Array] Fields to add
      # @return [String] "OK"
      #
      # @example Add a new field
      #   redis.ft_alter("idx", "SCHEMA", "ADD", "new_field", "TEXT")
      def ft_alter(index_name, *)
        call(CMD_FT_ALTER, index_name, *)
      end

      # Add an alias to an index
      #
      # @param alias_name [String] Alias name
      # @param index_name [String] Index name
      # @return [String] "OK"
      def ft_aliasadd(alias_name, index_name)
        call_2args(CMD_FT_ALIASADD, alias_name, index_name)
      end

      # Update an alias to point to a different index
      #
      # @param alias_name [String] Alias name
      # @param index_name [String] Index name
      # @return [String] "OK"
      def ft_aliasupdate(alias_name, index_name)
        call_2args(CMD_FT_ALIASUPDATE, alias_name, index_name)
      end

      # Remove an alias
      #
      # @param alias_name [String] Alias name
      # @return [String] "OK"
      def ft_aliasdel(alias_name)
        call_1arg(CMD_FT_ALIASDEL, alias_name)
      end

      # Explain a search query
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param dialect [Integer] Dialect version
      # @return [String] Query execution plan
      def ft_explain(index_name, query, dialect: nil)
        # Fast path: no dialect
        return call_2args(CMD_FT_EXPLAIN, index_name, query) unless dialect

        call(CMD_FT_EXPLAIN, index_name, query, OPT_DIALECT, dialect)
      end

      # Explain query with CLI-friendly output
      #
      # @param index_name [String] Index name
      # @param query [String] Search query
      # @param dialect [Integer] Dialect version
      # @return [Array] Query execution plan
      def ft_explaincli(index_name, query, dialect: nil)
        # Fast path: no dialect
        return call_2args(CMD_FT_EXPLAINCLI, index_name, query) unless dialect

        call(CMD_FT_EXPLAINCLI, index_name, query, OPT_DIALECT, dialect)
      end

      # Profile a search or aggregate command
      #
      # @param index_name [String] Index name
      # @param type [String] "SEARCH" or "AGGREGATE"
      # @param limited [Boolean] Return limited results
      # @param query [String] Query to profile
      # @param args [Array] Additional query arguments
      # @return [Array] Profile results
      def ft_profile(index_name, type, query, *, limited: false)
        cmd = [index_name, type.to_s.upcase]
        cmd << OPT_LIMITED if limited
        cmd.push(OPT_QUERY, query, *)
        call(CMD_FT_PROFILE, *cmd)
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
        # Fast path: no options
        if distance.nil? && include.nil? && exclude.nil? && dialect.nil?
          return call_2args(CMD_FT_SPELLCHECK, index_name, query)
        end

        args = [index_name, query]
        build_spellcheck_options(args, distance: distance, include: include, exclude: exclude, dialect: dialect)
        call(CMD_FT_SPELLCHECK, *args)
      end

      # Get all distinct tag values
      #
      # @param index_name [String] Index name
      # @param field_name [String] Tag field name
      # @return [Array<String>] Distinct tag values
      def ft_tagvals(index_name, field_name)
        call_2args(CMD_FT_TAGVALS, index_name, field_name)
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
        args << OPT_SKIPINITIALSCAN if skipinitialscan
        args.concat(terms)
        call(CMD_FT_SYNUPDATE, *args)
      end

      # Dump synonym groups
      #
      # @param index_name [String] Index name
      # @return [Hash] Synonym groups
      def ft_syndump(index_name)
        result = call_1arg(CMD_FT_SYNDUMP, index_name)
        Hash[*result]
      end

      # Add terms to a dictionary
      #
      # @param dict_name [String] Dictionary name
      # @param terms [Array<String>] Terms to add
      # @return [Integer] Number of terms added
      def ft_dictadd(dict_name, *terms)
        call(CMD_FT_DICTADD, dict_name, *terms)
      end

      # Delete terms from a dictionary
      #
      # @param dict_name [String] Dictionary name
      # @param terms [Array<String>] Terms to delete
      # @return [Integer] Number of terms deleted
      def ft_dictdel(dict_name, *terms)
        call(CMD_FT_DICTDEL, dict_name, *terms)
      end

      # Dump dictionary contents
      #
      # @param dict_name [String] Dictionary name
      # @return [Array<String>] Dictionary terms
      def ft_dictdump(dict_name)
        call_1arg(CMD_FT_DICTDUMP, dict_name)
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
        # Fast path: no options
        return call_3args(CMD_FT_SUGADD, key, string, score) if !incr && payload.nil?

        args = [key, string, score]
        args << OPT_INCR if incr
        args.push(OPT_PAYLOAD, payload) if payload
        call(CMD_FT_SUGADD, *args)
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
        # Fast path: no options
        return call_2args(CMD_FT_SUGGET, key, prefix) if !fuzzy && !withscores && !withpayloads && max.nil?

        args = [key, prefix]
        build_sugget_options(args, fuzzy: fuzzy, withscores: withscores, withpayloads: withpayloads, max: max)
        call(CMD_FT_SUGGET, *args)
      end

      # Get suggestion dictionary size
      #
      # @param key [String] Suggestion dictionary key
      # @return [Integer] Number of suggestions
      def ft_suglen(key)
        call_1arg(CMD_FT_SUGLEN, key)
      end

      # Delete a suggestion
      #
      # @param key [String] Suggestion dictionary key
      # @param string [String] Suggestion to delete
      # @return [Integer] 1 if deleted, 0 otherwise
      def ft_sugdel(key, string)
        call_2args(CMD_FT_SUGDEL, key, string)
      end

      # Get RediSearch configuration
      #
      # @param option [String] Configuration option (or "*" for all)
      # @return [Hash] Configuration values
      def ft_config_get(option = "*")
        result = call_2args(CMD_FT_CONFIG, SUBCMD_GET, option)
        result.to_h
      end

      # Set RediSearch configuration
      #
      # @param option [String] Configuration option
      # @param value [String] Configuration value
      # @return [String] "OK"
      def ft_config_set(option, value)
        call_3args(CMD_FT_CONFIG, SUBCMD_SET, option, value)
      end

      private

      # Build boolean flag arguments for FT.SEARCH
      def build_search_flags(args, options)
        build_search_content_flags(args, options)
        build_search_with_flags(args, options)
      end

      # Build content/behavior flags
      def build_search_content_flags(args, options)
        args << OPT_NOCONTENT if options[:nocontent]
        args << OPT_VERBATIM if options[:verbatim]
        args << OPT_NOSTOPWORDS if options[:nostopwords]
        args << OPT_INORDER if options[:inorder]
      end

      # Build "with" modifier flags
      def build_search_with_flags(args, options)
        args << OPT_WITHSCORES if options[:withscores]
        args << OPT_WITHPAYLOADS if options[:withpayloads]
        args << OPT_WITHSORTKEYS if options[:withsortkeys]
        args << OPT_EXPLAINSCORE if options[:explainscore]
      end

      # Build scorer, language, and slop arguments
      def build_search_scorer_and_language(args, options)
        args.push(OPT_SCORER, options[:scorer]) if options[:scorer]
        args.push(OPT_LANGUAGE, options[:language]) if options[:language]
        args.push(OPT_SLOP, options[:slop]) if options[:slop]
      end

      # Build numeric and geo filter arguments
      def build_search_filters(args, options)
        options[:filter]&.each do |field, (min, max)|
          args.push(OPT_FILTER, field.to_s, min, max)
        end

        return unless options[:geofilter]

        options[:geofilter].each do |field, (lon, lat, radius, unit)|
          args.push(OPT_GEOFILTER, field.to_s, lon, lat, radius, unit || "km")
        end
      end

      # Build field limiting arguments (inkeys, infields, return)
      def build_search_field_limits(args, options)
        args.push(OPT_INKEYS, options[:inkeys].size, *options[:inkeys]) if options[:inkeys]

        args.push(OPT_INFIELDS, options[:infields].size, *options[:infields]) if options[:infields]

        return unless options[:return]

        fields = Array(options[:return])
        args.push(OPT_RETURN, fields.size, *fields)
      end

      # Build summarize arguments
      def build_search_summarize(args, options)
        return unless options[:summarize]

        args << OPT_SUMMARIZE
        return unless options[:summarize].is_a?(Hash)

        summarize = options[:summarize]
        if summarize[:fields]
          fields = Array(summarize[:fields])
          args.push(OPT_FIELDS, fields.size, *fields)
        end
        args.push(OPT_FRAGS, summarize[:frags]) if summarize[:frags]
        args.push(OPT_LEN, summarize[:len]) if summarize[:len]
        args.push(OPT_SEPARATOR, summarize[:separator]) if summarize[:separator]
      end

      # Build highlight arguments
      def build_search_highlight(args, options)
        return unless options[:highlight]

        args << OPT_HIGHLIGHT
        return unless options[:highlight].is_a?(Hash)

        highlight = options[:highlight]
        if highlight[:fields]
          fields = Array(highlight[:fields])
          args.push(OPT_FIELDS, fields.size, *fields)
        end
        return unless highlight[:tags]

        args.push(OPT_TAGS, highlight[:tags][0], highlight[:tags][1])
      end

      # Build sort and pagination arguments
      def build_search_sort_and_pagination(args, options)
        if options[:sortby]
          args.push(OPT_SORTBY, options[:sortby])
          args << (options[:sortasc] == false ? OPT_DESC : OPT_ASC)
        end

        return unless options[:limit]

        offset, count = options[:limit]
        args.push(OPT_LIMIT, offset, count)
      end

      # Build params, dialect, and timeout arguments
      def build_search_params(args, options)
        if options[:params]
          args.push(OPT_PARAMS, options[:params].size * 2)
          options[:params].each do |k, v|
            args.push(k.to_s, v.to_s)
          end
        end

        args.push(OPT_DIALECT, options[:dialect]) if options[:dialect]
        args.push(OPT_TIMEOUT, options[:timeout]) if options[:timeout]
      end

      # Build spellcheck optional arguments
      def build_spellcheck_options(args, distance:, include:, exclude:, dialect:)
        args.push(OPT_DISTANCE, distance) if distance
        args.push(OPT_TERMS, OPT_INCLUDE, include) if include
        args.push(OPT_TERMS, OPT_EXCLUDE, exclude) if exclude
        args.push(OPT_DIALECT, dialect) if dialect
      end

      # Build sugget optional arguments
      def build_sugget_options(args, fuzzy:, withscores:, withpayloads:, max:)
        args << OPT_FUZZY if fuzzy
        args << OPT_WITHSCORES if withscores
        args << OPT_WITHPAYLOADS if withpayloads
        args.push(OPT_MAX, max) if max
      end
    end
  end
end
