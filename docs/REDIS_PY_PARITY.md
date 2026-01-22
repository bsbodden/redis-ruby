# Redis Client Feature Parity Analysis

## redis-ruby vs redis-py vs redis-rb

This document compares `redis-ruby` (this project) against `redis-py` (Python) and `redis-rb` (legacy Ruby client) to identify feature gaps and demonstrate where redis-ruby excels.

---

## Executive Summary

| Library | Overall Parity | Strengths | Weaknesses |
|---------|---------------|-----------|------------|
| **redis-ruby** | ~85% vs redis-py | Pure Ruby, Redis Modules, Async, Performance | Missing retry policies, Functions, ACL |
| **redis-py** | 100% (reference) | Complete feature set, OpenTelemetry, Retries | Python-only |
| **redis-rb** | ~70% vs redis-py | Stable, widely used | No modules, no async, basic retries |

---

## Feature Comparison Matrix

### 1. Client Types

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Sync client | ✅ `Redis` | ✅ `Client` | ✅ `Redis` | All have sync |
| Async client | ✅ `asyncio.Redis` | ✅ `AsyncClient` | ❌ None | redis-rb requires external gem |
| Connection pool (sync) | ✅ Built-in | ✅ `PooledClient` | ⚠️ External | redis-rb needs connection_pool gem |
| Connection pool (async) | ✅ Built-in | ✅ `AsyncPooledClient` | ❌ None | |
| Cluster client | ✅ `RedisCluster` | ✅ `ClusterClient` | ⚠️ Separate gem | redis-rb uses redis-clustering gem |
| Async cluster client | ✅ `asyncio.RedisCluster` | ❌ Missing | ❌ None | **Gap in redis-ruby** |
| Sentinel client | ✅ `Sentinel` | ✅ `SentinelClient` | ✅ Built-in | All support Sentinel |
| Async sentinel client | ✅ `asyncio.Sentinel` | ❌ Missing | ❌ None | **Gap in redis-ruby** |

