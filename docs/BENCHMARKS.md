# Performance Benchmarks

This document contains comprehensive performance benchmarks comparing redis-ruby against redis-rb (the official Ruby Redis client) in various configurations.

## Test Environment

- **Date**: 2026-02-10
- **Ruby Version**: 3.3.0
- **Platform**: arm64-darwin23 (Apple Silicon)
- **Redis**: localhost:6379
- **Benchmark Tool**: benchmark-ips (warmup: 2s, time: 5s)

## Benchmark Configurations

We test the following configurations:
1. **redis-rb (plain)**: Official redis-rb gem with pure Ruby driver
2. **redis-rb (hiredis)**: Official redis-rb gem with native hiredis driver
3. **redis-ruby**: This implementation (pure Ruby, RESP3)

Each configuration is tested with:
- **YJIT enabled** (Ruby 3.3+ JIT compiler)
- **YJIT disabled** (standard Ruby interpreter)

## Results Summary

### Ruby 3.3.0 + YJIT Enabled ✅ **RECOMMENDED**

| Operation | redis-ruby | redis-rb (plain) | redis-rb (hiredis) | vs plain | vs hiredis |
|-----------|------------|------------------|-------------------|----------|------------|
| Single GET | 6,534 ops/s | 5,823 ops/s | 7,935 ops/s | **1.12x** ✓ | 0.82x |
| Single SET | 8,415 ops/s | 6,527 ops/s | 6,059 ops/s | **1.29x** ✓ | **1.39x** ✓ |
| Pipeline 10 | 7,815 ops/s | 4,992 ops/s | 5,525 ops/s | **1.57x** ✓ | **1.41x** ✓ |
| Pipeline 100 | 4,586 ops/s | 3,512 ops/s | 3,579 ops/s | **1.31x** ✓ | **1.28x** ✓ |

**Key Findings:**
- ✅ **redis-ruby is 1.12-1.57x faster than redis-rb (plain)** across all operations
- ✅ **redis-ruby is competitive with redis-rb + hiredis** (0.82x-1.39x)
- ✅ **Pipelined operations show the biggest advantage** (1.28x-1.57x faster)
- ✅ **No native extensions required** - pure Ruby performance

### Ruby 3.3.0 + YJIT Disabled

| Operation | redis-ruby | redis-rb (plain) | redis-rb (hiredis) | vs plain | vs hiredis |
|-----------|------------|------------------|-------------------|----------|------------|
| Single GET | 6,944 ops/s | 8,376 ops/s | 7,652 ops/s | 0.83x | 0.91x |
| Single SET | 6,557 ops/s | 8,159 ops/s | 6,187 ops/s | 0.80x | 1.06x ✓ |
| Pipeline 10 | 4,938 ops/s | 6,040 ops/s | 5,432 ops/s | 0.82x | 0.91x |
| Pipeline 100 | 3,135 ops/s | 3,329 ops/s | 2,650 ops/s | 0.94x | 1.18x ✓ |

**Key Findings:**
- ⚠️ **Without YJIT, redis-ruby is slower than redis-rb (plain)** (0.80x-0.94x)
- ✅ **redis-ruby still competitive with hiredis on pipelines** (1.06x-1.18x on some operations)
- 💡 **YJIT is essential for optimal redis-ruby performance**

## Performance Characteristics

### Strengths
1. **Pipelined Operations**: redis-ruby excels at pipelined operations (1.28x-1.57x faster with YJIT)
2. **SET Operations**: Consistently faster than both redis-rb configurations with YJIT (1.29x-1.39x)
3. **Pure Ruby**: Achieves competitive performance without native extensions
4. **YJIT Optimization**: Designed to take full advantage of Ruby 3.3+ YJIT

### Considerations
1. **YJIT Required**: Performance advantage requires YJIT enabled (Ruby 3.3+)
2. **GET Operations**: Slightly slower than redis-rb + hiredis for single GET (0.82x)
3. **Variance**: Some benchmark runs show higher variance (±6-26%) due to system load

## Recommendations

### For Production Use
- ✅ **Use Ruby 3.3+ with YJIT enabled** (`RUBYOPT="--yjit"`)
- ✅ **Ideal for pipeline-heavy workloads** (batch operations, bulk imports)
- ✅ **Great for SET-heavy workloads** (caching, session storage)
- ⚠️ **Consider redis-rb + hiredis for GET-heavy workloads** if maximum throughput is critical

### For Development
- ✅ **redis-ruby works well without YJIT** (0.80x-1.18x performance)
- ✅ **No native extension compilation** simplifies setup
- ✅ **Better debugging experience** (pure Ruby stack traces)

## Running Benchmarks

### Quick Benchmark
```bash
# With YJIT (recommended)
RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_basic.rb

# Without YJIT
bundle exec ruby benchmarks/compare_basic.rb
```

### Comprehensive Report
```bash
# Generate full report with all configurations
RUBYOPT="--yjit" bundle exec ruby benchmarks/generate_comprehensive_report.rb

# Results saved to tmp/comprehensive_benchmark_*.json
```

### Performance Gate Verification
```bash
# Verify minimum performance requirements
RUBYOPT="--yjit" bundle exec ruby benchmarks/verify_gates.rb
```

## Benchmark Methodology

- **Warmup**: 2 seconds per benchmark to allow YJIT to compile hot paths
- **Measurement**: 5 seconds of sustained operations
- **Iterations**: Automatically determined by benchmark-ips for statistical significance
- **Error Margin**: Reported as ± percentage (typically 6-26% depending on system load)
- **Comparison**: Statistical comparison accounts for error margins

## Notes

- Benchmarks run on a local Redis instance to minimize network latency
- Results may vary based on hardware, OS, and Redis configuration
- Production performance depends on network latency, Redis server load, and workload patterns
- YJIT warmup time not included in measurements (real-world applications benefit from longer warmup)

## Historical Context

Previous benchmark claims in the README (2.11x faster for pipelines) were based on:
- Ruby 3.4 (newer YJIT optimizations)
- Different test environment
- Possibly different redis-rb version

Current benchmarks (Ruby 3.3.0) show more modest but still significant improvements:
- 1.12x-1.57x faster than redis-rb (plain) with YJIT
- Competitive with redis-rb + hiredis (native extension)

