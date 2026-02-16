# Redis Enterprise Features Analysis for redis-ruby

**Date:** 2026-02-16  
**Goal:** Make redis-ruby the most Enterprise Redis/Redis Cloud friendly Ruby client

## Executive Summary

redis-ruby already has **excellent enterprise feature coverage** compared to redis-rb. This analysis compares redis-ruby with leading clients (Jedis, redis-py, Lettuce) and identifies gaps to make redis-ruby the best choice for Redis Enterprise and Redis Cloud deployments.

## Current redis-ruby Enterprise Feature Coverage

### ✅ **Already Supported - Production Ready**

#### 1. **TLS/SSL Encryption** ✅
- **Status:** Fully implemented with SNI support
- **Implementation:** `lib/redis_ruby/connection/ssl.rb`
- **Features:**
  - TLS 1.2+ support (configurable min_version)
  - Server Name Indication (SNI) - **CRITICAL for Redis Enterprise/Cloud**
  - Certificate verification (VERIFY_PEER)
  - Custom CA certificates (ca_file, ca_path)
  - Client certificate authentication (mTLS)
  - Custom cipher suites
  - Post-connection hostname verification
- **Usage:**
  ```ruby
  redis = RR.new(url: "rediss://redis.cloud.redislabs.com:6379")
  # or
  redis = RR.new(
    host: "redis.cloud.redislabs.com",
    port: 6379,
    ssl: true,
    ssl_params: {
      verify_mode: OpenSSL::SSL::VERIFY_PEER,
      ca_file: "/path/to/ca.crt",
      cert: OpenSSL::X509::Certificate.new(File.read("client.crt")),
      key: OpenSSL::PKey::RSA.new(File.read("client.key")),
      min_version: OpenSSL::SSL::TLS1_2_VERSION
    }
  )
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 2. **Access Control Lists (ACL)** ✅
- **Status:** Full Redis 6.0+ ACL support
- **Implementation:** `lib/redis_ruby/commands/acl.rb`
- **Features:**
  - User management (ACL SETUSER, GETUSER, DELUSER, USERS)
  - Permission testing (ACL DRYRUN)
  - Security logging (ACL LOG)
  - Password generation (ACL GENPASS)
  - Category listing (ACL CAT)
  - Current user identification (ACL WHOAMI)
  - ACL persistence (ACL SAVE, ACL LOAD)
- **Usage:**
  ```ruby
  redis = RR.new(username: "myuser", password: "mypass")
  redis.acl_setuser("newuser", "on", ">password", "~*", "+@read")
  redis.acl_whoami  # => "myuser"
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 3. **Redis Sentinel (High Availability)** ✅
- **Status:** Full Sentinel support with automatic failover
- **Implementation:** `lib/redis_ruby/sentinel_client.rb`, `lib/redis_ruby/sentinel_manager.rb`
- **Features:**
  - Automatic master discovery
  - Automatic failover detection
  - Replica discovery and round-robin
  - Sentinel authentication
  - Minimum sentinel quorum
  - READONLY error handling
  - Connection retry with exponential backoff
- **Usage:**
  ```ruby
  redis = RR.sentinel(
    sentinels: [
      { host: "sentinel1", port: 26379 },
      { host: "sentinel2", port: 26379 },
      { host: "sentinel3", port: 26379 }
    ],
    service_name: "mymaster",
    password: "redis-password",
    sentinel_password: "sentinel-password"
  )
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 4. **Redis Cluster (Horizontal Scaling)** ✅
- **Status:** Full Cluster support with automatic sharding
- **Implementation:** `lib/redis_ruby/cluster_client.rb`, `lib/redis_ruby/cluster_topology.rb`
- **Features:**
  - Automatic slot mapping and routing
  - MOVED/ASK redirection handling
  - Read from replicas (`:replica`, `:replica_preferred`)
  - Cluster topology refresh
  - Hash tag support for multi-key operations
  - Host translation for NAT/Docker environments
  - Connection retry with exponential backoff
- **Usage:**
  ```ruby
  redis = RR.cluster(
    nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"],
    password: "cluster-password",
    read_from: :replica_preferred
  )
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 5. **Connection Pooling** ✅
- **Status:** Multiple pooling strategies
- **Implementation:** `lib/redis_ruby/connection/pool.rb`, `lib/redis_ruby/connection/async_pool.rb`
- **Features:**
  - Thread-safe connection pooling (using `connection_pool` gem)
  - Fiber-aware async pooling (using `async-pool` gem by Samuel Williams)
  - Configurable pool size and timeout
  - Lazy connection creation
  - Automatic connection reuse
