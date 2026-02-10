# Redis-Py vs Redis-Ruby Gap Analysis

**Date:** January 2026 (Updated)
**Analysis:** Comprehensive comparison of test coverage

## Executive Summary

Redis-ruby has **~991 test methods** vs Redis-py's **~1,100+ tests** across all modules. We have achieved near parity in test coverage and have implemented all Phase 1 critical features.

### Implementation Status: ✅ Phase 1 COMPLETE

All Phase 1 critical features have been implemented with full test coverage:
- ✅ Hash Field Expiration (Redis 7.4+) - All commands with NX/XX/GT/LT options
- ✅ Conditional Expiration (Redis 7.0+) - EXPIRE/PEXPIRE/EXPIREAT/PEXPIREAT with NX/XX/GT/LT
- ✅ ZADD Advanced Options - NX/XX/GT/LT/CH combinations
- ✅ Sharded PubSub (Redis 7.0+) - SSUBSCRIBE/SUNSUBSCRIBE/SPUBLISH
- ✅ Redis 7+ Commands - ZMPOP/LMPOP/ZINTERCARD/XAUTOCLAIM/EXPIRETIME/PEXPIRETIME

## Implemented Commands (Confirmed)

### Hash Field Expiration (Redis 7.4+) ✅
```ruby
hexpire(key, seconds, *fields, nx:, xx:, gt:, lt:)
hpexpire(key, milliseconds, *fields, nx:, xx:, gt:, lt:)
hexpireat(key, unix_time, *fields, nx:, xx:, gt:, lt:)
hpexpireat(key, unix_time_ms, *fields, nx:, xx:, gt:, lt:)
httl(key, *fields)
hpttl(key, *fields)
hexpiretime(key, *fields)
hpexpiretime(key, *fields)
hpersist(key, *fields)
```

### Conditional Expiration (Redis 7.0+) ✅
```ruby
expire(key, seconds, nx:, xx:, gt:, lt:)
pexpire(key, milliseconds, nx:, xx:, gt:, lt:)
expireat(key, timestamp, nx:, xx:, gt:, lt:)
pexpireat(key, timestamp, nx:, xx:, gt:, lt:)
expiretime(key)
pexpiretime(key)
```

### ZADD Advanced Options ✅
```ruby
zadd(key, *score_members, nx:, xx:, gt:, lt:, ch:)
```

### Sharded PubSub (Redis 7.0+) ✅
```ruby
ssubscribe(*shardchannels, &block)
sunsubscribe(*shardchannels)
spublish(shardchannel, message)
pubsub_shardchannels(pattern)
pubsub_shardnumsub(*channels)
```

### Redis 7+ Commands ✅
```ruby
zmpop(*keys, modifier:, count:)
bzmpop(timeout, *keys, modifier:, count:)
zintercard(*keys, limit:)
lmpop(*keys, direction:, count:)
blmpop(timeout, *keys, direction:, count:)
xautoclaim(key, group, consumer, min_idle_time, start, count:, justid:)
```

### ZRANGE Unified Interface (Redis 6.2+) ✅
```ruby
zrange(key, start, stop, byscore:, bylex:, rev:, limit:, withscores:)
zrangestore(destination, key, start, stop, byscore:, bylex:, rev:, limit:)
```

## Remaining Gaps (Phase 2-4)

### Phase 2: High Priority (~120 tests)

#### 2.1 PubSub Comprehensive - 25 tests
- Multiple channel subscriptions (need more edge case tests)
- Pattern matching edge cases
- Subscription state validation
- Message ordering tests

#### 2.2 Search Module - 50 tests
- FT.AGGREGATE with GROUP BY, REDUCE
- FT.SUGADD, FT.SUGGET, FT.SUGDEL
- FT.SPELLCHECK
- FT.CONFIG
- Complex query syntax
- Vector similarity search

#### 2.3 JSON Module - 15 tests
- JSON.MGET (multi-key)
- JSON.ARRINSERT
- JSON.ARRTRIM
- JSON.TOGGLE
- JSON.CLEAR
- Complex path expressions

