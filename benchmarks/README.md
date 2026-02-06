# Redis-Ruby Benchmarks

Comprehensive benchmark suite for comparing redis-ruby against redis-rb.

## Quick Start

```bash
# Run the comprehensive benchmark suite
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb

# Quick mode (shorter runs)
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --quick

# Run specific suite
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --suite=throughput
RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --suite=latency,pipeline
```

## Benchmark Files

### Primary Benchmarks

| File | Description |
|------|-------------|
| `comprehensive_suite.rb` | **Complete benchmark suite** - Throughput, latency, data sizes, pipelines, transactions, workloads |
| `verify_gates.rb` | CI-friendly gate verification with pass/fail exit codes |
| `generate_report.rb` | Generate HTML and JSON reports |
| `memory_comparison.rb` | Memory allocation comparison |

### Specialized Benchmarks

| File | Description |
|------|-------------|
| `compare_basic.rb` | Basic operations (PING, GET, SET, EXISTS, DEL) |
| `compare_comprehensive.rb` | Performance gate verification |
| `compare_vs_hiredis.rb` | Comparison against hiredis driver |
| `protocol_comparison.rb` | RESP3 protocol encoding/decoding |
| `command_optimizations.rb` | Individual command benchmarks |

### Profiling Tools

| File | Description |
|------|-------------|
| `deep_profile.rb` | Memory, CPU, GC, and YJIT profiling |
| `profile_hotspots.rb` | CPU hotspot identification |
| `simple_profile.rb` | Quick profiling |

## Performance Gates

From `CLAUDE.md`, redis-ruby must meet these minimum performance requirements:

| Metric | Minimum Gate |
|--------|-------------|
| Single GET/SET | 1.3x faster than redis-rb |
| Pipeline (10 cmds) | 1.5x faster than redis-rb |
| Pipeline (100 cmds) | 2x faster than redis-rb |
| Connection setup | Equal or faster than redis-rb |
| RESP3 Parser | 1.5x faster than redis-rb |

Verify gates with:
```bash
RUBYOPT="--yjit" bundle exec ruby benchmarks/verify_gates.rb
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