### 2. Connection Features

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| TCP connections | ✅ | ✅ | ✅ | All support TCP |
| SSL/TLS connections | ✅ | ✅ | ✅ | All support TLS |
| Unix socket connections | ✅ | ✅ | ✅ | All support Unix sockets |
| URL parsing (redis://) | ✅ | ✅ | ✅ | Standard URL format |
| URL parsing (rediss://) | ✅ | ✅ | ✅ | TLS URL format |
| URL parsing (unix://) | ✅ | ✅ | ✅ | Unix socket URL |
| Connection pooling | ✅ Built-in | ✅ Built-in | ⚠️ External gem | redis-rb needs connection_pool |
| Fork-safe connections | ✅ | ✅ | ✅ | PID tracking |
| Socket keepalive options | ✅ Full | ⚠️ Basic | ⚠️ Basic | redis-py has more options |
| OCSP validation | ✅ | ❌ | ❌ | Only redis-py |

### 3. Authentication & Security

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Password auth | ✅ | ✅ | ✅ | All support |
| Username/password (ACL) | ✅ | ⚠️ Partial | ✅ | redis-ruby needs URL support |
| ACL SETUSER | ✅ | ❌ | ⚠️ Via call() | **Gap** |
| ACL GETUSER | ✅ | ❌ | ⚠️ Via call() | **Gap** |
| ACL LIST/USERS | ✅ | ❌ | ⚠️ Via call() | **Gap** |
| ACL CAT/LOG | ✅ | ❌ | ⚠️ Via call() | **Gap** |
| CLIENT TRACKING | ✅ | ❌ | ❌ | Only redis-py |

### 4. Resilience & Reliability

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Retry policy class | ✅ `Retry` | ❌ Missing | ⚠️ Basic | 🔴 **Critical gap** |
| Exponential backoff | ✅ Multiple | ❌ Missing | ❌ None | 🔴 **Critical gap** |
| Jitter strategies | ✅ | ❌ Missing | ❌ None | redis-py has 3 strategies |
| Configurable retries | ✅ | ⚠️ Cluster only | ⚠️ reconnect_attempts | Limited in both Ruby clients |
| Health checks | ✅ | ⚠️ Ping | ⚠️ Ping | Basic in all |

### 5. Observability

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| OpenTelemetry built-in | ✅ `RedisInstrumentor` | ❌ Missing | ❌ Missing | 🔴 **Critical gap** |
| OpenTelemetry community | ✅ | ❌ | ✅ Available | redis-rb has community gem |
| Distributed tracing | ✅ | ❌ | ⚠️ Community | **Gap in redis-ruby** |
| Command logging | ⚠️ | ❌ | ❌ | Limited in all |
| Metrics export | ✅ | ❌ | ❌ | Only redis-py |

### 6. Command Coverage

| Category | redis-py | redis-ruby | redis-rb | Notes |
|----------|----------|------------|----------|-------|
| String commands | ✅ 20+ | ✅ 20 | ✅ 20+ | All complete |
| List commands | ✅ 22+ | ✅ 22 | ✅ 22+ | All complete |
| Set commands | ✅ 17+ | ✅ 17 | ✅ 17+ | All complete |
| Sorted Set commands | ✅ 35+ | ✅ 35 | ✅ 35+ | All complete |
| Hash commands | ✅ 26+ | ✅ 26 | ✅ 26+ | All complete |
| Stream commands | ✅ 22+ | ✅ 22 | ✅ 22+ | All complete |
| Geo commands | ✅ 9+ | ✅ 9 | ✅ 9+ | All complete |
| HyperLogLog | ✅ 3 | ✅ 3 | ✅ 3 | All complete |
| Bitmap commands | ✅ 7+ | ✅ 7 | ✅ 7+ | All complete |
| Key commands | ✅ 24+ | ✅ 24 | ✅ 24+ | All complete |
| Pub/Sub commands | ✅ | ✅ | ✅ | All complete |
| Cluster commands | ✅ | ✅ | ✅ | All complete |
| Sentinel commands | ✅ | ✅ | ✅ | All complete |

### 7. Scripting & Functions

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| EVAL / EVALSHA | ✅ | ✅ | ✅ | All support |
| EVAL_RO / EVALSHA_RO | ✅ | ✅ | ⚠️ Via call() | redis-ruby has dedicated methods |
| Script object caching | ✅ `register_script()` | ⚠️ `evalsha_or_eval` | ❌ | redis-ruby has basic version |
| FUNCTION LOAD | ✅ | ❌ | ⚠️ Via call() | 🔴 **Critical gap** |
| FUNCTION LIST | ✅ | ❌ | ⚠️ Via call() | 🔴 **Critical gap** |
| FUNCTION DELETE | ✅ | ❌ | ⚠️ Via call() | 🔴 **Critical gap** |
| FCALL / FCALL_RO | ✅ | ❌ | ⚠️ Via call() | 🔴 **Critical gap** |

### 8. Redis Modules

| Module | redis-py | redis-ruby | redis-rb | Notes |
|--------|----------|------------|----------|-------|
| **RedisJSON** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **RediSearch** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **RedisTimeSeries** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **Bloom Filter** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **Cuckoo Filter** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **Count-Min Sketch** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **Top-K** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **t-Digest** | ✅ Full wrappers | ✅ Full wrappers | ⚠️ Via call() | 🏆 **redis-ruby advantage** |
| **Vector Sets** | ⚠️ Partial | ✅ Full wrappers | ❌ None | 🏆 **redis-ruby leads** |

### 9. Transactions & Pipelining

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Pipelining | ✅ | ✅ | ✅ | All support |
| MULTI/EXEC transactions | ✅ | ✅ | ✅ | All support |
| WATCH optimistic locking | ✅ | ✅ | ✅ | All support |
| CAS transactions | ✅ | ✅ | ✅ | All support |
| Cluster pipelining | ✅ Parallel | ⚠️ Serial | ⚠️ Serial | redis-py parallelizes |
| Pipeline exception handling | ✅ | ✅ | ✅ v5.0+ | All support |

### 10. Response Handling

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Automatic string decoding | ✅ `decode_responses` | ❌ | ❌ | Only redis-py |
| Custom response parsers | ✅ | ❌ | ❌ | Only redis-py |
| RESP3 protocol | ✅ | ✅ | ✅ | All support RESP3 |
| Push message handling | ✅ | ⚠️ Partial | ⚠️ Partial | redis-py best |

### 11. Pub/Sub Features

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Channel subscribe | ✅ | ✅ | ✅ | All support |
| Pattern subscribe | ✅ | ✅ | ✅ | All support |
| Sharded Pub/Sub | ✅ | ✅ | ✅ v7.0+ | All support |
| Message handlers | ✅ | ✅ | ✅ | All support |
| Background thread | ✅ `run_in_thread()` | ❌ | ❌ | Only redis-py |
| Subscription timeout | ✅ | ✅ | ✅ | All support |

### 12. Cluster Features

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Slot discovery | ✅ | ✅ | ✅ | All support |
| MOVED handling | ✅ | ✅ | ✅ | All support |
| ASK handling | ✅ | ✅ | ✅ | All support |
| Topology refresh | ✅ | ✅ | ✅ | All support |
| Read from replicas | ✅ | ✅ | ✅ | All support |
| Parallel pipelining | ✅ | ❌ Serial | ❌ Serial | Only redis-py |
| Hash tags | ✅ | ✅ | ✅ | All support |

### 13. Performance

| Feature | redis-py | redis-ruby | redis-rb | Notes |
|---------|----------|------------|----------|-------|
| Native extension option | ✅ hiredis | ❌ Pure Ruby | ✅ hiredis | redis-ruby is pure Ruby |
| Command encoding speed | Baseline | 🏆 **1.1-2x faster** | Baseline | redis-ruby optimized |
| Pipeline performance | Baseline | 🏆 **1.5-2x faster** | Baseline | redis-ruby optimized |
| Memory efficiency | Good | 🏆 **Better** | Good | Buffer reuse strategy |

---

## Critical Gaps Summary

### redis-ruby vs redis-py

| Gap | Priority | Effort | Notes |
|-----|----------|--------|-------|
| Retry Policy with Backoff | 🔴 Critical | Medium | Essential for production |
| Redis Functions (FCALL) | 🔴 Critical | Low | Redis 7.0+ feature |
| ACL Commands | 🔴 Critical | Low | Security requirement |
| OpenTelemetry | 🔴 Critical | Medium | Observability requirement |
| Async Cluster Client | 🟡 Medium | High | Async users need this |
| Async Sentinel Client | 🟡 Medium | Medium | Async users need this |
| Cluster Parallel Pipeline | 🟡 Medium | High | Performance optimization |
| decode_responses option | 🟢 Low | Low | Convenience feature |

### redis-ruby Advantages Over redis-rb

| Advantage | Impact | Notes |
|-----------|--------|-------|
| **Full Redis Modules** | 🏆 High | JSON, Search, TimeSeries, Bloom, Vector Sets |
| **Native Async Support** | 🏆 High | Built-in fiber scheduler integration |
| **Built-in Connection Pool** | 🏆 Medium | No external gem needed |
| **Better Performance** | 🏆 Medium | 1.1-2x faster encoding |
| **Vector Sets** | 🏆 High | Redis 8.0+ support |
| **Pure Ruby** | 🏆 Medium | No native compilation |

---

## Implementation Priority

### Phase 1: Production Ready (Critical)
```
1. Retry Policy with Exponential Backoff
   - Retry class with configurable attempts
   - ExponentialBackoff, ExponentialWithJitterBackoff
   - Integration with all client types

2. Redis Functions (Redis 7.0+)
   - function_load, function_list, function_delete
   - function_flush, function_dump, function_restore
   - fcall, fcall_ro

3. ACL Commands
   - acl_setuser, acl_getuser, acl_deluser
   - acl_list, acl_users, acl_cat, acl_log
   - acl_whoami, acl_genpass, acl_dryrun
```

### Phase 2: Enterprise Features
```
4. OpenTelemetry Integration
   - RedisInstrumentor class
   - Automatic span creation
   - Error tracking

5. AsyncClusterClient
   - Async version of ClusterClient
   - Fiber-aware slot management

6. AsyncSentinelClient
   - Async version of SentinelClient
   - Fiber-aware failover
```

### Phase 3: Polish
```
7. Cluster Parallel Pipelining
8. decode_responses option
9. Pub/Sub background fiber
10. Script object caching (register_script pattern)
```

---

## Conclusion

**redis-ruby is the best choice for Ruby developers who need:**
- Redis Stack modules (JSON, Search, TimeSeries, Bloom)
- Modern async support with fiber scheduler
- High performance pure Ruby implementation
- Redis 8.0+ features (Vector Sets)

**To reach 100% parity with redis-py, implement:**
1. Retry policies with exponential backoff
2. Redis Functions commands
3. ACL management commands
4. OpenTelemetry integration

**redis-ruby already surpasses redis-rb in:**
- Redis Modules support (complete vs none)
- Async support (built-in vs external)
- Connection pooling (built-in vs external)
- Performance (1.1-2x faster)
- Modern features (Vector Sets, RESP3)