#### 2.4 Stream Enhancements - 15 tests
- Additional XINFO STREAM with FULL tests
- XGROUP CREATE variants edge cases

### Phase 3: Server/Admin Commands (~60 tests)

#### 3.1 CLIENT Commands - 15 tests
```ruby
# Commands to implement:
- CLIENT LIST [TYPE normal|master|replica|pubsub] [ID id [id ...]]
- CLIENT KILL [ID client-id] [ADDR ip:port] [LADDR ip:port] [USER username] [MAXAGE maxage]
- CLIENT NO-EVICT ON|OFF
- CLIENT TRACKINGINFO
```

#### 3.2 Memory Commands - 10 tests
```ruby
# Commands to implement:
- MEMORY DOCTOR
- MEMORY STATS
- MEMORY MALLOC-SIZE pointer
```

#### 3.3 Latency Commands - 10 tests
```ruby
# Commands to implement:
- LATENCY DOCTOR
- LATENCY GRAPH event
- LATENCY HISTORY event
- LATENCY LATEST
- LATENCY RESET [event [event ...]]
```

#### 3.4 ACL Commands - 15 tests
```ruby
# Commands to implement:
- ACL LIST
- ACL GETUSER username
- ACL SETUSER username [rule [rule ...]]
- ACL DELUSER username [username ...]
- ACL CAT [categoryname]
- ACL LOG [count | RESET]
```

#### 3.5 Debug/Info - 10 tests
```ruby
# Commands to implement:
- INFO [section [section ...]] - with section parsing
- MODULE LIST
```

### Phase 4: Cluster Enhancements (~50 tests)

#### 4.1 Slot Management - 20 tests
```ruby
# Commands to implement:
- CLUSTER ADDSLOTS slot [slot ...]
- CLUSTER DELSLOTS slot [slot ...]
- CLUSTER SETSLOT slot IMPORTING node-id
- CLUSTER SETSLOT slot MIGRATING node-id
- CLUSTER SETSLOT slot NODE node-id
- CLUSTER SETSLOT slot STABLE
```

#### 4.2 Node Management - 15 tests
```ruby
# Commands to implement:
- CLUSTER MEET ip port
- CLUSTER FORGET node-id
- CLUSTER REPLICATE node-id
- CLUSTER FAILOVER [FORCE | TAKEOVER]
- CLUSTER RESET [HARD | SOFT]
```

#### 4.3 Cluster Info - 15 tests
```ruby
# Commands to implement:
- CLUSTER INFO
- CLUSTER NODES
- CLUSTER SHARDS
- CLUSTER KEYSLOT key
- CLUSTER COUNTKEYSINSLOT slot
```

## Test Count Summary

| Phase | Status | Tests |
|-------|--------|-------|
| Phase 1 (Critical) | ✅ COMPLETE | ~150 |
| Phase 2 (High) | Partial | ~60/120 |
| Phase 3 (Server) | Minimal | ~10/60 |
| Phase 4 (Cluster) | Partial | ~30/50 |
| **Current Total** | | **~991** |
| **Target** | | **~1,100** |

## Code Quality Tools Added

The following tools have been added for code quality analysis (similar to Python's mfcqi):

```ruby
# Gemfile - quality group
gem "rubycritic"    # Unified quality report (wraps Flog, Flay, Reek)
gem "flog"          # ABC complexity metrics
gem "flay"          # Code duplication detection
gem "reek"          # Code smell detection
gem "debride"       # Find unused methods
gem "fasterer"      # Performance suggestions
```

Rake tasks:
- `rake quality:all` - Run all quality checks
- `rake quality:rubycritic` - Generate unified quality report
- `rake quality:flog` - ABC complexity analysis
- `rake quality:flay` - Code duplication detection
- `rake quality:reek` - Code smell detection
- `rake quality:report` - Generate HTML quality report

## References

- Redis-py tests: `/workspace/references/redis-py/tests/`
- Redis commands documentation: https://redis.io/commands/
- Redis 7.0 release notes: https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/
