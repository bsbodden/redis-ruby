# Redis-Py vs Redis-Ruby Gap Analysis

**Date:** January 2026
**Analysis:** Comprehensive comparison of test coverage

## Executive Summary

Redis-ruby has **582 tests** vs Redis-py's **~1,100+ tests** across all modules. While redis-ruby has good breadth, it lacks depth in:
1. Advanced command options
2. Redis 7+/8+ features
3. Module-specific testing (Search, Cluster)

## Priority Implementation Plan

### Phase 1: Critical Missing Features (~90 tests)

#### 1.1 Hash Field Expiration (Redis 7.3+) - 20 tests
```ruby
# Commands to implement and test:
- HEXPIRE key seconds FIELDS count field [field ...]
- HPEXPIRE key milliseconds FIELDS count field [field ...]
- HEXPIREAT key unix-time-seconds FIELDS count field [field ...]
- HPEXPIREAT key unix-time-milliseconds FIELDS count field [field ...]
- Options: NX, XX, GT, LT
- HTTL, HPTTL, HEXPIRETIME, HPEXPIRETIME
- HPERSIST
```

#### 1.2 Conditional Expiration (Redis 7.0+) - 15 tests
```ruby
# Add options to existing commands:
- EXPIRE key seconds [NX | XX | GT | LT]
- PEXPIRE key milliseconds [NX | XX | GT | LT]
- EXPIREAT key unix-time-seconds [NX | XX | GT | LT]
- PEXPIREAT key unix-time-milliseconds [NX | XX | GT | LT]
```

#### 1.3 ZADD Advanced Options - 15 tests
```ruby
# Test combinations:
- ZADD key NX score member
- ZADD key XX score member
- ZADD key GT score member
- ZADD key LT score member
- ZADD key CH score member
- ZADD key NX CH score member
- ZADD key XX GT score member
```

#### 1.4 Sharded PubSub (Redis 7.0+) - 15 tests
```ruby
# New commands:
- SSUBSCRIBE shardchannel [shardchannel ...]
- SUNSUBSCRIBE [shardchannel [shardchannel ...]]
- SPUBLISH shardchannel message
```

#### 1.5 Additional Redis 7+ Commands - 25 tests
```ruby
# Missing commands:
- ZMPOP numkeys key [key ...] MIN | MAX [COUNT count]
- ZINTERCARD numkeys key [key ...] [LIMIT limit]
- LMPOP numkeys key [key ...] LEFT | RIGHT [COUNT count]
- XAUTOCLAIM key group consumer min-idle-time start [COUNT count] [JUSTID]
- EXPIRETIME key
- PEXPIRETIME key
```

### Phase 2: High Priority (~120 tests)

#### 2.1 PubSub Comprehensive - 25 tests
- Multiple channel subscriptions
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

#### 2.4 ZRANGE Unified Interface - 15 tests
```ruby
# Redis 6.2+ unified ZRANGE:
- ZRANGE key min max [BYSCORE | BYLEX] [REV] [LIMIT offset count] [WITHSCORES]
- ZRANGESTORE dst src min max [BYSCORE | BYLEX] [REV] [LIMIT offset count]
```

#### 2.5 Stream Enhancements - 15 tests
- XADD with NOMKSTREAM
- XADD with LIMIT
- XGROUP CREATE variants (MKSTREAM, ENTRIESREAD)
- XINFO STREAM with FULL

### Phase 3: Server/Admin Commands (~60 tests)

#### 3.1 CLIENT Commands - 15 tests
```ruby
- CLIENT LIST [TYPE normal|master|replica|pubsub] [ID id [id ...]]
- CLIENT KILL [ID client-id] [ADDR ip:port] [LADDR ip:port] [USER username] [MAXAGE maxage]
- CLIENT NO-EVICT ON|OFF
- CLIENT TRACKINGINFO
```

#### 3.2 Memory Commands - 10 tests
```ruby
- MEMORY DOCTOR
- MEMORY STATS
- MEMORY MALLOC-SIZE pointer
- MEMORY USAGE key [SAMPLES count]
```

#### 3.3 Latency Commands - 10 tests
```ruby
- LATENCY DOCTOR
- LATENCY GRAPH event
- LATENCY HISTORY event
- LATENCY LATEST
- LATENCY RESET [event [event ...]]
```

#### 3.4 ACL Commands - 15 tests
```ruby
- ACL LIST
- ACL GETUSER username
- ACL SETUSER username [rule [rule ...]]
- ACL DELUSER username [username ...]
- ACL CAT [categoryname]
- ACL LOG [count | RESET]
```