- **Usage:**
  ```ruby
  # Thread-safe pool
  redis = RR.pooled(url: "redis://localhost:6379", pool: { size: 10, timeout: 5 })
  
  # Fiber-aware async pool
  Async do
    redis = RR.async_pooled(url: "redis://localhost:6379", pool: { limit: 10 })
  end
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 6. **RESP3 Protocol** ✅
- **Status:** Native RESP3 support (default)
- **Implementation:** `lib/redis_ruby/protocol/resp3_encoder.rb`, `lib/redis_ruby/protocol/resp3_decoder.rb`
- **Features:**
  - Full RESP3 protocol support
  - Client-side caching with push notifications
  - Improved type system (sets, maps, booleans, doubles)
  - Streaming responses
  - Attribute metadata
- **Usage:**
  ```ruby
  redis = RR.new  # RESP3 by default
  cache = RR::Cache.new(redis, max_entries: 10_000, ttl: 60)
  cache.enable!
  value = cache.get("key")  # Auto-invalidated via RESP3 push
  ```
- **Comparison:** **AHEAD** of redis-rb (RESP2 only), on par with Jedis/redis-py/Lettuce

#### 7. **Redis Stack / Advanced Features** ✅
- **Status:** Full support for all Redis Stack modules
- **Implementation:** Multiple command modules
- **Features:**
  - **RedisJSON** - Native JSON document storage (`lib/redis_ruby/commands/json.rb`)
  - **RediSearch** - Full-text search, vector search, aggregations (`lib/redis_ruby/commands/search.rb`)
  - **RedisTimeSeries** - Time series data with downsampling (`lib/redis_ruby/commands/time_series.rb`)
  - **RedisBloom** - Probabilistic data structures (`lib/redis_ruby/commands/probabilistic.rb`)
    - Bloom Filter, Cuckoo Filter, Count-Min Sketch, Top-K
  - **Vector Sets** - Native vector similarity search Redis 8+ (`lib/redis_ruby/commands/vector_set.rb`)
  - **Streams** - Redis Streams with consumer groups (`lib/redis_ruby/commands/streams.rb`)
  - **Pub/Sub** - Publish/Subscribe messaging (`lib/redis_ruby/commands/pubsub.rb`)
- **Usage:**
  ```ruby
  # RediSearch
  redis.index("products") do
    text :name
    numeric :price
    tag :category
  end

  # RedisJSON
  redis.json_set("user:1", "$", { name: "Alice", age: 30 })

  # RedisTimeSeries
  redis.ts_create("sensor:temp", retention: 86400)
  redis.ts_add("sensor:temp", "*", 23.5)
  ```
- **Comparison:** **AHEAD** of redis-rb (no Stack support), on par with Jedis/redis-py/Lettuce

#### 8. **Retry and Resilience** ✅
- **Status:** Configurable retry policies
- **Implementation:** `lib/redis_ruby/retry.rb`
- **Features:**
  - Exponential backoff with jitter
  - Configurable retry count
  - Custom retry policies
  - Automatic reconnection on fork
  - Connection health checking
- **Usage:**
  ```ruby
  redis = RR.new(reconnect_attempts: 3)
  # or custom policy
  redis = RR.new(
    retry_policy: RR::Retry.new(
      retries: 5,
      backoff: RR::ExponentialWithJitterBackoff.new(base: 0.025, cap: 2.0)
    )
  )
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 9. **Pipelining and Transactions** ✅
- **Status:** Full support for batching
- **Implementation:** `lib/redis_ruby/pipeline.rb`, `lib/redis_ruby/transaction.rb`
- **Features:**
  - Command pipelining for reduced round-trips
  - MULTI/EXEC transactions
  - WATCH for optimistic locking
  - Automatic error handling
