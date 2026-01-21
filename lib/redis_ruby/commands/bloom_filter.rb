# frozen_string_literal: true

module RedisRuby
  module Commands
    # Redis Bloom Filter commands module
    #
    # Provides probabilistic data structures for membership testing:
    # - Bloom Filter (BF.*) - Test if element may exist in set
    # - Cuckoo Filter (CF.*) - Similar to bloom with deletion support
    # - Count-Min Sketch (CMS.*) - Frequency estimation
    # - Top-K (TOPK.*) - Track top K frequent items
    # - t-digest (TDIGEST.*) - Percentile estimation
    #
    # @see https://redis.io/docs/data-types/probabilistic/
    module BloomFilter
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
        args = [key, error_rate, capacity]
        args.push("EXPANSION", expansion) if expansion
        args << "NONSCALING" if nonscaling
        call("BF.RESERVE", *args)
      end

      # Add an item to bloom filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to add
      # @return [Integer] 1 if newly added, 0 if already exists
      def bf_add(key, item)
        call("BF.ADD", key, item)
      end

      # Add multiple items to bloom filter
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to add
      # @return [Array<Integer>] 1 for each new item, 0 for existing
      def bf_madd(key, *items)
        call("BF.MADD", key, *items)
      end

      # Check if item exists in bloom filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to check
      # @return [Integer] 1 if may exist, 0 if definitely not
      def bf_exists(key, item)
        call("BF.EXISTS", key, item)
      end

      # Check if multiple items exist in bloom filter
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to check
      # @return [Array<Integer>] 1 if may exist, 0 if definitely not
      def bf_mexists(key, *items)
        call("BF.MEXISTS", key, *items)
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
        args.push("CAPACITY", capacity) if capacity
        args.push("ERROR", error) if error
        args.push("EXPANSION", expansion) if expansion
        args << "NOCREATE" if nocreate
        args << "NONSCALING" if nonscaling
        args.push("ITEMS", *items)
        call("BF.INSERT", *args)
      end

      # Get bloom filter information
      #
      # @param key [String] Filter name
      # @return [Hash] Filter information
      def bf_info(key)
        result = call("BF.INFO", key)
        result.each_slice(2).to_h
      end

      # Get cardinality (estimated number of items)
      #
      # @param key [String] Filter name
      # @return [Integer] Estimated cardinality
      def bf_card(key)
        call("BF.CARD", key)
      end

      # Begin scanning a bloom filter
      #
      # @param key [String] Filter name
      # @param iterator [Integer] Iterator (0 for start)
      # @return [Array] [iterator, data] for incremental save
      def bf_scandump(key, iterator)
        call("BF.SCANDUMP", key, iterator)
      end

      # Restore bloom filter from dump
      #
      # @param key [String] Filter name
      # @param iterator [Integer] Iterator from scandump
      # @param data [String] Data from scandump
      # @return [String] "OK"
      def bf_loadchunk(key, iterator, data)
        call("BF.LOADCHUNK", key, iterator, data)
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
        args = [key, capacity]
        args.push("BUCKETSIZE", bucketsize) if bucketsize
        args.push("MAXITERATIONS", maxiterations) if maxiterations
        args.push("EXPANSION", expansion) if expansion
        call("CF.RESERVE", *args)
      end

      # Add item to cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to add
      # @return [Integer] 1 if added, 0 if exists
      def cf_add(key, item)
        call("CF.ADD", key, item)
      end

      # Add item if it doesn't exist
      #
      # @param key [String] Filter name
      # @param item [String] Item to add
      # @return [Integer] 1 if added, 0 if already exists
      def cf_addnx(key, item)
        call("CF.ADDNX", key, item)
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
        args.push("CAPACITY", capacity) if capacity
        args << "NOCREATE" if nocreate
        args.push("ITEMS", *items)
        call("CF.INSERT", *args)
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
        args.push("CAPACITY", capacity) if capacity
        args << "NOCREATE" if nocreate
        args.push("ITEMS", *items)
        call("CF.INSERTNX", *args)
      end

      # Check if item exists in cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to check
      # @return [Integer] 1 if may exist, 0 if not
      def cf_exists(key, item)
        call("CF.EXISTS", key, item)
      end

      # Check multiple items in cuckoo filter
      #
      # @param key [String] Filter name
      # @param items [Array<String>] Items to check
      # @return [Array<Integer>] Results
      def cf_mexists(key, *items)
        call("CF.MEXISTS", key, *items)
      end

      # Delete item from cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to delete
      # @return [Integer] 1 if deleted, 0 if not found
      def cf_del(key, item)
        call("CF.DEL", key, item)
      end

      # Get item count in cuckoo filter
      #
      # @param key [String] Filter name
      # @param item [String] Item to count
      # @return [Integer] Estimated count
      def cf_count(key, item)
        call("CF.COUNT", key, item)
      end

      # Get cuckoo filter info
      #
      # @param key [String] Filter name
      # @return [Hash] Filter information
      def cf_info(key)
        result = call("CF.INFO", key)
        result.each_slice(2).to_h
      end

      # Scan cuckoo filter for dump
      def cf_scandump(key, iterator)
        call("CF.SCANDUMP", key, iterator)
      end

      # Restore cuckoo filter from dump
      def cf_loadchunk(key, iterator, data)
        call("CF.LOADCHUNK", key, iterator, data)
      end

      # COUNT-MIN SKETCH COMMANDS

      # Create a count-min sketch
      #
      # @param key [String] Sketch name
      # @param width [Integer] Number of counters in each array
      # @param depth [Integer] Number of counter arrays
      # @return [String] "OK"
      def cms_initbydim(key, width, depth)
        call("CMS.INITBYDIM", key, width, depth)
      end

      # Create count-min sketch by error rate
      #
      # @param key [String] Sketch name
      # @param error [Float] Error rate (0 to 1)
      # @param probability [Float] Probability of error (0 to 1)
      # @return [String] "OK"
      def cms_initbyprob(key, error, probability)
        call("CMS.INITBYPROB", key, error, probability)
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
        call("CMS.INCRBY", key, *items)
      end

      # Get item counts
      #
      # @param key [String] Sketch name
      # @param items [Array<String>] Items to query
      # @return [Array<Integer>] Estimated counts
      def cms_query(key, *items)
        call("CMS.QUERY", key, *items)
      end

      # Merge sketches
      #
      # @param dest [String] Destination sketch
      # @param sources [Array<String>] Source sketches
      # @param weights [Array<Integer>] Optional weights
      # @return [String] "OK"
      def cms_merge(dest, *sources, weights: nil)
        args = [dest, sources.length, *sources]
        args.push("WEIGHTS", *weights) if weights
        call("CMS.MERGE", *args)
      end

      # Get sketch info
      #
      # @param key [String] Sketch name
      # @return [Hash] Sketch information
      def cms_info(key)
        result = call("CMS.INFO", key)
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
        args = [key, k]
        args << width if width
        args << depth if depth
        args << decay if decay
        call("TOPK.RESERVE", *args)
      end

      # Add items to top-k
      #
      # @param key [String] Top-k name
      # @param items [Array<String>] Items to add
      # @return [Array] Dropped items (or nil)
      def topk_add(key, *items)
        call("TOPK.ADD", key, *items)
      end

      # Increment item count
      #
      # @param key [String] Top-k name
      # @param items [Array] item, increment pairs
      # @return [Array] Dropped items (or nil)
      def topk_incrby(key, *items)
        call("TOPK.INCRBY", key, *items)
      end

      # Check if items are in top-k
      #
      # @param key [String] Top-k name
      # @param items [Array<String>] Items to check
      # @return [Array<Integer>] 1 if in top-k, 0 if not
      def topk_query(key, *items)
        call("TOPK.QUERY", key, *items)
      end

      # Get item counts
      #
      # @param key [String] Top-k name
      # @param items [Array<String>] Items to query
      # @return [Array<Integer>] Estimated counts
      def topk_count(key, *items)
        call("TOPK.COUNT", key, *items)
      end

      # List top-k items
      #
      # @param key [String] Top-k name
      # @param withcount [Boolean] Include counts
      # @return [Array] Top items (with optional counts)
      def topk_list(key, withcount: false)
        args = [key]
        args << "WITHCOUNT" if withcount
        call("TOPK.LIST", *args)
      end

      # Get top-k info
      #
      # @param key [String] Top-k name
      # @return [Hash] Top-k information
      def topk_info(key)
        result = call("TOPK.INFO", key)
        result.each_slice(2).to_h
      end

      # T-DIGEST COMMANDS

      # Create a t-digest sketch
      #
      # @param key [String] Sketch name
      # @param compression [Integer] Compression factor (default 100)
      # @return [String] "OK"
      def tdigest_create(key, compression: nil)
        args = [key]
        args.push("COMPRESSION", compression) if compression
        call("TDIGEST.CREATE", *args)
      end

      # Add values to t-digest
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to add
      # @return [String] "OK"
      def tdigest_add(key, *values)
        call("TDIGEST.ADD", key, *values)
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
        args.push("COMPRESSION", compression) if compression
        args << "OVERRIDE" if override
        call("TDIGEST.MERGE", *args)
      end

      # Reset t-digest
      #
      # @param key [String] Sketch name
      # @return [String] "OK"
      def tdigest_reset(key)
        call("TDIGEST.RESET", key)
      end

      # Get quantile values
      #
      # @param key [String] Sketch name
      # @param quantiles [Array<Float>] Quantiles to query (0-1)
      # @return [Array<Float>] Values at quantiles
      def tdigest_quantile(key, *quantiles)
        call("TDIGEST.QUANTILE", key, *quantiles)
      end

      # Get quantile ranks (reverse of quantile)
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to query
      # @return [Array<Float>] Ranks (0-1)
      def tdigest_rank(key, *values)
        call("TDIGEST.RANK", key, *values)
      end

      # Get reverse rank
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to query
      # @return [Array<Float>] Reverse ranks
      def tdigest_revrank(key, *values)
        call("TDIGEST.REVRANK", key, *values)
      end

      # Get CDF values
      #
      # @param key [String] Sketch name
      # @param values [Array<Float>] Values to query
      # @return [Array<Float>] CDF values
      def tdigest_cdf(key, *values)
        call("TDIGEST.CDF", key, *values)
      end

      # Get trimmed mean
      #
      # @param key [String] Sketch name
      # @param low_percentile [Float] Lower percentile
      # @param high_percentile [Float] Upper percentile
      # @return [Float] Trimmed mean
      def tdigest_trimmed_mean(key, low_percentile, high_percentile)
        call("TDIGEST.TRIMMED_MEAN", key, low_percentile, high_percentile)
      end

      # Get min value
      #
      # @param key [String] Sketch name
      # @return [Float] Minimum value
      def tdigest_min(key)
        call("TDIGEST.MIN", key)
      end

      # Get max value
      #
      # @param key [String] Sketch name
      # @return [Float] Maximum value
      def tdigest_max(key)
        call("TDIGEST.MAX", key)
      end

      # Get t-digest info
      #
      # @param key [String] Sketch name
      # @return [Hash] Sketch information
      def tdigest_info(key)
        result = call("TDIGEST.INFO", key)
        result.each_slice(2).to_h
      end

      # Get values by rank
      #
      # @param key [String] Sketch name
      # @param ranks [Array<Integer>] Ranks to query
      # @return [Array<Float>] Values at ranks
      def tdigest_byrank(key, *ranks)
        call("TDIGEST.BYRANK", key, *ranks)
      end

      # Get values by reverse rank
      #
      # @param key [String] Sketch name
      # @param ranks [Array<Integer>] Reverse ranks to query
      # @return [Array<Float>] Values at reverse ranks
      def tdigest_byrevrank(key, *ranks)
        call("TDIGEST.BYREVRANK", key, *ranks)
      end
    end
  end
end
