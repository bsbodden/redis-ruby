# redis-ruby Missing Tests Report

**Date:** January 2026
**Purpose:** Identify missing tests in redis-ruby by comparing against redis-rb and redis-py test coverage

---

## Executive Summary

After analyzing test coverage across redis-rb and redis-ruby, we identified **significant gaps** in redis-ruby's test suite. While redis-ruby has good coverage for core operations, it lacks tests for:

1. **Edge cases** (binary data, type coercion, special characters)
2. **Newer Redis features** (Redis 6.2+, 7.0+ options)
3. **Error handling** (invalid arguments, command errors)
4. **Blocking commands** (BLPOP, BRPOP, BZPOPMIN, etc.)
5. **Keys/Value types commands** (EXISTS, EXPIRE options, COPY, MOVE)

| Module | redis-rb Tests | redis-ruby Tests | Coverage Gap |
|--------|----------------|------------------|--------------|
| Strings | ~50 | 22 | **-56%** |
| Hashes | ~28 | 21 | -25% |
| Lists | ~25 | 13 | **-48%** |
| Sets | ~25 | 11 | **-56%** |
| Sorted Sets | ~80 | 19 | **-76%** |
| HyperLogLog | ~7 | 15 | +114% ✓ |
| Keys/Value Types | ~17 | 0 | **-100%** |
| Streams | ~60 | 39 | -35% |
| Blocking Commands | ~17 | 0 | **-100%** |
| Geo | N/A | 27 | ✓ |
| Bitmap | ~10 | 27 | +170% ✓ |

---

## redis-py Test Locations

**Main Commands:** `/workspace/references/redis-py/tests/test_commands.py`
**Hash Module:** `/workspace/references/redis-py/tests/test_hash.py`
**Cluster:** `/workspace/references/redis-py/tests/test_cluster.py`
**Sentinel:** `/workspace/references/redis-py/tests/test_sentinel.py`
**Connection Pool:** `/workspace/references/redis-py/tests/test_connection_pool.py`
**Pub/Sub:** `/workspace/references/redis-py/tests/test_pubsub.py`
**Pipeline:** `/workspace/references/redis-py/tests/test_pipeline.py`

### Bug-fix Tests from redis-py

| Issue | Test | Location |
|-------|------|----------|
| #924 | `test_sort_issue_924` | test_commands.py:4402 |
| #1128 | BaseException handling | test_commands.py:6662 |
| #2609 | `test_georadius_Issue2609` | test_commands.py:4868 |

---

## Detailed Analysis by Module

### 1. Strings

**redis-rb Location:** `/workspace/redis-rb/test/lint/strings.rb`
**redis-ruby Location:** `/workspace/redis-ruby/test/integration/commands/strings_test.rb`

#### Tests Present in redis-rb but Missing in redis-ruby:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_set_and_get` | Basic SET/GET | LOW (implicit) |
| `test_set_and_get_with_newline_characters` | Newline handling | **HIGH** |
| `test_set_and_get_with_non_string_value` | Array→string coercion | **HIGH** |
| `test_set_and_get_with_ascii_characters` | All 256 ASCII bytes | **HIGH** |
| `test_set_with_exat` | EXAT option (Redis 6.2+) | MEDIUM |
| `test_set_with_pxat` | PXAT option (Redis 6.2+) | MEDIUM |
| `test_set_with_nx` | NX with existing key behavior | MEDIUM |
| `test_set_with_xx` | XX option | MEDIUM |
| `test_set_with_keepttl` | KEEPTTL option (Redis 6.0+) | **HIGH** |
| `test_set_with_get` | GET option (Redis 6.2+) | **HIGH** |
| `test_setex_with_non_string_value` | Type coercion for SETEX | MEDIUM |
| `test_psetex_with_non_string_value` | Type coercion for PSETEX | MEDIUM |
| `test_getex` with persist | GETEX persist:true | **HIGH** |
| `test_getset_with_non_string_value` | Type coercion | MEDIUM |
| `test_setnx_with_non_string_value` | Type coercion | MEDIUM |
| `test_getbit` | Basic GETBIT (in Strings module) | MEDIUM |
| `test_setbit` | Basic SETBIT (in Strings module) | MEDIUM |
| `test_bitcount` | BITCOUNT in byte range | **HIGH** |
| `test_bitcount_bits_range` | BIT scale option (Redis 7.0+) | MEDIUM |
| `test_setrange_with_non_string_value` | Type coercion | MEDIUM |
| `test_bitfield` | BITFIELD operations | **HIGH** |
| `test_mget_mapped` | mapped_mget | MEDIUM |
| `test_mapped_mget_in_a_pipeline_returns_hash` | Pipeline behavior | MEDIUM |
| `test_mset_mapped` | mapped_mset | MEDIUM |
| `test_msetnx_mapped` | mapped_msetnx | MEDIUM |
| `test_bitop` | BITOP AND/OR/XOR/NOT | **HIGH** |

