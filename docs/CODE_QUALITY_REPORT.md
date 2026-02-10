# Code Quality Report: redis-ruby

**Generated**: 2026-02-06
**Tools Used**: RuboCop 1.82, Reek 6.5, Flog 4.9, Flay 2.14, Debride 1.15, Fasterer 0.11, RubyCritic 4.11, Skunk 0.5, bundler-audit

---

## Executive Summary

| Metric | Value | Rating |
|--------|-------|--------|
| **Total Issues (all tools)** | **~12,100** | |
| RuboCop offenses | 9,052 (157 in lib/, 4,829 in test/, 4,066 in benchmarks) | |
| Reek code smells | 1,557 | |
| Flay duplications | 90 clusters (8,010 mass) | |
| Flog complexity | 7,723 total (5.2 avg/method) | |
| Fasterer perf suggestions | 396 | |
| Debride possibly unused | 486 methods | |
| RubyCritic Score | **41.65 / 100** | Needs improvement |
| Skunk StinkScore | **3,745 total** (63.5 avg) | |
| Test Coverage | 96.13% line / 92.47% branch | Excellent |
| Security Vulnerabilities | 0 known | Excellent |

### Key Insight

The vast majority of issues (**~8,900 of 9,052 RuboCop offenses**) are in **test/ and benchmarks/**, not production code. The **lib/ directory has only 157 RuboCop offenses** and those are predominantly Metrics cops (complexity thresholds). The production code is structurally sound but has complexity hotspots and significant code duplication that need attention.

---

## Priority 1: Autocorrectable (Quick Wins)

**~8,347 offenses can be auto-fixed with `bundle exec rubocop -A`**

These are purely stylistic and safe to auto-correct:

| Cop | Count | Location | Fix |
|-----|-------|----------|-----|
| `Minitest/EmptyLineBeforeAssertionMethods` | 3,152 | test/ | `rubocop -A` |
| `Style/StringLiterals` | 3,000 | everywhere | `rubocop -A` (single -> double quotes) |
| `Style/WordArray` | 827 | test/ | `rubocop -A` (`["a","b"]` -> `%w[a b]`) |
| `Style/NumericLiterals` | 156 | test/ | `rubocop -A` (`10000` -> `10_000`) |
| `Style/TrailingCommaInArrayLiteral` | 85 | test/ | `rubocop -A` |
| `Style/FormatStringToken` | 84 | mixed | `rubocop -A` |
| `Style/TrailingCommaInHashLiteral` | 46 | test/ | `rubocop -A` |
| `Style/StringLiteralsInInterpolation` | 39 | test/ | `rubocop -A` |
| `Style/PercentLiteralDelimiters` | 37 | mixed | `rubocop -A` |
| `Style/StringConcatenation` | 38 | mixed | `rubocop -A` |
| `Layout/EmptyLinesAfterModuleInclusion` | 30 | test/ | `rubocop -A` |
| Other autocorrectable Style/Layout | ~853 | mixed | `rubocop -A` |

**Action**: Run `bundle exec rubocop -A` to clear ~8,347 issues in one shot.

---

## Priority 2: Production Code (lib/) - 157 Offenses

These are the issues that actually matter for code quality:

### 2a. Complexity Cops (126 offenses)

| Cop | Count | Description |
|-----|-------|-------------|
| `Metrics/CyclomaticComplexity` | 46 | Methods with too many branches |
| `Metrics/PerceivedComplexity` | 43 | Methods that are hard to understand |
| `Metrics/MethodLength` | 19 | Methods exceeding 20 lines |
| `Metrics/AbcSize` | 8 | Assignment-Branch-Condition too high |
| `Metrics/ClassLength` | 6 | Classes exceeding line limit |
| `Metrics/BlockLength` | 2 | Blocks exceeding line limit |

**Worst offenders** (from Flog, score > 30):

| Method | Flog Score | File |
|--------|-----------|------|
| `RESP3Encoder#encode_pipeline` | 141.9 | `lib/redis_ruby/protocol/resp3_encoder.rb:262` |
| `RESP3Encoder#encode_command` | 96.1 | `lib/redis_ruby/protocol/resp3_encoder.rb:79` |
| `Redis#normalize_options` | 64.0 | `lib/redis.rb:1261` |
| `ClusterClient#handle_command_error` | 34.4 | `lib/redis_ruby/cluster_client.rb:294` |
| `ClusterClient#execute_with_retry` | 34.0 | `lib/redis_ruby/cluster_client.rb:247` |
| `Redis#multi` | 36.0 | `lib/redis.rb:198` |
| `Redis#script_exists` | 34.2 | `lib/redis.rb:1064` |
| `Redis#zadd` | 31.1 | `lib/redis.rb:743` |
| `ResponseCallbacks::parse_info` | 35.0 | `lib/redis_ruby/callbacks.rb` |

**Action**: Extract helper methods, use guard clauses, decompose case statements.

### 2b. Lint/Security Issues (12 offenses)

| Cop | Count | Severity | Description |
|-----|-------|----------|-------------|
| `Security/Eval` | 1 | **WARNING** | Use of `eval` - review for safety |
| `Lint/DuplicateBranch` | 5 | warning | Identical branches in conditionals |
| `Lint/EmptyConditionalBody` | 2 | warning | Empty if/else bodies |
| `Lint/HashCompareByIdentity` | 2 | warning | Hash using identity comparison |
| `Lint/NonLocalExitFromIterator` | 1 | warning | Return from within block |
| `Lint/UselessConstantScoping` | 1 | warning | Constant in wrong scope |

**Action**: Audit `Security/Eval` immediately. Fix lint warnings.

### 2c. Naming Issues (7 offenses)

| Cop | Count | Description |
|-----|-------|-------------|
| `Naming/MethodParameterName` | 7 | Single-char params like `k`, `v`, `n` |

---

## Priority 3: Code Duplication (Flay)

**90 duplication clusters** with total mass of **8,010**.

### Worst Duplications

| # | Mass | Type | Files | Description |
|---|------|------|-------|-------------|
| 1 | 891 | IDENTICAL | `lib/redis/pipeline.rb` (3 locations) | Three identical method definitions |
| 2 | 261 | IDENTICAL | `async_client.rb`, `async_pooled_client.rb`, `pooled_client.rb` | Same method across 3 client types |
| 3 | 228 | Similar | `geo.rb`, `hashes.rb`, `hyperloglog.rb`, `lists.rb`, `sets.rb`, `sorted_sets.rb`, `streams.rb` | Repeated command patterns |
| 4 | 196 | IDENTICAL | `lib/redis/pipeline.rb` (2 locations) | Duplicate pipeline methods |
| 5 | 189 | IDENTICAL | `lib/redis/pipeline.rb` (3 locations) | Another triple duplication |
| 6 | 176 | IDENTICAL | `lib/redis/pipeline.rb` (2 locations) | More pipeline duplication |
| 7 | 162 | IDENTICAL | `time_series.rb` (3 locations) | Repeated conditional blocks |

**Key patterns**:
- `lib/redis/pipeline.rb` has massive internal duplication (6+ clusters)
- Client types (`async_client`, `async_pooled_client`, `pooled_client`) share identical methods
- Command modules have repeated parameter handling patterns
- `resp3_encoder.rb` has similar `when` branches

**Action**: Extract shared modules, use `Forwardable`, create base client class, DRY command patterns.

---

## Priority 4: Code Smells (Reek) - 1,557 Total

| Smell Type | Count | Description |
|------------|-------|-------------|
| `BooleanParameter` | 261 | Methods accepting boolean flags |
| `LongParameterList` | 181 | Methods with > 3 parameters |
| `TooManyStatements` | 159 | Methods doing too much |
| `DuplicateMethodCall` | 151 | Same method called multiple times |
| `ControlParameter` | 139 | Boolean params controlling flow |
| `DataClump` | 126 | Groups of data always appearing together |
| `FeatureEnvy` | 124 | Methods envious of other classes |
| `UncommunicativeVariableName` | 93 | Names like `k`, `v`, `n`, `i` |
| `UncommunicativeParameterName` | 77 | Short parameter names |
| `NilCheck` | 72 | Explicit nil checks |
| `UtilityFunction` | 37 | Methods not using instance state |
| `RepeatedConditional` | 27 | Same condition checked multiple times |
| `TooManyConstants` | 26 | Classes with many constants |
| `TooManyInstanceVariables` | 19 | Classes with > 4 ivars |
| `TooManyMethods` | 19 | Classes with too many methods |
| `NestedIterators` | 16 | Nested blocks |
| `IrresponsibleModule` | 16 | Missing module documentation |
| `MissingSafeMethod` | 7 | Bang methods without non-bang version |

**Action**: Address `BooleanParameter` and `ControlParameter` with options hashes or enums. Use keyword arguments to fix `LongParameterList`. Rename variables.

---

## Priority 5: Performance Suggestions (Fasterer) - 396 Total

| Suggestion | Count | Impact |
|------------|-------|--------|
| `Hash#fetch(k, v)` -> `Hash#fetch(k) { v }` | 139 | Avoids allocating default every call |
| `each_with_index` -> `while` loop | 59 | Lower overhead iteration |
| `block.call` -> `yield` | 31 | Faster block invocation |
| `for` loop -> `each` | 31 | Idiomatic Ruby |
| Symbol to proc (`&:method`) | 69 | Faster than block |
| Rescue `NoMethodError` -> `respond_to?` | 20 | Avoid exception overhead |
| `sort` -> `sort_by` | 19 | Faster for complex comparisons |
| `attr_reader` for ivars | 16 | Method dispatch optimization |
| `attr_writer` for ivars | 8 | Method dispatch optimization |
| `Hash#keys.each` -> `Hash#each_key` | 9 | Avoids array allocation |
| `Hash#merge!` -> `Hash#[]` | 8 | Faster single-key assignment |
| `tr` instead of `gsub` | 6 | Faster single-char replace |
| `cover?` instead of `include?` | 5 | Range optimization |
| `Array#sample` instead of `shuffle.first` | 5 | O(1) vs O(n) |
| `reverse_each` instead of `reverse.each` | 4 | Avoids array copy |
| `flat_map` instead of `map.flatten(1)` | 4 | Single pass |
| `detect` instead of `select.first` | 3 | Short-circuits |

**Note**: Most of these are in test/ and benchmarks/. Only the lib/ ones matter for runtime performance.

---

## Priority 6: Skunk StinkScore (Worst Files)

Files ranked by StinkScore (complexity x churn / coverage):

| File | StinkScore | Coverage | Issue |
|------|-----------|----------|-------|
| `lib/redis/pipeline.rb` | **1,459** | 88.1% | Massive duplication + low coverage |
| `lib/redis_ruby/pooled_client.rb` | **303** | 87.9% | Duplication with async_pooled |
| `lib/redis_ruby/async_pooled_client.rb` | **302** | 87.6% | Duplication with pooled |
| `lib/redis_ruby/async_client.rb` | **277** | 88.5% | Shared code with sentinel |
| `lib/redis_ruby/commands/pubsub.rb` | **273** | 72.2% | **Lowest coverage** |
| `lib/redis_ruby/protocol/resp3_encoder.rb` | **142** | 96.3% | Highest complexity |
| `lib/redis_ruby/commands/hashes.rb` | **136** | 93.6% | Duplication in iter methods |
| `lib/redis_ruby/subscriber.rb` | **125** | 79.5% | Low coverage |
| `lib/redis_ruby/connection/ssl.rb` | **69** | 83.2% | Below 85% coverage |
| `lib/redis_ruby/cluster_client.rb` | **68** | 95.5% | High complexity |

**Action**: Focus on these 10 files for maximum quality improvement.

---

## Recommended Cleanup Order

### Phase 1: Auto-fix (~8,347 issues, ~5 minutes)
```bash
bundle exec rubocop -A
```
This clears all style/formatting issues across the entire codebase.

### Phase 2: Production lint (12 issues, ~1 hour)
- Audit `Security/Eval` usage
- Fix `Lint/DuplicateBranch` (5 places)
- Fix `Lint/EmptyConditionalBody` (2 places)
- Fix remaining lint warnings

### Phase 3: Pipeline.rb deduplication (~1,459 StinkScore, ~2 hours)
- `lib/redis/pipeline.rb` has 6+ duplication clusters
- Extract shared method implementations
- This single file accounts for the highest StinkScore in the project

### Phase 4: Client type deduplication (~880 StinkScore, ~2 hours)
- Extract `BaseClient` module for shared methods across:
  - `pooled_client.rb`
  - `async_pooled_client.rb`
  - `async_client.rb`
  - `sentinel_client.rb`

### Phase 5: Complexity reduction (~126 offenses, ~4 hours)
- Decompose `RESP3Encoder#encode_pipeline` (flog 141.9)
- Decompose `RESP3Encoder#encode_command` (flog 96.1)
- Simplify `Redis#normalize_options` (flog 64.0)
- Decompose `ClusterClient#execute_with_retry` (flog 34.0)

### Phase 6: Command module DRY-up (~228 mass, ~3 hours)
- Extract shared command argument builders
- DRY `time_series.rb` conditional blocks
- DRY `geo.rb` option handling
- DRY `sorted_sets.rb` score parsing

### Phase 7: Coverage gaps (~3 hours)
- `commands/pubsub.rb`: 72.2% -> 85%+
- `subscriber.rb`: 79.5% -> 85%+
- `connection/ssl.rb`: 83.2% -> 85%+
- `pooled_client.rb`: 87.9% -> 90%+
- `async_pooled_client.rb`: 87.6% -> 90%+
- `async_client.rb`: 88.5% -> 90%+
- `pipeline.rb`: 88.1% -> 90%+

### Phase 8: Performance fixes (lib/ only, ~1 hour)
- `Hash#fetch` with block instead of default argument
- `yield` instead of `block.call`
- `attr_reader`/`attr_writer` for ivar access
- `Hash#each_key` instead of `Hash#keys.each`

---

## Tool Configs to Add

### `.reek.yml` (suppress intentional smells)
```yaml
detectors:
  BooleanParameter:
    exclude:
      - RedisRuby::Commands  # Redis API requires boolean params (NX, EX, etc.)
  UncommunicativeVariableName:
    accept:
      - k  # Hash key
      - v  # Hash value
      - n  # Count
      - i  # Index
      - e  # Exception
```

### `.fasterer.yml` (disable inapplicable rules)
```yaml
speedups:
  each_with_index_vs_while: false  # Readability > micro-optimization
  for_loop_vs_each: false          # Already using each everywhere
  module_eval_vs_define_method: false  # Not applicable
```

---

## Metrics After Full Cleanup (Projected)

| Metric | Current | Target |
|--------|---------|--------|
| RuboCop offenses | 9,052 | < 100 |
| RuboCop lib/ offenses | 157 | 0 |
| Reek smells | 1,557 | < 500 |
| Flay mass | 8,010 | < 2,000 |
| RubyCritic Score | 41.65 | > 75 |
| Skunk Total | 3,745 | < 1,000 |
| Test Coverage | 96.1% | > 96% |
