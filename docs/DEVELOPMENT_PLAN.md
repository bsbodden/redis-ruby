# redis-ruby Development Plan

## Vision: The Premier Redis Client for Ruby

**Goal**: Make redis-ruby the most complete, performant, and developer-friendly Redis client available for any language—not just Ruby.

### Why redis-ruby?

| Feature | redis-ruby | redis-rb | Jedis | Lettuce | redis-py |
|---------|------------|----------|-------|---------|----------|
| Pure Ruby (no native deps) | ✅ | ❌ hiredis | N/A | N/A | ✅ |
| RESP3 Native | ✅ | ⚠️ | ⚠️ | ✅ | ✅ |
| Async (Fibers) | ✅ | ❌ | ❌ | ✅ | ✅ |
| Redis Stack (JSON, Search, etc.) | ✅ | ❌ | ⚠️ | ⚠️ | ✅ |
| Connection Pooling | ✅ | ✅ | ✅ | ✅ | ✅ |
| Cluster Support | 🔜 | ✅ | ✅ | ✅ | ✅ |
| Performance vs hiredis | **2x faster** | baseline | N/A | N/A | N/A |

---

## Current Status

### Completed ✅

#### Phase 1: Foundation
- [x] Pure Ruby RESP3 protocol encoder/decoder
- [x] TCP connection with performance optimizations
- [x] SSL/TLS connection support
- [x] Unix socket connection support
- [x] Connection timeout handling
- [x] Error hierarchy (ConnectionError, CommandError, TimeoutError)

#### Phase 2: Core Commands
- [x] String commands (18 commands)
- [x] Key commands (23 commands)
- [x] Hash commands (16 commands)
- [x] List commands (21 commands)
- [x] Set commands (17 commands)
- [x] Sorted Set commands (22 commands)

#### Phase 3: Client Variants
- [x] Synchronous Client
- [x] AsyncClient (Fiber Scheduler)
- [x] PooledClient (Thread-safe)
- [x] AsyncPooledClient (Fiber-aware pooling)

#### Phase 4: Transactions & Pipelines
- [x] Pipeline support with optimized encoding
- [x] Transaction support (MULTI/EXEC)
- [x] WATCH/UNWATCH optimistic locking

#### Phase 5: Redis Stack Modules
- [x] RedisJSON (20 commands)
- [x] RediSearch (28 commands)
- [x] RedisTimeSeries (17 commands)
- [x] RedisBloom (49 commands: BF, CF, CMS, TopK, TDigest)
- [x] VectorSet (13 commands)

#### Phase 6: Sentinel
- [x] SentinelClient with auto-discovery
- [x] SentinelManager for failover
- [x] Sentinel commands (17 commands)
- [x] Automatic reconnection on failover

#### Phase 7: Performance
- [x] BufferedIO with optimized buffer management
- [x] Encoder buffer reuse (49% allocation reduction)
- [x] SIZE_CACHE for common integers
- [x] Pipeline 100 commands: 2.11x faster than redis-rb
- [x] Comprehensive benchmark suite

---

## Roadmap

### Phase 8: Redis Cluster (Critical)
**Target: Production-ready Cluster support**

```
Priority: 🔴 CRITICAL
Estimated Effort: 2-3 weeks
```

#### 8.1 Cluster Topology
- [ ] ClusterClient with slot-aware routing
- [ ] Cluster node discovery (CLUSTER SLOTS, CLUSTER NODES)
- [ ] Slot mapping and caching
- [ ] MOVED/ASK redirection handling
- [ ] Automatic topology refresh

#### 8.2 Cluster Commands
- [ ] CLUSTER INFO, CLUSTER NODES, CLUSTER SLOTS
- [ ] CLUSTER KEYSLOT, CLUSTER COUNTKEYSINSLOT
- [ ] CLUSTER ADDSLOTS, CLUSTER DELSLOTS
- [ ] CLUSTER FAILOVER, CLUSTER REPLICATE
- [ ] CLUSTER MEET, CLUSTER FORGET, CLUSTER RESET

#### 8.3 Cluster-Aware Operations
- [ ] Cluster-aware pipelining (group by slot)
- [ ] Multi-key command validation (same slot)
- [ ] Read from replicas (READONLY mode)
- [ ] Cross-slot transaction support (Lua)