**Bug-fix related tests to add:**
- Binary data handling (all 256 ASCII bytes)
- Type coercion edge cases
- Redis 6.2+ options (EXAT, PXAT, GET)

**Additional from redis-py (test_commands.py):**

| redis-py Test | Line | Description | Priority |
|---------------|------|-------------|----------|
| `test_set_px` | 2481 | PX with DataError on float | **HIGH** |
| `test_set_ex_str` | 2504 | EX with string type, DataError on decimal | **HIGH** |
| `test_set_exat_timedelta` | 2517 | EXAT with datetime.timedelta | MEDIUM |
| `test_set_pxat_timedelta` | 2523 | PXAT with datetime.timedelta | MEDIUM |
| `test_set_keepttl` | 2535 | KEEPTTL preserves TTL | **HIGH** |
| `test_set_get` | 2636 | GET option returns previous value | **HIGH** |
| `test_set_ifeq` | 2544+ | IFEQ conditional set (Redis 8.3+) | LOW |
| `test_set_mutual_exclusion_client_side` | 2622 | DataError for invalid option combos | **HIGH** |
| `test_msetex_*` | 2145+ | MSETEX tests with various options | MEDIUM |

---

### 2. Hashes

**redis-rb Location:** `/workspace/redis-rb/test/lint/hashes.rb`
**redis-ruby Location:** `/workspace/redis-ruby/test/integration/commands/hashes_test.rb`

#### Tests Present in redis-rb but Missing in redis-ruby:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_variadic_hset` | HSET with hash argument | MEDIUM |
| `test_splat_hdel` | HDEL with splatted args | LOW |
| `test_variadic_hdel` | HDEL with array arg | LOW |
| `test_hmset_with_invalid_arguments` | Error on odd arg count | **HIGH** |
| `test_mapped_hmset` | HMSET with hash | MEDIUM |
| `test_hmget_mapped` | mapped_hmget | MEDIUM |
| `test_mapped_hmget_in_a_pipeline_returns_hash` | Pipeline behavior | MEDIUM |
| `test_hrandfield` with ArgumentError | Missing count validation | **HIGH** |
| `test_hrandfield` with negative count | Duplicate handling | MEDIUM |
| `test_hexpire` | Hash field expiration (Redis 7.4+) | LOW |
| `test_httl` | Hash field TTL (Redis 7.4+) | LOW |

**Bug-fix related tests to add:**
- HMSET with invalid odd argument count
- HRANDFIELD without count but with with_values

---

### 3. Lists

**redis-rb Location:** `/workspace/redis-rb/test/lint/lists.rb`
**redis-ruby Location:** `/workspace/redis-ruby/test/integration/commands/lists_test.rb`

#### Tests Present in redis-rb but Missing in redis-ruby:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_lmove` with nil return | Non-existent source | **HIGH** |
| `test_lmove` with same list | Rotating within list | **HIGH** |
| `test_lmove` invalid direction | ArgumentError test | **HIGH** |
| `test_variadic_lpush` | LPUSH with array | MEDIUM |
| `test_lpushx` | Push only if exists | **HIGH** |
| `test_variadic_rpush` | RPUSH with array | MEDIUM |
| `test_rpushx` | Push only if exists | **HIGH** |
| `test_lrange` empty key | Returns empty array | MEDIUM |
| `test_lpop` nil return | Non-existent key | MEDIUM |
| `test_lpop_count` | LPOP with count (Redis 6.2+) | **HIGH** |
| `test_rpop` nil return | Non-existent key | MEDIUM |
| `test_rpop_count` | RPOP with count (Redis 6.2+) | **HIGH** |
| `test_lset` error | Out of range index | **HIGH** |
| `test_linsert` invalid position | Error handling | MEDIUM |
| `test_rpoplpush` | RPOPLPUSH | MEDIUM |
| `test_blmpop` | Blocking LMPOP (Redis 7.0+) | MEDIUM |
| `test_lmpop` | LMPOP (Redis 7.0+) | MEDIUM |