#### 3.5 Debug/Info - 10 tests
```ruby
- DEBUG SLEEP seconds
- DEBUG SEGFAULT
- INFO [section [section ...]]
- MODULE LIST
```

### Phase 4: Cluster Enhancements (~50 tests)

#### 4.1 Slot Management - 20 tests
```ruby
- CLUSTER ADDSLOTS slot [slot ...]
- CLUSTER DELSLOTS slot [slot ...]
- CLUSTER SETSLOT slot IMPORTING node-id
- CLUSTER SETSLOT slot MIGRATING node-id
- CLUSTER SETSLOT slot NODE node-id
- CLUSTER SETSLOT slot STABLE
```

#### 4.2 Node Management - 15 tests
```ruby
- CLUSTER MEET ip port
- CLUSTER FORGET node-id
- CLUSTER REPLICATE node-id
- CLUSTER FAILOVER [FORCE | TAKEOVER]
- CLUSTER RESET [HARD | SOFT]
```

#### 4.3 Cluster Info - 15 tests
```ruby
- CLUSTER INFO
- CLUSTER NODES
- CLUSTER SLOTS (deprecated, use CLUSTER SHARDS)
- CLUSTER SHARDS
- CLUSTER KEYSLOT key
- CLUSTER COUNTKEYSINSLOT slot
```

## Commands Completely Missing from redis-ruby

### Redis 7.0+ Commands
| Command | Description | Priority |
|---------|-------------|----------|
| `ZMPOP` | Pop from multiple sorted sets | High |
| `LMPOP` | Pop from multiple lists | High |
| `ZINTERCARD` | Cardinality of intersection | High |
| `XAUTOCLAIM` | Auto-claim pending stream entries | High |
| `EXPIRETIME` | Get absolute expiration time (seconds) | High |
| `PEXPIRETIME` | Get absolute expiration time (ms) | High |
| `SSUBSCRIBE` | Sharded subscribe | High |
| `SUNSUBSCRIBE` | Sharded unsubscribe | High |
| `SPUBLISH` | Sharded publish | High |

### Redis 7.3+ Commands (Hash Field Expiration)
| Command | Description | Priority |
|---------|-------------|----------|
| `HEXPIRE` | Set field expiration (seconds) | Critical |
| `HPEXPIRE` | Set field expiration (ms) | Critical |
| `HEXPIREAT` | Set field expiration (unix timestamp) | Critical |
| `HPEXPIREAT` | Set field expiration (unix timestamp ms) | Critical |
| `HTTL` | Get field TTL (seconds) | Critical |
| `HPTTL` | Get field TTL (ms) | Critical |
| `HEXPIRETIME` | Get field expiration time | Critical |
| `HPEXPIRETIME` | Get field expiration time (ms) | Critical |
| `HPERSIST` | Remove field expiration | Critical |

### Redis 8.0+ Commands
| Command | Description | Priority |
|---------|-------------|----------|
| `DELEX` | Conditional delete | Medium |
| `SET ... IFEQ` | Set if value equals | Medium |
| `SET ... IFNE` | Set if value not equals | Medium |

## Option Coverage Gaps

### Commands with untested options:

| Command | Missing Options |
|---------|-----------------|
| `ZADD` | `NX`, `XX`, `GT`, `LT`, `CH` combinations |
| `EXPIRE` | `NX`, `XX`, `GT`, `LT` |
| `GEOADD` | `NX`, `XX`, `CH` |
| `ZRANK` | `WITHSCORE` (Redis 7.2+) |
| `BITCOUNT` | `BYTE\|BIT` mode (Redis 7.0+) |
| `CLIENT KILL` | `ID`, `ADDR`, `LADDR`, `USER`, `MAXAGE` |
| `XADD` | `NOMKSTREAM`, `LIMIT` |
| `SCAN` | `TYPE` filter |

## Test Count Summary

| Phase | New Tests | Cumulative |
|-------|-----------|------------|
| Phase 1 (Critical) | 90 | 672 |
| Phase 2 (High) | 120 | 792 |
| Phase 3 (Server) | 60 | 852 |
| Phase 4 (Cluster) | 50 | 902 |
| **Total Target** | **320** | **~900** |

## Implementation Notes

1. **Use TestContainers with Redis 7.4+** for new feature tests
2. **Add version checks** for Redis version-specific features
3. **Create helper methods** for option combination testing
4. **Document breaking changes** between Redis versions
5. **Consider backwards compatibility** with Redis 6.x

## References

- Redis-py tests: `/workspace/references/redis-py/tests/`
- Redis commands documentation: https://redis.io/commands/
- Redis 7.0 release notes: https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/