#### 8.4 Cluster Resilience
- [ ] Node failure detection
- [ ] Automatic failover handling
- [ ] Retry with exponential backoff
- [ ] Circuit breaker for failed nodes

---

### Phase 9: Pub/Sub & Streams (Critical)
**Target: Real-time messaging support**

```
Priority: 🔴 CRITICAL
Estimated Effort: 1-2 weeks
```

#### 9.1 Pub/Sub
- [ ] SUBSCRIBE, UNSUBSCRIBE, PSUBSCRIBE, PUNSUBSCRIBE
- [ ] PUBLISH, PUBSUB CHANNELS/NUMSUB/NUMPAT
- [ ] PubSubClient with message handlers
- [ ] Pattern subscriptions
- [ ] Async message processing

#### 9.2 Streams
- [ ] XADD, XREAD, XREADGROUP
- [ ] XGROUP CREATE/DESTROY/SETID/DELCONSUMER
- [ ] XACK, XCLAIM, XAUTOCLAIM
- [ ] XLEN, XRANGE, XREVRANGE
- [ ] XINFO STREAM/GROUPS/CONSUMERS
- [ ] XTRIM, XDEL
- [ ] Consumer group management
- [ ] Blocking reads with timeout

#### 9.3 Stream Patterns
- [ ] Simple producer/consumer
- [ ] Consumer groups with acknowledgment
- [ ] Reliable queue with pending entries
- [ ] Stream processing helpers

---

### Phase 10: Scripting & Functions (Critical)
**Target: Server-side scripting support**

```
Priority: 🔴 CRITICAL
Estimated Effort: 1 week
```

#### 10.1 Lua Scripting
- [ ] EVAL, EVALSHA, EVALSHA_RO
- [ ] SCRIPT LOAD, SCRIPT EXISTS, SCRIPT FLUSH, SCRIPT KILL
- [ ] SCRIPT DEBUG
- [ ] Script caching (SHA1)
- [ ] Automatic EVALSHA with EVAL fallback

#### 10.2 Redis Functions (Redis 7+)
- [ ] FUNCTION LOAD, FUNCTION DELETE, FUNCTION FLUSH
- [ ] FUNCTION LIST, FUNCTION DUMP, FUNCTION RESTORE
- [ ] FCALL, FCALL_RO
- [ ] Function library management

---

### Phase 11: Missing Command Sets (Important)
**Target: Complete command coverage**

```
Priority: 🟡 IMPORTANT
Estimated Effort: 1 week
```

#### 11.1 Geospatial Commands
- [ ] GEOADD, GEOPOS, GEODIST
- [ ] GEOSEARCH, GEOSEARCHSTORE
- [ ] GEORADIUS, GEORADIUSBYMEMBER (deprecated but supported)
- [ ] GEOHASH

#### 11.2 HyperLogLog Commands
- [ ] PFADD, PFCOUNT, PFMERGE
- [ ] PFDEBUG, PFSELFTEST

#### 11.3 Bitmap Commands
- [ ] SETBIT, GETBIT
- [ ] BITCOUNT, BITPOS
- [ ] BITOP (AND, OR, XOR, NOT)
- [ ] BITFIELD, BITFIELD_RO

#### 11.4 Server Commands
- [ ] INFO, DBSIZE, FLUSHDB, FLUSHALL
- [ ] CONFIG GET/SET/REWRITE/RESETSTAT
- [ ] CLIENT LIST/KILL/SETNAME/GETNAME/ID
- [ ] CLIENT PAUSE/UNPAUSE/NO-EVICT
- [ ] DEBUG, MEMORY DOCTOR/MALLOC-SIZE/PURGE/STATS
- [ ] SLOWLOG GET/LEN/RESET
- [ ] LATENCY DOCTOR/GRAPH/HISTORY/LATEST
- [ ] ACL LIST/GETUSER/SETUSER/DELUSER/CAT/LOG

---

### Phase 12: Authentication & Security (Important)
**Target: Enterprise security support**

```
Priority: 🟡 IMPORTANT
Estimated Effort: 3-5 days
```

#### 12.1 ACL Support (Redis 6+)
- [ ] AUTH with username + password
- [ ] ACL command support
- [ ] Per-connection authentication
- [ ] Re-authentication on reconnect