**Additional from redis-py (test_commands.py):**

| redis-py Test | Line | Description | Priority |
|---------------|------|-------------|----------|
| `test_lpop_count` | 2874 | LPOP with count option | **HIGH** |
| `test_rpop_count` | 2942 | RPOP with count option | **HIGH** |
| `test_lpushx` | 2887 | LPUSHX basic | **HIGH** |
| `test_lpushx_with_list` | 2895 | LPUSHX with list argument | MEDIUM |
| `test_blpop` | 2772 | Blocking LPOP | **CRITICAL** |
| `test_brpop` | 2792 | Blocking RPOP | **CRITICAL** |
| `test_brpoplpush` | 2812 | Blocking RPOPLPUSH | **HIGH** |
| `test_brpoplpush_empty_string` | 2822 | Edge case | MEDIUM |

---

### 4. Sets

**redis-rb Location:** `/workspace/redis-rb/test/lint/sets.rb`
**redis-ruby Location:** `/workspace/redis-ruby/test/integration/commands/sets_test.rb`

#### Tests Present in redis-rb but Missing in redis-ruby:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_sadd?` | Boolean return variant | **HIGH** |
| `test_variadic_sadd` | SADD with array | MEDIUM |
| `test_variadic_sadd?` | Boolean with array | MEDIUM |
| `test_srem?` | Boolean return variant | **HIGH** |
| `test_variadic_srem` | SREM with array | MEDIUM |
| `test_variadic_srem?` | Boolean with array | MEDIUM |
| `test_spop_with_positive_count` | SPOP count option | **HIGH** |
| `test_srandmember` | Basic random member | MEDIUM |
| `test_srandmember_with_positive_count` | Unique random | **HIGH** |
| `test_srandmember_with_negative_count` | Possibly duplicate | **HIGH** |
| `test_smismember` | Multiple membership (Redis 6.2+) | **HIGH** |
| `test_sunionstore` | Store union result | MEDIUM |
| `test_sdiffstore` | Store diff result | MEDIUM |
| `test_sscan` | Cursor-based iteration | **HIGH** |

**Additional from redis-py (test_commands.py):**

| redis-py Test | Line | Description | Priority |
|---------------|------|-------------|----------|
| `test_smismember` | 3267 | Multiple member check | **HIGH** |
| `test_sintercard` | 3239 | SINTERCARD (Redis 7.0+) | MEDIUM |
| `test_spop_multi_value` | 3289 | SPOP with count | **HIGH** |

---

### 5. Sorted Sets

**redis-rb Location:** `/workspace/redis-rb/test/lint/sorted_sets.rb`
**redis-ruby Location:** `/workspace/redis-ruby/test/integration/commands/sorted_sets_test.rb`

