# Redis-Ruby Code Quality Report

**Generated:** January 2026
**Tools Used:** Flog, Flay, Reek, Debride, Fasterer

## Executive Summary

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Flog Total | 3952.3 | 3803.9 | **-3.8%** |
| Flog Average | 5.6 | 5.3 | **-5.4%** |
| Flay Duplication | 6994 | 3558 | **-49%** |
| Performance Issues | 6 | 1 | **-83%** |

### Completed Refactoring (Session 3)

1. **Refactored `ft_search` method (170.6 → <30)** - Split into 8 focused helper methods
2. **Extracted `ts_incrby`/`ts_decrby` helpers** - Created `build_ts_incrby_decrby_args` and `build_ts_ignore_and_labels`

### Completed Refactoring (Session 2)

1. **Extracted `set()`/`get()` to Commands::Strings** - Eliminated duplication across 7 files (mass=3430)
2. **Created `Utils::URLParser` module** - Centralized URL parsing logic
3. **Extracted TimeSeries range helpers** - `build_range_args` and `build_mrange_args`
4. **Fixed Hash#fetch performance** - Changed to block syntax in 5 locations
5. **Extracted Hash expiration helpers** - `build_hexpire_args` and `build_expire_args`

## Priority 1: High Complexity Methods (Flog > 30)

These methods need refactoring due to high ABC complexity:

### Critical (>40 complexity)
| Method | Score | Location |
|--------|-------|----------|
| `subscription_loop` | 72.5 | lib/redis_ruby/commands/pubsub.rb:246-310 |
| `parse_cluster_nodes` | 48.3 | lib/redis_ruby/commands/cluster.rb:247-277 |
| `geosearch` | 45.4 | lib/redis_ruby/commands/geo.rb:113-152 |
| `geosearchstore` | 42.7 | lib/redis_ruby/commands/geo.rb:165-202 |

### High (30-40 complexity)
| Method | Score | Location |
|--------|-------|----------|
| `handle_command_error` | 34.1 | lib/redis_ruby/cluster_client.rb:270-298 |
| `execute_with_retry` | 34.0 | lib/redis_ruby/cluster_client.rb:223-267 |
| `vsim` | 30.0 | lib/redis_ruby/commands/vector_set.rb:99-129 |
| `fill_buffer` | 29.9 | lib/redis_ruby/protocol/buffered_io.rb:226-254 |
| `encode_command` | 29.9 | lib/redis_ruby/protocol/resp3_encoder.rb:42-64 |

**Note:** `ft_search` has been successfully refactored and is no longer a high-complexity method.

**Recommendation:** Break remaining high-complexity methods into smaller private methods with single responsibilities.

## Priority 2: Code Duplication (Flay)

### Critical Duplication (mass > 200)

#### 1. `set()` method duplicated in 7 files (mass = 3430)
**Impact:** Very High
**Files:**
- lib/redis_ruby/async_client.rb:132
- lib/redis_ruby/async_pooled_client.rb:150
- lib/redis_ruby/client.rb:119
- lib/redis_ruby/pipeline.rb:79
- lib/redis_ruby/pooled_client.rb:132
- lib/redis_ruby/sentinel_client.rb:158
- lib/redis_ruby/transaction.rb:91

**Fix:** Extract to `RedisRuby::Commands::Strings` module and include in all clients.

#### 2. `parse_url` method duplicated in 3 files (mass = 243)
**Files:**
- lib/redis_ruby/async_client.rb:222
- lib/redis_ruby/async_pooled_client.rb:249
- lib/redis_ruby/pooled_client.rb:231

**Fix:** Extract to `RedisRuby::Utils::URLParser` module.

#### 3. TimeSeries `ts_mrange`/`ts_mrevrange` (mass = 230)
**Files:**
- lib/redis_ruby/commands/time_series.rb:322
- lib/redis_ruby/commands/time_series.rb:357

**Fix:** Extract common logic to private `build_mrange_args` method.

#### 4. Hash expiration methods (mass = 180)
**Files:**
- lib/redis_ruby/commands/hashes.rb:176, 196, 216, 236

**Fix:** Extract to private `build_hexpire_args` helper method.

### High Duplication (mass 100-200)

| Issue | Mass | Files | Fix |
|-------|------|-------|-----|
| watch/unwatch methods | 162 | 3 files | Extract to module |
| expire/pexpire methods | 152 | keys.rb | Extract helper |
| ts_range/ts_revrange | 166 | time_series.rb | Extract helper |

## Priority 3: Performance Issues (Fasterer)

### Hash#fetch Optimization (12 occurrences in lib/)

**Current (slower):**
```ruby
options.fetch(:timeout, 5)
```

**Optimized (faster):**
```ruby
options.fetch(:timeout) { 5 }
```

**Files to fix:**
- lib/redis_ruby/async_pooled_client.rb:90
- lib/redis_ruby/connection/ssl.rb:157, 177, 184
- lib/redis_ruby/pooled_client.rb:71, 72

### each_with_index Optimization (1 occurrence in lib/)

**Current (slower):**
```ruby
items.each_with_index do |item, i|
  # use i
end
```

**Optimized (faster):**
```ruby
i = 0
while i < items.length
  item = items[i]
  # use i
  i += 1
end
```

**File to fix:**
- lib/redis_ruby/sentinel_manager.rb:59

## Priority 4: Architectural Improvements

### Extract Shared Modules

1. **RedisRuby::Commands::Core** - Common commands shared by all clients
   - `set`, `get`, `del`, `exists`, etc.
   - Currently duplicated across Client, AsyncClient, PooledClient, etc.

2. **RedisRuby::Utils::URLParser** - URL parsing logic
   - Currently duplicated in multiple client classes

3. **RedisRuby::Utils::CommandBuilder** - Command argument building
   - Many commands build similar argument arrays
   - Could use builder pattern

### Reduce Client Class Complexity

Current inheritance/composition is complex:
```
Client includes Commands::*
PooledClient wraps Pool<Client>
AsyncClient includes Commands::*
AsyncPooledClient wraps Pool<AsyncClient>
```

Consider using composition over inheritance more consistently.

## Implementation Plan

### Phase 1: Quick Wins (Low effort, high impact)
1. Fix Hash#fetch performance issues (~30 min)
2. Extract `build_hexpire_args` helper (~30 min)
3. Extract `build_mrange_args` helper (~30 min)

### Phase 2: Module Extraction (Medium effort, high impact)
1. Create `RedisRuby::Utils::URLParser` (~1 hour)
2. Create `RedisRuby::Commands::Core` with shared methods (~2 hours)
3. Update all client classes to use new modules (~2 hours)

### Phase 3: Complex Refactoring (High effort, high impact)
1. Refactor `ft_search` into smaller methods (~2 hours)
2. Refactor `subscription_loop` (~2 hours)
3. Refactor `parse_cluster_nodes` (~1 hour)

## Metrics After Improvements

| Metric | Current | Target |
|--------|---------|--------|
| Flog Total | 3952.3 | < 3000 |
| Flog Average | 5.6 | < 5.0 |
| Flay Duplication | 6994 | < 2000 |
| Methods > 30 complexity | 9 | 0 |

## Testing Impact

All refactoring should maintain 100% backward compatibility:
- No public API changes
- All existing tests must pass
- Add unit tests for new helper methods

## References

- [Flog Scoring Guide](https://github.com/seattlerb/flog)
- [Flay Documentation](https://github.com/seattlerb/flay)
- [Ruby Style Guide](https://rubystyle.guide/)