#### 12.2 Security Features
- [ ] CLIENT SETINFO (library name/version)
- [ ] TLS certificate rotation support
- [ ] SNI (Server Name Indication) support
- [ ] Secrets redaction in logs

---

### Phase 13: Resilience & Reliability (Important)
**Target: Production-grade reliability**

```
Priority: 🟡 IMPORTANT
Estimated Effort: 1 week
```

#### 13.1 Automatic Reconnection
- [ ] Connection health monitoring
- [ ] Automatic reconnection with backoff
- [ ] Configurable retry policies
- [ ] Connection lifecycle hooks

#### 13.2 Command Retry
- [ ] Retryable command detection
- [ ] Exponential backoff with jitter
- [ ] Max retry attempts configuration
- [ ] Custom retry conditions

#### 13.3 Circuit Breaker
- [ ] Failure rate tracking
- [ ] Open/Half-Open/Closed states
- [ ] Configurable thresholds
- [ ] Fallback handlers

#### 13.4 Request Queue
- [ ] Command queuing during reconnection
- [ ] Queue size limits
- [ ] Timeout for queued commands
- [ ] Queue overflow handling

---

### Phase 14: Observability (Important)
**Target: Production monitoring**

```
Priority: 🟡 IMPORTANT
Estimated Effort: 1 week
```

#### 14.1 Logging
- [ ] Configurable log levels
- [ ] Structured logging (JSON)
- [ ] Command logging (with redaction)
- [ ] Connection event logging
- [ ] Integration with Ruby Logger

#### 14.2 Metrics
- [ ] Command latency histograms
- [ ] Connection pool utilization
- [ ] Error rates by type
- [ ] Throughput (commands/sec)
- [ ] Prometheus/StatsD exporters

#### 14.3 Tracing
- [ ] OpenTelemetry integration
- [ ] Span per command
- [ ] Distributed trace propagation
- [ ] Datadog/Jaeger/Zipkin support

#### 14.4 Event Listeners
- [ ] Connection events (connect, disconnect, reconnect)
- [ ] Command events (before, after, error)
- [ ] Cluster events (topology change, failover)
- [ ] Custom event handlers

---

### Phase 15: RESP3 Advanced Features (Nice to Have)
**Target: Full RESP3 compliance**

```
Priority: 🟢 NICE TO HAVE
Estimated Effort: 3-5 days
```

#### 15.1 Client-Side Caching
- [ ] CLIENT TRACKING ON/OFF
- [ ] Invalidation message handling
- [ ] Local cache with TTL
- [ ] Cache hit/miss metrics

#### 15.2 Push Notifications
- [ ] Push message parsing (already in decoder)
- [ ] Push message routing
- [ ] Async notification handlers

#### 15.3 RESP3 Attributes
- [ ] Attribute parsing from responses
- [ ] Metadata access API

---

### Phase 16: Advanced Topologies (Nice to Have)
**Target: Enterprise deployment support**

```
Priority: 🟢 NICE TO HAVE
Estimated Effort: 2 weeks
```

#### 16.1 Read/Write Splitting
- [ ] Configurable read preferences
- [ ] Read from replicas
- [ ] Write to master only
- [ ] Latency-based routing

#### 16.2 Multi-Master (Enterprise)
- [ ] Active-Active geo-distribution
- [ ] Conflict resolution strategies
- [ ] CRDTs support

#### 16.3 Sharding Strategies
- [ ] Hash slot-based (Cluster)
- [ ] Consistent hashing
- [ ] Custom sharding functions

---

### Phase 17: Developer Experience (Nice to Have)
**Target: Best-in-class DX**

```
Priority: 🟢 NICE TO HAVE
Estimated Effort: Ongoing
```

#### 17.1 Documentation
- [ ] Comprehensive YARD docs
- [ ] Getting Started guide
- [ ] Migration guide from redis-rb
- [ ] Performance tuning guide
- [ ] Cluster deployment guide

#### 17.2 Rails Integration
- [ ] Rails cache store
- [ ] Rails session store
- [ ] ActiveJob adapter
- [ ] Kredis compatibility

#### 17.3 CLI Tools
- [ ] redis-ruby CLI for testing
- [ ] Connection diagnostics
- [ ] Performance profiling

---

## Performance Targets