#### Tests Present in redis-rb but Missing in redis-ruby:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_zadd` with XX option | Only update existing | **HIGH** |
| `test_zadd` with NX option | Only add new | **HIGH** |
| `test_zadd` with CH option | Return changed count | **HIGH** |
| `test_zadd` with INCR option | ZINCRBY behavior | **HIGH** |
| `test_zadd` with GT/LT options | Conditional update (Redis 6.2+) | **HIGH** |
| `test_zadd` incompatible options | XX+NX error | **HIGH** |
| `test_variadic_zadd` | Multiple score/member pairs | **HIGH** |
| `test_variadic_zadd` empty array | Edge case | MEDIUM |
| `test_variadic_zadd` wrong count | Error handling | **HIGH** |
| `test_zrank` with_score (Redis 7.2+) | Score with rank | MEDIUM |
| `test_zrevrank` with_score | Score with rank | MEDIUM |
| `test_zrange` with Infinity | -inf/+inf scores | **HIGH** |
| `test_zrange_with_byscore` | BYSCORE option (Redis 6.2+) | **HIGH** |
| `test_zrange_with_bylex` | BYLEX option (Redis 6.2+) | **HIGH** |
| `test_zrangestore` | Store range (Redis 6.2+) | MEDIUM |
| `test_zrangebyscore_with_limit` | LIMIT offset count | **HIGH** |
| `test_zrevrangebyscore_with_limit` | LIMIT offset count | **HIGH** |
| `test_zrangebyscore_with_withscores` | Score output | **HIGH** |
| `test_zmscore` | Multiple scores (Redis 6.2+) | **HIGH** |
| `test_zrandmember` | Random member (Redis 6.2+) | MEDIUM |
| `test_bzmpop` | Blocking ZMPOP (Redis 7.0+) | MEDIUM |
| `test_zmpop` | ZMPOP (Redis 7.0+) | MEDIUM |
| `test_zremrangebylex` | Remove by lex | MEDIUM |
| `test_zlexcount` | Count by lex | MEDIUM |
| `test_zrangebylex` | Range by lex | **HIGH** |
| `test_zrevrangebylex` | Reverse range by lex | **HIGH** |
| `test_zunion` | ZUNION (Redis 6.2+) | **HIGH** |
| `test_zunion_with_weights` | Weighted union | **HIGH** |
| `test_zunion_with_aggregate` | MIN/MAX aggregate | **HIGH** |
| `test_zunionstore_with_weights` | Weighted store | **HIGH** |
| `test_zunionstore_with_aggregate` | Aggregate store | **HIGH** |
| `test_zdiff` | ZDIFF (Redis 6.2+) | **HIGH** |
| `test_zdiffstore` | ZDIFFSTORE (Redis 6.2+) | **HIGH** |
| `test_zinter` | ZINTER (Redis 6.2+) | **HIGH** |
| `test_zinter_with_weights` | Weighted inter | **HIGH** |
| `test_zinter_with_aggregate` | Aggregate inter | **HIGH** |
| `test_zinterstore_with_weights` | Weighted store | **HIGH** |
| `test_zinterstore_with_aggregate` | Aggregate store | **HIGH** |
| `test_zscan` | Cursor iteration | **HIGH** |

**Additional from redis-py (test_commands.py):**

| redis-py Test | Line | Description | Priority |
|---------------|------|-------------|----------|
| `test_zadd_nx` | 3367 | ZADD NX option | **HIGH** |
| `test_zadd_xx` | 3377 | ZADD XX option | **HIGH** |
| `test_zadd_ch` | 3387 | ZADD CH option (changed count) | **HIGH** |
| `test_zadd_incr` | 3397 | ZADD INCR option | **HIGH** |
| `test_zadd_incr_with_xx` | 3401 | ZADD INCR + XX combo | **HIGH** |
| `test_zadd_gt_lt` | 3408 | ZADD GT/LT options | **HIGH** |
| `test_zinter` | 3479 | ZINTER command | **HIGH** |
| `test_zintercard` | 3518 | ZINTERCARD (Redis 7.0+) | MEDIUM |
| `test_zinterstore_sum` | 3526 | ZINTERSTORE with SUM | **HIGH** |
| `test_zinterstore_max` | 3539 | ZINTERSTORE with MAX | **HIGH** |
| `test_zinterstore_min` | 3552 | ZINTERSTORE with MIN | **HIGH** |
| `test_zinterstore_with_weight` | 3565 | ZINTERSTORE with weights | **HIGH** |
| `test_zrange_errors` | 3734 | ZRANGE error handling | **HIGH** |
| `test_zrange_params` | 3745 | ZRANGE with byscore/bylex | **HIGH** |
| `test_zrangestore` | 3784 | ZRANGESTORE command | **HIGH** |
| `test_zrank_withscore` | 3857 | ZRANK with score (Redis 7.2+) | MEDIUM |
| `test_zunion` | 3997 | ZUNION command | **HIGH** |
| `test_zunionstore_sum/max/min` | 4039+ | ZUNIONSTORE variants | **HIGH** |

---

### 6. Keys / Value Types (CRITICAL - NO TESTS!)

**redis-rb Location:** `/workspace/redis-rb/test/lint/value_types.rb`
**redis-ruby Location:** **MISSING** - No dedicated keys test file