- **Usage:**
  ```ruby
  # Pipelining
  redis.pipelined do |pipe|
    pipe.set("key1", "value1")
    pipe.set("key2", "value2")
  end

  # Transactions
  redis.multi do |txn|
    txn.set("key", "value")
    txn.incr("counter")
  end
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

#### 10. **Lua Scripting and Functions** ✅
- **Status:** Full Redis 7.0+ Functions support
- **Implementation:** `lib/redis_ruby/commands/scripting.rb`, `lib/redis_ruby/commands/functions.rb`
- **Features:**
  - EVAL, EVALSHA for Lua scripts
  - Script caching and management
  - Redis Functions (FUNCTION LOAD, FCALL, FCALL_RO)
  - Library management
- **Usage:**
  ```ruby
  # Lua scripting
  script = redis.script_load("return redis.call('GET', KEYS[1])")
  redis.evalsha(script, keys: ["mykey"])

  # Redis Functions
  redis.function_load(lua_library_code, replace: true)
  redis.fcall("myfunc", keys: ["key1"], args: ["arg1"])
  ```
- **Comparison:** On par with Jedis, redis-py, Lettuce

---

## ⚠️ **Missing Enterprise Features - Gaps to Address**

### 1. **Active-Active / CRDT Support** ❌
- **Status:** NOT IMPLEMENTED
- **Priority:** **HIGH** (Critical for Redis Enterprise)
- **Description:**
  - Redis Enterprise Active-Active databases use Conflict-Free Replicated Data Types (CRDTs)
  - Allows multi-region writes with automatic conflict resolution
  - Requires special handling for CRDT data types
- **What's Needed:**
  - CRDT-aware commands (CRDT.GET, CRDT.SET, etc.)
  - Active-Active database discovery
  - Multi-region connection management
  - CRDT conflict resolution strategies
- **Comparison:**
  - **Jedis:** Has Active-Active support
  - **redis-py:** Limited CRDT support
  - **Lettuce:** Has Active-Active support
- **Implementation Effort:** Medium-High (requires Redis Enterprise testing environment)

### 2. **Redis Enterprise Discovery Service** ❌
- **Status:** NOT IMPLEMENTED
- **Priority:** **MEDIUM**
- **Description:**
  - Redis Enterprise provides a discovery service for database endpoints
  - Allows clients to discover database endpoints dynamically
  - Useful for managed Redis Enterprise clusters
- **What's Needed:**
  - Discovery service client
  - Automatic endpoint resolution
  - Integration with Sentinel/Cluster clients
- **Comparison:**
  - **Jedis:** Has discovery service support
  - **redis-py:** Has discovery service support via `redis-py-cluster`
  - **Lettuce:** Has discovery service support
- **Implementation Effort:** Medium

### 3. **Enhanced Observability / Metrics** ⚠️
- **Status:** PARTIAL (basic error handling only)
- **Priority:** **MEDIUM-HIGH**
- **Description:**
  - Enterprise deployments need detailed metrics and observability
  - Connection pool metrics, command latency, error rates
  - Integration with monitoring systems (Prometheus, StatsD, OpenTelemetry)
- **What's Needed:**
  - Command execution metrics (latency, count, errors)
  - Connection pool metrics (active, idle, wait time)
  - Prometheus exporter or OpenTelemetry integration
  - Configurable metric collection
- **Comparison:**
  - **Jedis:** Has JMX metrics
  - **redis-py:** Limited metrics support
  - **Lettuce:** Has Micrometer metrics integration
- **Implementation Effort:** Medium

### 4. **Health Checks and Circuit Breaker** ⚠️
- **Status:** PARTIAL (basic connection health only)
- **Priority:** **MEDIUM**
- **Description:**
  - Enterprise applications need robust health checking
  - Circuit breaker pattern to prevent cascading failures
  - Automatic degradation and recovery
- **What's Needed:**
  - Periodic health checks (PING)
  - Circuit breaker implementation
  - Configurable failure thresholds
  - Health check callbacks
- **Comparison:**
  - **Jedis:** Has health checks
  - **redis-py:** Basic health checks
  - **Lettuce:** Has health checks and circuit breaker
- **Implementation Effort:** Low-Medium

### 5. **Connection Event Callbacks** ⚠️
- **Status:** PARTIAL (basic callbacks exist in `lib/redis_ruby/callbacks.rb`)
- **Priority:** **LOW-MEDIUM**
- **Description:**
  - Enterprise applications need visibility into connection lifecycle
  - Callbacks for connect, disconnect, reconnect, error events
  - Integration with logging and monitoring systems
- **What's Needed:**
  - Expand existing callback system
  - Add more event types (connect, disconnect, reconnect, error, command_start, command_end)
  - Thread-safe callback execution
  - Documentation and examples
- **Comparison:**
  - **Jedis:** Has connection listeners
  - **redis-py:** Limited callback support
  - **Lettuce:** Has comprehensive event system
- **Implementation Effort:** Low

### 6. **DNS-based Load Balancing** ❌
- **Status:** NOT IMPLEMENTED
- **Priority:** **LOW**
- **Description:**
  - Some Redis Enterprise deployments use DNS-based load balancing
  - Client should resolve DNS and connect to multiple IPs
  - Useful for cloud deployments with dynamic IPs
- **What's Needed:**
  - DNS resolution with multiple A records
  - Round-robin or random selection
  - Periodic DNS refresh
- **Comparison:**
  - **Jedis:** Limited DNS support
  - **redis-py:** Limited DNS support
  - **Lettuce:** Has DNS-based load balancing
- **Implementation Effort:** Low-Medium

---

## ✅ **Already Better Than redis-rb**

redis-ruby has **significant advantages** over redis-rb:

1. **RESP3 Protocol** - redis-rb only supports RESP2
2. **Redis Stack Support** - redis-rb has no Stack module support
3. **Idiomatic Ruby API** - redis-ruby has chainable proxies and DSLs
4. **Performance** - redis-ruby matches redis-rb + hiredis (pure Ruby!)
5. **Async Support** - redis-ruby has fiber-aware async clients
6. **Modern Architecture** - Clean separation of concerns, better testability

---

## 📊 **Feature Comparison Matrix**

| Feature | redis-ruby | redis-rb | Jedis | redis-py | Lettuce |
|---------|-----------|----------|-------|----------|---------|
| **TLS/SSL with SNI** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **ACL Support** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Sentinel** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Cluster** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Connection Pooling** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **RESP3** | ✅ | ❌ | ✅ | ✅ | ✅ |
| **Redis Stack** | ✅ | ❌ | ✅ | ✅ | ✅ |
| **Active-Active/CRDT** | ❌ | ❌ | ✅ | ⚠️ | ✅ |
| **Discovery Service** | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Metrics/Observability** | ⚠️ | ❌ | ✅ | ⚠️ | ✅ |
| **Circuit Breaker** | ⚠️ | ❌ | ⚠️ | ❌ | ✅ |
| **Async/Fiber Support** | ✅ | ❌ | ❌ | ✅ | ✅ |
| **Idiomatic API** | ✅ | ❌ | ⚠️ | ⚠️ | ⚠️ |

**Legend:** ✅ Full Support | ⚠️ Partial Support | ❌ Not Supported

---

## 🎯 **Recommended Priorities**

### **Phase 1: High Priority (Critical for Enterprise)**
1. **Active-Active / CRDT Support** - Essential for Redis Enterprise multi-region deployments
2. **Enhanced Observability** - Metrics, tracing, logging for production monitoring

### **Phase 2: Medium Priority (Nice to Have)**
3. **Discovery Service** - Simplifies Redis Enterprise integration
4. **Health Checks & Circuit Breaker** - Improves resilience

### **Phase 3: Low Priority (Future Enhancements)**
5. **Connection Event Callbacks** - Expand existing system
6. **DNS-based Load Balancing** - For specific cloud deployments

---

## 💡 **Conclusion**

**redis-ruby is already enterprise-ready** with excellent coverage of core enterprise features:
- ✅ TLS/SSL with SNI (critical for Redis Cloud)
- ✅ ACL for security
- ✅ Sentinel for HA
- ✅ Cluster for horizontal scaling
- ✅ Connection pooling for performance
- ✅ RESP3 for modern features
- ✅ Full Redis Stack support

**To become the BEST enterprise Ruby client**, we should focus on:
1. **Active-Active/CRDT support** - The biggest gap vs. Jedis/Lettuce
2. **Observability/Metrics** - Essential for production deployments
3. **Discovery Service** - Simplifies Redis Enterprise integration

**redis-ruby is already BETTER than redis-rb** for enterprise use cases and competitive with Jedis/redis-py/Lettuce in most areas!