| Benchmark | Current | Target | vs redis-rb |
|-----------|---------|--------|-------------|
| Single GET/SET | same-ish | 1.3x | Network bound |
| Pipeline 10 | 1.33x | 1.5x | 🟡 Close |
| Pipeline 100 | **2.11x** | 2.0x | ✅ Exceeds |
| Connection Setup | same-ish | 1.0x | ✅ Pass |
| Memory/connection | ~10KB | <10KB | ✅ Pass |
| Cluster operations | N/A | 1.5x | TBD |

---

## Comparison with Competitors

### vs redis-rb
| Feature | redis-ruby | redis-rb |
|---------|------------|----------|
| Protocol | Pure Ruby RESP3 | hiredis (C) |
| Async | Fiber Scheduler | ❌ |
| Redis Stack | ✅ Full | ❌ |
| Performance | 2x faster | Baseline |
| Dependencies | Minimal | Native ext |

### vs Lettuce (Java)
| Feature | redis-ruby | Lettuce |
|---------|------------|---------|
| Async | ✅ Fibers | ✅ Netty |
| Reactive | ❌ | ✅ Reactor |
| Cluster | 🔜 | ✅ |
| Client Caching | 🔜 | ✅ |
| Metrics | 🔜 | ✅ |

### vs redis-py
| Feature | redis-ruby | redis-py |
|---------|------------|----------|
| Async | ✅ Fibers | ✅ asyncio |
| Redis Stack | ✅ | ✅ |
| Cluster | 🔜 | ✅ |
| Streams | 🔜 | ✅ |
| Pub/Sub | 🔜 | ✅ |

---

## Release Milestones

### v0.1.0 - Foundation (Released)
- Core data structures
- TCP/SSL/Unix connections
- Connection pooling
- Transactions & Pipelines

### v0.2.0 - Redis Stack (Released)
- JSON, Search, TimeSeries, BloomFilter, VectorSet
- Sentinel support
- Performance optimizations

### v0.3.0 - Real-Time (Next)
- Pub/Sub
- Streams
- Lua scripting

### v0.4.0 - Cluster
- Redis Cluster support
- Cluster-aware operations
- Read replicas

### v0.5.0 - Production Ready
- Complete command coverage
- ACL authentication
- Resilience patterns
- Observability

### v1.0.0 - Premier Release
- All features complete
- Comprehensive documentation
- Rails integration
- Enterprise support

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Priority Contributions Wanted
1. Redis Cluster implementation
2. Pub/Sub support
3. Streams implementation
4. Geo/HyperLogLog/Bitmap commands
5. Documentation

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Application                                                     │
├─────────────────────────────────────────────────────────────────┤
│  Client Layer                                                    │
│  ├── Client (sync)                                               │
│  ├── AsyncClient (fiber)                                         │
│  ├── PooledClient (thread-safe)                                  │
│  ├── AsyncPooledClient (fiber-pooled)                            │
│  ├── SentinelClient (failover)                                   │
│  └── ClusterClient (sharding)  [PLANNED]                         │
├─────────────────────────────────────────────────────────────────┤
│  Command Layer (12 modules, 282+ commands)                       │
│  ├── Strings, Keys, Hashes, Lists, Sets, SortedSets             │
│  ├── JSON, Search, TimeSeries, BloomFilter, VectorSet           │
│  ├── Pub/Sub, Streams, Scripting  [PLANNED]                     │
│  └── Geo, HyperLogLog, Bitmap  [PLANNED]                        │
├─────────────────────────────────────────────────────────────────┤
│  Topology Layer                                                  │
│  ├── Standalone                                                  │
│  ├── Sentinel (failover)                                         │
│  └── Cluster (sharding)  [PLANNED]                               │
├─────────────────────────────────────────────────────────────────┤
│  Connection Layer                                                │
│  ├── TCP (optimized)                                             │
│  ├── SSL/TLS                                                     │
│  ├── Unix Socket                                                 │
│  ├── Pool (thread-safe)                                          │
│  └── AsyncPool (fiber-aware)                                     │
├─────────────────────────────────────────────────────────────────┤
│  Protocol Layer (Pure Ruby RESP3)                                │
│  ├── RESP3Encoder (optimized, buffer reuse)                      │
│  ├── RESP3Decoder (streaming)                                    │
│  └── BufferedIO (efficient I/O)                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## License

MIT License - See [LICENSE](LICENSE) for details.