#### ALL tests missing - create new test file:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_exists` | EXISTS command | **CRITICAL** |
| `test_variadic_exists` | Multiple keys | **CRITICAL** |
| `test_exists?` | Boolean variant | **CRITICAL** |
| `test_type` | TYPE command | **CRITICAL** |
| `test_keys` | KEYS pattern | **CRITICAL** |
| `test_expire` | EXPIRE command | **CRITICAL** |
| `test_expire` with NX/XX/GT/LT (Redis 7.0+) | Conditional | **HIGH** |
| `test_pexpire` | Millisecond expire | **CRITICAL** |
| `test_expireat` | EXPIREAT command | **CRITICAL** |
| `test_pexpireat` | PEXPIREAT | **CRITICAL** |
| `test_expiretime` (Redis 7.0+) | Get absolute time | **HIGH** |
| `test_pexpiretime` (Redis 7.0+) | Millisecond time | **HIGH** |
| `test_persist` | Remove expiration | **CRITICAL** |
| `test_ttl` | TTL command | **CRITICAL** |
| `test_pttl` | PTTL command | **CRITICAL** |
| `test_dump_and_restore` | Serialization | **HIGH** |
| `test_move` | Move to another DB | MEDIUM |
| `test_copy` (Redis 6.2+) | Copy key | **HIGH** |

---

### 7. Blocking Commands (CRITICAL - NO TESTS!)

**redis-rb Location:** `/workspace/redis-rb/test/lint/blocking_commands.rb`
**redis-ruby Location:** **MISSING** - No blocking commands test file

#### ALL tests missing - create new test file:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_blmove` | Blocking LMOVE (Redis 6.2+) | **HIGH** |
| `test_blpop` | Blocking LPOP | **CRITICAL** |
| `test_brpop` | Blocking RPOP | **CRITICAL** |
| `test_brpoplpush` | Blocking RPOPLPUSH | **HIGH** |
| `test_bzpopmin` | Blocking ZPOPMIN | **HIGH** |
| `test_bzpopmax` | Blocking ZPOPMAX | **HIGH** |
| `test_blpop_timeout` | Timeout handling | **CRITICAL** |
| `test_brpop_timeout` | Timeout handling | **CRITICAL** |
| `test_blpop_socket_timeout` | Socket timeout error | **HIGH** |
| `test_brpop_socket_timeout` | Socket timeout error | **HIGH** |

---

### 8. HyperLogLog ✓ GOOD COVERAGE

**Status:** redis-ruby has MORE tests than redis-rb

| redis-rb Test | redis-ruby Equivalent |
|---------------|----------------------|
| `test_pfadd` | ✓ `test_pfadd_single_element`, `test_pfadd_multiple_elements` |
| `test_variadic_pfadd` | ✓ `test_pfadd_with_many_elements` |
| `test_pfcount` | ✓ `test_pfcount_single_key`, `test_pfcount_approximate_cardinality` |
| `test_variadic_pfcount` | ✓ `test_pfcount_multiple_keys` |
| `test_pfmerge` | ✓ `test_pfmerge_single_source`, `test_pfmerge_multiple_sources` |

**Additional redis-ruby tests:** edge cases, memory efficiency

---

### 9. Streams

**redis-rb Location:** `/workspace/redis-rb/test/lint/streams.rb`
**redis-ruby Location:** `/workspace/redis-ruby/test/integration/commands/streams_test.rb`

#### Tests Present in redis-rb but Missing in redis-ruby:

| Missing Test | Description | Priority |
|--------------|-------------|----------|
| `test_xadd_with_invalid_entry_id_option` | Error handling | **HIGH** |
| `test_xadd_with_old_entry_id_option` | ID too old error | **HIGH** |
| `test_xadd_with_both_maxlen_and_minid` | ArgumentError | **HIGH** |
| `test_xadd_with_invalid_arguments` | Type errors | **HIGH** |
| `test_xtrim_with_limit_option` | LIMIT option (Redis 6.2+) | MEDIUM |
| `test_xtrim_with_maxlen_strategy` | MAXLEN strategy | MEDIUM |
| `test_xtrim_with_minid_strategy` | MINID strategy | MEDIUM |
| `test_xtrim_with_invalid_strategy` | Error handling | MEDIUM |
| `test_xtrim_with_not_existed_stream` | Edge case | MEDIUM |
| `test_xdel_with_invalid_entry_ids` | Invalid format handling | MEDIUM |
| `test_xdel_with_invalid_arguments` | Type errors | **HIGH** |
| `test_xrange_with_invalid_arguments` | Type errors | **HIGH** |
| `test_xrevrange_with_invalid_arguments` | Type errors | **HIGH** |
| `test_xread_with_block_option` | Blocking read | **HIGH** |
| `test_xread_with_invalid_arguments` | Error handling | **HIGH** |
| `test_xgroup_with_invalid_arguments` | Error handling | **HIGH** |
| `test_xreadgroup_with_invalid_arguments` | Error handling | **HIGH** |
| `test_xreadgroup_a_trimmed_entry` | Returns nil for deleted | **HIGH** |
| `test_xack_with_invalid_arguments` | Error handling | MEDIUM |
| `test_xclaim` with all options | IDLE, TIME, RETRYCOUNT, FORCE, JUSTID | **HIGH** |
| `test_xautoclaim` (Redis 6.2+) | Auto-claim pending | **HIGH** |
| `test_xpending_with_range_and_idle_options` | IDLE filter (Redis 6.2+) | MEDIUM |

---

### 10. Geo ✓ GOOD COVERAGE

**Status:** redis-ruby has comprehensive geo tests

No dedicated geo tests in redis-rb lint module (may be elsewhere).

---

### 11. Bitmap ✓ GOOD COVERAGE

**Status:** redis-ruby has MORE tests than redis-rb strings.rb bitmap section

---

## Recommended Priority Order

### Phase 1: Critical Missing Features
1. **Create keys_test.rb** - EXISTS, TYPE, EXPIRE, TTL, PERSIST
2. **Create blocking_commands_test.rb** - BLPOP, BRPOP with timeout
3. Add ZADD options tests (NX, XX, CH, INCR, GT, LT)
4. Add ZRANGE byscore/bylex tests

### Phase 2: Edge Cases and Error Handling
5. Add binary data tests for Strings (all 256 ASCII bytes)
6. Add type coercion tests (Array→String)
7. Add LPOP/RPOP count tests (Redis 6.2+)
8. Add LPUSHX/RPUSHX tests
9. Add LMOVE edge case tests

### Phase 3: Redis 6.2+ Features
10. Add SET with EXAT/PXAT/KEEPTTL/GET options
11. Add COPY command tests
12. Add ZUNION/ZDIFF/ZINTER tests
13. Add SMISMEMBER tests
14. Add XAUTOCLAIM tests

### Phase 4: Advanced Features
15. Add ZSCAN tests
16. Add SSCAN tests
17. Add mapped_mget/mapped_mset tests
18. Add pipeline behavior tests

---

## Test Count Targets

After implementing all missing tests:

| Module | Current | Target | Gap |
|--------|---------|--------|-----|
| Strings | 22 | 50 | +28 |
| Hashes | 21 | 30 | +9 |
| Lists | 13 | 25 | +12 |
| Sets | 11 | 25 | +14 |
| Sorted Sets | 19 | 60 | +41 |
| Keys | 0 | 20 | +20 |
| Blocking | 0 | 15 | +15 |
| Streams | 39 | 55 | +16 |
| **TOTAL** | **125** | **280** | **+155** |

---

## Files to Create

1. `/workspace/redis-ruby/test/integration/commands/keys_test.rb` - NEW
2. `/workspace/redis-ruby/test/integration/commands/blocking_test.rb` - NEW

## Files to Extend

1. `strings_test.rb` - Add 28 tests
2. `hashes_test.rb` - Add 9 tests
3. `lists_test.rb` - Add 12 tests
4. `sets_test.rb` - Add 14 tests
5. `sorted_sets_test.rb` - Add 41 tests
6. `streams_test.rb` - Add 16 tests

---

## Conclusion

redis-ruby has solid basic coverage but lacks:

1. **Edge case testing** - Binary data, type coercion, error conditions
2. **Modern Redis features** - Redis 6.2+ and 7.0+ options
3. **Blocking commands** - Critical for production use
4. **Keys management** - EXISTS, EXPIRE, TTL are fundamental

Addressing these gaps will bring redis-ruby to production-ready test coverage.
