# frozen_string_literal: true

require_relative "../dsl/bloom_filter_proxy"
require_relative "../dsl/cuckoo_filter_proxy"
require_relative "../dsl/count_min_sketch_proxy"
require_relative "../dsl/top_k_proxy"

module RR
  module Commands
    # Redis Probabilistic Data Structures
    #
    # Provides probabilistic data structures for approximate computation:
    # - Bloom Filter (BF.*) - Test if element may exist in set
    # - Cuckoo Filter (CF.*) - Similar to bloom with deletion support
    # - Count-Min Sketch (CMS.*) - Frequency estimation
    # - Top-K (TOPK.*) - Track top K frequent items
    # - t-digest (TDIGEST.*) - Percentile estimation
    #
    # @see https://redis.io/docs/data-types/probabilistic/
    module Probabilistic
      # Frozen command constants to avoid string allocations
      # Bloom Filter
      CMD_BF_RESERVE = "BF.RESERVE"
      CMD_BF_ADD = "BF.ADD"
      CMD_BF_MADD = "BF.MADD"
      CMD_BF_EXISTS = "BF.EXISTS"
      CMD_BF_MEXISTS = "BF.MEXISTS"
      CMD_BF_INSERT = "BF.INSERT"
      CMD_BF_INFO = "BF.INFO"
      CMD_BF_CARD = "BF.CARD"
      CMD_BF_SCANDUMP = "BF.SCANDUMP"
      CMD_BF_LOADCHUNK = "BF.LOADCHUNK"

      # Cuckoo Filter
      CMD_CF_RESERVE = "CF.RESERVE"
      CMD_CF_ADD = "CF.ADD"
      CMD_CF_ADDNX = "CF.ADDNX"
      CMD_CF_INSERT = "CF.INSERT"
      CMD_CF_INSERTNX = "CF.INSERTNX"
      CMD_CF_EXISTS = "CF.EXISTS"
      CMD_CF_MEXISTS = "CF.MEXISTS"
      CMD_CF_DEL = "CF.DEL"
      CMD_CF_COUNT = "CF.COUNT"
      CMD_CF_INFO = "CF.INFO"
      CMD_CF_SCANDUMP = "CF.SCANDUMP"
      CMD_CF_LOADCHUNK = "CF.LOADCHUNK"

      # Count-Min Sketch
      CMD_CMS_INITBYDIM = "CMS.INITBYDIM"
      CMD_CMS_INITBYPROB = "CMS.INITBYPROB"
      CMD_CMS_INCRBY = "CMS.INCRBY"
      CMD_CMS_QUERY = "CMS.QUERY"
      CMD_CMS_MERGE = "CMS.MERGE"
      CMD_CMS_INFO = "CMS.INFO"

      # Top-K
      CMD_TOPK_RESERVE = "TOPK.RESERVE"
      CMD_TOPK_ADD = "TOPK.ADD"
      CMD_TOPK_INCRBY = "TOPK.INCRBY"
      CMD_TOPK_QUERY = "TOPK.QUERY"
      CMD_TOPK_COUNT = "TOPK.COUNT"
      CMD_TOPK_LIST = "TOPK.LIST"
      CMD_TOPK_INFO = "TOPK.INFO"

      # T-Digest
      CMD_TDIGEST_CREATE = "TDIGEST.CREATE"
      CMD_TDIGEST_ADD = "TDIGEST.ADD"
      CMD_TDIGEST_MERGE = "TDIGEST.MERGE"
      CMD_TDIGEST_RESET = "TDIGEST.RESET"
      CMD_TDIGEST_QUANTILE = "TDIGEST.QUANTILE"
      CMD_TDIGEST_RANK = "TDIGEST.RANK"
      CMD_TDIGEST_REVRANK = "TDIGEST.REVRANK"
      CMD_TDIGEST_CDF = "TDIGEST.CDF"
      CMD_TDIGEST_TRIMMED_MEAN = "TDIGEST.TRIMMED_MEAN"
      CMD_TDIGEST_MIN = "TDIGEST.MIN"
      CMD_TDIGEST_MAX = "TDIGEST.MAX"
      CMD_TDIGEST_INFO = "TDIGEST.INFO"
      CMD_TDIGEST_BYRANK = "TDIGEST.BYRANK"
      CMD_TDIGEST_BYREVRANK = "TDIGEST.BYREVRANK"

      # Frozen options
      OPT_EXPANSION = "EXPANSION"
      OPT_NONSCALING = "NONSCALING"
      OPT_CAPACITY = "CAPACITY"
      OPT_ERROR = "ERROR"
      OPT_NOCREATE = "NOCREATE"
      OPT_ITEMS = "ITEMS"
      OPT_BUCKETSIZE = "BUCKETSIZE"
      OPT_MAXITERATIONS = "MAXITERATIONS"
      OPT_WEIGHTS = "WEIGHTS"
      OPT_WITHCOUNT = "WITHCOUNT"
      OPT_COMPRESSION = "COMPRESSION"
      OPT_OVERRIDE = "OVERRIDE"

      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a Bloom Filter proxy for idiomatic operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis Bloom Filters.
      # Supports composite keys with automatic ":" joining.
      #
      # Bloom Filters are space-efficient probabilistic data structures for membership testing.
      # False positives are possible, but false negatives are not.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RR::DSL::BloomFilterProxy] Bloom Filter proxy instance
      #
      # @example Spam detection
      #   spam = redis.bloom_filter(:spam, :emails)
      #   spam.reserve(error_rate: 0.01, capacity: 100_000)
      #   spam.add("spam@example.com")
      #   spam.exists?("spam@example.com")  # => true
      #
      # @example Duplicate detection
      #   seen = redis.bloom_filter(:processed, :urls)
      #   seen.reserve(error_rate: 0.001, capacity: 1_000_000)
      #   seen.add(url) unless seen.exists?(url)
      def bloom_filter(*key_parts)
        DSL::BloomFilterProxy.new(self, *key_parts)
      end
      alias bloom bloom_filter

      # Create a Cuckoo Filter proxy for idiomatic operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis Cuckoo Filters.
      # Supports composite keys with automatic ":" joining.
      #
      # Cuckoo Filters are similar to Bloom Filters but support deletion and
      # generally have better lookup performance.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RR::DSL::CuckooFilterProxy] Cuckoo Filter proxy instance
      #
      # @example Session tracking
      #   sessions = redis.cuckoo_filter(:active, :sessions)
      #   sessions.reserve(capacity: 10_000)
      #   sessions.add("session:abc123")
      #   sessions.remove("session:abc123")  # Can delete!
      #
      # @example Cache admission
      #   cache = redis.cuckoo_filter(:cache, :admitted)
      #   cache.add_nx(key)  # Add only if not exists
      def cuckoo_filter(*key_parts)
        DSL::CuckooFilterProxy.new(self, *key_parts)
      end
      alias cuckoo cuckoo_filter

      # Create a Count-Min Sketch proxy for idiomatic operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis Count-Min Sketch.
      # Supports composite keys with automatic ":" joining.
      #
      # Count-Min Sketch is a probabilistic data structure for frequency estimation.
      # It may over-estimate but never under-estimates counts.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RR::DSL::CountMinSketchProxy] Count-Min Sketch proxy instance
      #
      # @example Page view counting
      #   pageviews = redis.count_min_sketch(:pageviews)
      #   pageviews.init_by_prob(error_rate: 0.001, probability: 0.01)
      #   pageviews.increment("/home", "/about")
      #   pageviews.query("/home")  # => 1
      #
      # @example Heavy hitter detection
      #   events = redis.count_min_sketch(:events)
      #   events.init_by_dim(width: 2000, depth: 5)
      #   events.increment_by("event:login", 100)
      def count_min_sketch(*key_parts)
        DSL::CountMinSketchProxy.new(self, *key_parts)
      end
      alias cms count_min_sketch

      # Create a Top-K proxy for idiomatic operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis Top-K.
      # Supports composite keys with automatic ":" joining.
      #
      # Top-K tracks the top K most frequent items in a stream with constant memory.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RR::DSL::TopKProxy] Top-K proxy instance
      #
      # @example Trending products
      #   trending = redis.top_k(:trending, :products)
      #   trending.reserve(k: 10)
      #   trending.add("product:123", "product:456")
      #   trending.list  # => ["product:123", "product:456", ...]
      #
      # @example Popular items with counts
      #   popular = redis.top_k(:popular, :items)
      #   popular.reserve(k: 5, width: 1000, depth: 5)
      #   popular.list(with_counts: true)
      def top_k(*key_parts)
        DSL::TopKProxy.new(self, *key_parts)
      end

      # ============================================================
      # Low-Level Commands
      # ============================================================

      # BLOOM FILTER COMMANDS

      # Create a new bloom filter
      #
      # @param key [String] Filter name
      # @param error_rate [Float] Desired error rate (0 to 1)
      # @param capacity [Integer] Expected number of items
      # @param expansion [Integer] Expansion factor for sub-filters
      # @param nonscaling [Boolean] Don't allow filter to scale
      # @return [String] "OK"
      #
      # @example Create with 1% error rate and 1000 capacity
      #   redis.bf_reserve("myfilter", 0.01, 1000)
      def bf_reserve(key, error_rate, capacity, expansion: nil, nonscaling: false)
        # Fast path: no options
        return call_3args(CMD_BF_RESERVE, key, error_rate, capacity) if expansion.nil? && !nonscaling

        args = [key, error_rate, capacity]
        args.push(OPT_EXPANSION, expansion) if expansion
        args << OPT_NONSCALING if nonscaling
        call(CMD_BF_RESERVE, *args)
      end

      # Add an item to bloom filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to add
      # @return [Integer] 1 if newly added, 0 if already exists
      def bf_add(key, item)
        call_2args(CMD_BF_ADD, key, item)
      end

      # Add multiple items to bloom filter
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to add
      # @return [Array<Integer>] 1 for each new item, 0 for existing
      def bf_madd(key, *items)
        call(CMD_BF_MADD, key, *items)
      end

      # Check if item exists in bloom filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to check
      # @return [Integer] 1 if may exist, 0 if definitely not
      def bf_exists(key, item)
        call_2args(CMD_BF_EXISTS, key, item)
      end

      # Check if multiple items exist in bloom filter
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to check
      # @return [Array<Integer>] 1 if may exist, 0 if definitely not
      def bf_mexists(key, *items)
        call(CMD_BF_MEXISTS, key, *items)
      end

      # Add item to bloom filter with auto-creation
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to add
      # @param capacity [Integer] Initial capacity (if creating)
      # @param error [Float] Error rate (if creating)
      # @param expansion [Integer] Expansion factor
      # @param nocreate [Boolean] Error if filter doesn't exist
      # @param nonscaling [Boolean] Don't scale the filter
      # @return [Array<Integer>] Results for each item
      def bf_insert(key, *items, capacity: nil, error: nil, expansion: nil, nocreate: false, nonscaling: false)
        args = [key]
        args.push(OPT_CAPACITY, capacity) if capacity
        args.push(OPT_ERROR, error) if error
        args.push(OPT_EXPANSION, expansion) if expansion
        args << OPT_NOCREATE if nocreate
        args << OPT_NONSCALING if nonscaling
        args.push(OPT_ITEMS, *items)
        call(CMD_BF_INSERT, *args)
      end

      # Get bloom filter information
      #
      # @param key [String] Filter name
      # @return [Hash] Filter information
      def bf_info(key)
        result = call_1arg(CMD_BF_INFO, key)
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # Get cardinality (estimated number of items)
      #
      # @param key [String] Filter name
      # @return [Integer] Estimated cardinality
      def bf_card(key)
        call_1arg(CMD_BF_CARD, key)
      end

      # Begin scanning a bloom filter
      #
      # @param key [String] Filter name
      # @param iterator [Integer] Iterator (0 for start)
      # @return [Array] [iterator, data] for incremental save
      def bf_scandump(key, iterator)
        call_2args(CMD_BF_SCANDUMP, key, iterator)
      end

      # Restore bloom filter from dump
      #
      # @param key [String] Filter name
      # @param iterator [Integer] Iterator from scandump
      # @param data [String] Data from scandump
      # @return [String] "OK"
      def bf_loadchunk(key, iterator, data)
        call_3args(CMD_BF_LOADCHUNK, key, iterator, data)
      end

      # CUCKOO FILTER COMMANDS

      # Create a cuckoo filter
      #
      # @param key [String] Filter name
      # @param capacity [Integer] Expected number of items
      # @param bucketsize [Integer] Items per bucket (default 2)
      # @param maxiterations [Integer] Max cuckoo kicks before failure
      # @param expansion [Integer] Growth factor
      # @return [String] "OK"
      def cf_reserve(key, capacity, bucketsize: nil, maxiterations: nil, expansion: nil)
        # Fast path: no options
        return call_2args(CMD_CF_RESERVE, key, capacity) if bucketsize.nil? && maxiterations.nil? && expansion.nil?

        args = [key, capacity]
        args.push(OPT_BUCKETSIZE, bucketsize) if bucketsize
        args.push(OPT_MAXITERATIONS, maxiterations) if maxiterations
        args.push(OPT_EXPANSION, expansion) if expansion
        call(CMD_CF_RESERVE, *args)
      end

      # Add item to cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to add
      # @return [Integer] 1 if added, 0 if exists
      def cf_add(key, item)
        call_2args(CMD_CF_ADD, key, item)
      end

      # Add item if it doesn't exist
      #
      # @param key [String] Filter name
      # @param item [String] Item to add
      # @return [Integer] 1 if added, 0 if already exists
      def cf_addnx(key, item)
        call_2args(CMD_CF_ADDNX, key, item)
      end

      # Add item to cuckoo filter with options
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to add
      # @param capacity [Integer] Capacity if creating
      # @param nocreate [Boolean] Don't create filter
      # @return [Array<Integer>] Results
      def cf_insert(key, *items, capacity: nil, nocreate: false)
        args = [key]
        args.push(OPT_CAPACITY, capacity) if capacity
        args << OPT_NOCREATE if nocreate
        args.push(OPT_ITEMS, *items)
        call(CMD_CF_INSERT, *args)
      end

      # Add items only if they don't exist
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to add
      # @param capacity [Integer] Capacity if creating
      # @param nocreate [Boolean] Don't create filter
      # @return [Array<Integer>] Results
      def cf_insertnx(key, *items, capacity: nil, nocreate: false)
        args = [key]
        args.push(OPT_CAPACITY, capacity) if capacity
        args << OPT_NOCREATE if nocreate
        args.push(OPT_ITEMS, *items)
        call(CMD_CF_INSERTNX, *args)
      end

      # Check if item exists in cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to check
      # @return [Integer] 1 if may exist, 0 if not
      def cf_exists(key, item)
        call_2args(CMD_CF_EXISTS, key, item)
      end

      # Check multiple items in cuckoo filter
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to check
      # @return [Array<Integer>] Results
      def cf_mexists(key, *items)
        call(CMD_CF_MEXISTS, key, *items)
      end

      # Delete item from cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to delete
      # @return [Integer] 1 if deleted, 0 if not found
      def cf_del(key, item)
        call_2args(CMD_CF_DEL, key, item)
      end

      # Get item count in cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to count
      # @return [Integer] Estimated count
      def cf_count(key, item)
        call_2args(CMD_CF_COUNT, key, item)
      end

      # Get cuckoo filter info
      #
      # @param key [String] Filter name
      # @return [Hash] Filter information
      def cf_info(key)
        result = call_1arg(CMD_CF_INFO, key)
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # Scan cuckoo filter for dump
      def cf_scandump(key, iterator)
        call_2args(CMD_CF_SCANDUMP, key, iterator)
      end

      # Restore cuckoo filter from dump
      def cf_loadchunk(key, iterator, data)
        call_3args(CMD_CF_LOADCHUNK, key, iterator, data)
      end

      # COUNT-MIN SKETCH COMMANDS

      # Create a count-min sketch
      #
      # @param key [String] Sketch name
      # @param width [Integer] Number of counters in each array
      # @param depth [Integer] Number of counter arrays
      # @return [String] "OK"
      def cms_initbydim(key, width, depth)
        call_3args(CMD_CMS_INITBYDIM, key, width, depth)
      end

      # Create count-min sketch by error rate
      #
      # @param key [String] Sketch name
      # @param error [Float] Error rate (0 to 1)
      # @param probability [Float] Probability of error (0 to 1)
      # @return [String] "OK"
      def cms_initbyprob(key, error, probability)
        call_3args(CMD_CMS_INITBYPROB, key, error, probability)
      end

      # Increment item count
      #
      # @param key [String] Sketch name
      # @param items [Array] item, increment pairs
      # @return [Array<Integer>] New counts
      #
      # @example Increment counts
      #   redis.cms_incrby("sketch", "item1", 5, "item2", 3)
      def cms_incrby(key, *items)
        call(CMD_CMS_INCRBY, key, *items)
      end

      # Get item counts
      #
      # @param key [String] Sketch name
      # @param items [Array<String>] Items to query
      # @return [Array<Integer>] Estimated counts
      def cms_query(key, *items)
        call(CMD_CMS_QUERY, key, *items)
      end

      # Merge sketches
      #
      # @param dest [String] Destination sketch
      # @param sources [Array<String>] Source sketches
      # @param weights [Array<Integer>] Optional weights
      # @return [String] "OK"
      def cms_merge(dest, *sources, weights: nil)
        args = [dest, sources.length, *sources]
        args.push(OPT_WEIGHTS, *weights) if weights
        call(CMD_CMS_MERGE, *args)
      end

      # Get sketch info
      #
      # @param key [String] Sketch name
      # @return [Hash] Sketch information
      def cms_info(key)
        result = call_1arg(CMD_CMS_INFO, key)
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # TOP-K COMMANDS

      # Create a top-k data structure
      #
      # @param key [String] Top-k name
      # @param k [Integer] Number of top items to keep
      # @param width [Integer] Width of count array
      # @param depth [Integer] Depth of count array
      # @param decay [Float] Decay rate
      # @return [String] "OK"
      def topk_reserve(key, k, width: nil, depth: nil, decay: nil)
        # Fast path: no options
        return call_2args(CMD_TOPK_RESERVE, key, k) if width.nil? && depth.nil? && decay.nil?

        args = [key, k]
        args << width if width
        args << depth if depth
        args << decay if decay
        call(CMD_TOPK_RESERVE, *args)
      end

      # Add items to top-k
      #
      # @param key [String] Top-k name
      # @param items [Array<String>] Items to add
      # @return [Array] Dropped items (or nil)
      def topk_add(key, *items)
        call(CMD_TOPK_ADD, key, *items)
      end

      # Increment item count
      #
      # @param key [String] Top-k name
      # @param items [Array] item, increment pairs
      # @return [Array] Dropped items (or nil)
      def topk_incrby(key, *items)
        call(CMD_TOPK_INCRBY, key, *items)
      end

      # Check if items are in top-k
      #
      # @param key [String] Top-k name
      # @param items [Array<String>] Items to check
      # @return [Array<Integer>] 1 if in top-k, 0 if not
      def topk_query(key, *items)
        call(CMD_TOPK_QUERY, key, *items)
      end

      # Get item counts
      #
      # @param key [String] Top-k name
      # @param items [Array<String>] Items to query
      # @return [Array<Integer>] Estimated counts
      def topk_count(key, *items)
        call(CMD_TOPK_COUNT, key, *items)
      end

      # List top-k items
      #
      # @param key [String] Top-k name
      # @param withcount [Boolean] Include counts
      # @return [Array] Top items (with optional counts)
      def topk_list(key, withcount: false)
        # Fast path: no options
        return call_1arg(CMD_TOPK_LIST, key) unless withcount

        call(CMD_TOPK_LIST, key, OPT_WITHCOUNT)
      end

      # Get top-k info
      #
      # @param key [String] Top-k name
      # @return [Hash] Top-k information
      def topk_info(key)
        result = call_1arg(CMD_TOPK_INFO, key)
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # T-DIGEST COMMANDS

      # Create a t-digest sketch
      #
      # @param key [String] Sketch name
      # @param compression [Integer] Compression factor (default 100)
      # @return [String] "OK"
      def tdigest_create(key, compression: nil)
        # Fast path: no options
        return call_1arg(CMD_TDIGEST_CREATE, key) if compression.nil?

        call(CMD_TDIGEST_CREATE, key, OPT_COMPRESSION, compression)
      end

      # Add values to t-digest
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to add
      # @return [String] "OK"
      def tdigest_add(key, *values)
        call(CMD_TDIGEST_ADD, key, *values)
      end

      # Merge t-digest sketches
      #
      # @param dest [String] Destination sketch
      # @param sources [Array<String>] Source sketches
      # @param compression [Integer] Override compression
      # @param override [Boolean] Override destination if exists
      # @return [String] "OK"
      def tdigest_merge(dest, *sources, compression: nil, override: false)
        args = [dest, sources.length, *sources]
        args.push(OPT_COMPRESSION, compression) if compression
        args << OPT_OVERRIDE if override
        call(CMD_TDIGEST_MERGE, *args)
      end

      # Reset t-digest
      #
      # @param key [String] Sketch name
      # @return [String] "OK"
      def tdigest_reset(key)
        call_1arg(CMD_TDIGEST_RESET, key)
      end

      # Get quantile values
      #
      # @param key [String] Sketch name
      # @param quantiles [Array<Float>] Quantiles to query (0-1)
      # @return [Array<Float>] Values at quantiles
      def tdigest_quantile(key, *quantiles)
        call(CMD_TDIGEST_QUANTILE, key, *quantiles)
      end

      # Get quantile ranks (reverse of quantile)
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to query
      # @return [Array<Float>] Ranks (0-1)
      def tdigest_rank(key, *values)
        call(CMD_TDIGEST_RANK, key, *values)
      end

      # Get reverse rank
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to query
      # @return [Array<Float>] Reverse ranks
      def tdigest_revrank(key, *values)
        call(CMD_TDIGEST_REVRANK, key, *values)
      end

      # Get CDF values
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to query
      # @return [Array<Float>] CDF values
      def tdigest_cdf(key, *values)
        call(CMD_TDIGEST_CDF, key, *values)
      end

      # Get trimmed mean
      #
      # @param key [String] Sketch name
      # @param low_percentile [Float] Lower percentile
      # @param high_percentile [Float] Upper percentile
      # @return [Float] Trimmed mean
      def tdigest_trimmed_mean(key, low_percentile, high_percentile)
        call_3args(CMD_TDIGEST_TRIMMED_MEAN, key, low_percentile, high_percentile)
      end

      # Get min value
      #
      # @param key [String] Sketch name
      # @return [Float] Minimum value
      def tdigest_min(key)
        call_1arg(CMD_TDIGEST_MIN, key)
      end

      # Get max value
      #
      # @param key [String] Sketch name
      # @return [Float] Maximum value
      def tdigest_max(key)
        call_1arg(CMD_TDIGEST_MAX, key)
      end

      # Get t-digest info
      #
      # @param key [String] Sketch name
      # @return [Hash] Sketch information
      def tdigest_info(key)
        result = call_1arg(CMD_TDIGEST_INFO, key)
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # Get values by rank
      #
      # @param key [String] Sketch name
      # @param ranks [Array<Integer>] Ranks to query
      # @return [Array<Float>] Values at ranks
      def tdigest_byrank(key, *ranks)
        call(CMD_TDIGEST_BYRANK, key, *ranks)
      end

      # Get values by reverse rank
      #
      # @param key [String] Sketch name
      # @param ranks [Array<Integer>] Reverse ranks to query
      # @return [Array<Float>] Values at reverse ranks
      def tdigest_byrevrank(key, *ranks)
        call(CMD_TDIGEST_BYREVRANK, key, *ranks)
      end
    end
  end
end
