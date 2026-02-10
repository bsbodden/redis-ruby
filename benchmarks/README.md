# Redis-Ruby Benchmarks

Comprehensive benchmark suite for comparing redis-ruby against redis-rb.

## Quick Start

```bash
# Generate comprehensive performance report (recommended)
RUBYOPT="--yjit" bundle exec ruby benchmarks/generate_comprehensive_report.rb

# Run the comprehensive benchmark suite
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb

# Quick mode (shorter runs)
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --quick

# Run specific suite
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --suite=throughput
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --suite=latency,pipeline
```

## Directory Structure

```
benchmarks/
├── README.md                           # This file
├── comprehensive_suite.rb              # Main benchmark suite
├── generate_comprehensive_report.rb    # Generate performance reports
├── generate_report.rb                  # Legacy report generator
├── comparison/                         # Comparison benchmarks
│   ├── compare_async.rb
│   ├── compare_basic.rb
│   ├── compare_comprehensive.rb
│   ├── compare_resp3_parser.rb
│   ├── compare_vs_hiredis.rb
│   ├── get_set_comparison.rb
│   ├── memory_comparison.rb
│   ├── protocol_comparison.rb
│   └── quick_compare.rb
├── profiling/                          # Profiling and analysis tools
│   ├── analyze_io_pattern.rb
│   ├── deep_profile.rb
│   ├── profile_get.rb
│   ├── profile_get_detailed.rb
│   ├── profile_hotspots.rb
│   ├── profile_set.rb
│   ├── simple_profile.rb
│   ├── test_flush.rb
│   └── trace_reads.rb
└── development/                        # Development and optimization tools
    ├── command_optimizations.rb
    ├── encoder_commands_micro.rb
    ├── encoder_micro.rb
    └── verify_gates.rb
```

## Primary Benchmarks

| File | Description |
|------|-------------|
| `comprehensive_suite.rb` | **Complete benchmark suite** - Throughput, latency, data sizes, pipelines, transactions, workloads |
| `generate_comprehensive_report.rb` | **Recommended** - Generate detailed HTML/JSON performance reports comparing redis-ruby vs redis-rb |
| `generate_report.rb` | Legacy report generator |

## Comparison Benchmarks (`comparison/`)

| File | Description |
|------|-------------|
| `compare_basic.rb` | Basic operations (PING, GET, SET, EXISTS, DEL) |
| `compare_comprehensive.rb` | Performance gate verification |
| `compare_vs_hiredis.rb` | Comparison against redis-rb + hiredis (native C extension) |
| `get_set_comparison.rb` | Focused GET/SET performance comparison |
| `memory_comparison.rb` | Memory allocation comparison |
| `protocol_comparison.rb` | RESP3 protocol encoding/decoding |
| `quick_compare.rb` | Quick performance check |

## Profiling Tools (`profiling/`)

| File | Description |
|------|-------------|
| `analyze_io_pattern.rb` | Analyze I/O syscall patterns (reads, writes, flushes) |
| `deep_profile.rb` | Memory, CPU, GC, and YJIT profiling |
| `profile_get.rb` | Profile GET operation performance |
| `profile_get_detailed.rb` | Detailed CPU profiling for GET operations |
| `profile_hotspots.rb` | CPU hotspot identification |
| `profile_set.rb` | Profile SET operation performance |
| `simple_profile.rb` | Quick profiling |
| `trace_reads.rb` | Trace read operations for debugging |

## Development Tools (`development/`)

| File | Description |
|------|-------------|
| `command_optimizations.rb` | Individual command benchmarks |
| `encoder_commands_micro.rb` | Micro-benchmarks for command encoding |
| `encoder_micro.rb` | Micro-benchmarks for RESP3 encoding |
| `verify_gates.rb` | CI-friendly gate verification with pass/fail exit codes |

## Performance Results

**Current Performance (Ruby 3.3.0 + YJIT):**

redis-ruby vs redis-rb + hiredis (native C extension):
- ✅ **Single GET**: 0.99-1.04x (essentially tied!)
- ✅ **Single SET**: 0.96-1.04x (essentially tied!)
- ✅ **Pipeline (10 cmds)**: 1.04-1.05x (4-5% faster)
- ✅ **Pipeline (100 cmds)**: 1.12-1.19x (12-19% faster)

redis-ruby vs redis-rb (plain):
- ✅ **Single GET**: 1.05x (5% faster)
- ✅ **Pipeline (10 cmds)**: 1.05x (5% faster)
- ✅ **Pipeline (100 cmds)**: 1.14x (14% faster)

See [docs/BENCHMARKS.md](../docs/BENCHMARKS.md) for detailed results.

## Performance Gates

Verify performance gates with:
```bash
RUBYOPT="--yjit" bundle exec ruby benchmarks/development/verify_gates.rb
```

## Methodology

### Fair Comparison Principles

1. **Same Environment**: Both libraries run in identical conditions
2. **JIT Warmup**: Adequate warmup before measurement (2+ seconds)
3. **Statistical Significance**: Multiple iterations with comparison
4. **Data Pre-fill**: Realistic data populated before benchmarks
5. **Cleanup**: Proper teardown to avoid cross-test contamination

### Metrics Measured

| Metric | Tool | Description |
|--------|------|-------------|
| Throughput | `Benchmark.ips` | Operations per second |
| Latency P50/P95/P99 | Custom measurer | Percentile response times |
| Memory | `memory_profiler` | Allocations per operation |
| CPU | `stackprof` | Method-level CPU time |

### Best Practices

Based on Redis benchmarking guidelines:

1. **Enable YJIT**: Always run with `RUBYOPT="--yjit"` for production-realistic results
2. **Network Baseline**: Understand local vs network latency impacts
3. **Data Sizes**: Test with realistic data sizes (100B, 1KB, 10KB)
4. **Percentiles**: Focus on P99 latency, not averages
5. **Workload Patterns**: Test read-heavy (10:1), write-heavy (1:10), and mixed

## Output

Reports are saved to `tmp/`:

- `tmp/comprehensive_benchmark.json` - JSON data
- `tmp/comprehensive_benchmark.html` - Visual HTML report
- `tmp/gate_verification.json` - Gate results
- `tmp/memory_comparison.json` - Memory data
- `tmp/profiles/` - Profiling data

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379` | Redis connection URL |
| `BENCHMARK_RUNS` | `3` | Number of statistical runs |
| `BENCHMARK_QUICK` | - | Enable quick mode |
| `ITERATIONS` | `1000` | Memory benchmark iterations |

## Running in CI

```yaml
# Example GitHub Actions
- name: Run Performance Gates
  run: |
    RUBYOPT="--yjit" bundle exec ruby benchmarks/verify_gates.rb
  continue-on-error: false  # Fail if gates don't pass
```

## Interpreting Results

### Throughput (i/s)
- Higher is better
- Speedup > 1.0 means redis-ruby is faster

### Latency (microseconds)
- Lower is better
- Improvement > 0% means redis-ruby has lower latency

### Memory (objects/op)
- Lower is better
- Improvement > 0% means redis-ruby allocates fewer objects

## References

- [Redis Benchmarking Best Practices](https://redis.io/docs/management/optimization/benchmarks/)
- [memtier_benchmark](https://redis.io/blog/memtier_benchmark-a-high-throughput-benchmarking-tool-for-redis-memcached/)
- [Jedis vs Lettuce Comparison](https://redis.io/blog/jedis-vs-lettuce-an-exploration/)
- [AWS Redis Client Optimization](https://aws.amazon.com/blogs/database/optimize-redis-client-performance-for-amazon-elasticache/)
