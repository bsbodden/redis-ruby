# Redis-Ruby Benchmarking Framework

A comprehensive performance evaluation framework for redis-ruby, designed to be run with a single command and inspired by best practices from Lettuce (gold standard), Jedis JMH patterns, and redis-py benchmarks.

## Quick Start

```bash
# Run all benchmarks with YJIT enabled
bundle exec rake benchmark

# Run specific benchmark categories
bundle exec rake benchmark:micro       # Basic operations (PING, GET, SET)
bundle exec rake benchmark:integration # Pipelines, mixed workloads
bundle exec rake benchmark:gates       # Verify performance gates (CI/CD)

# Generate reports
bundle exec rake benchmark:report      # JSON + HTML reports
```

## Performance Gates

From `CLAUDE.md`, these are the **minimum performance requirements** that redis-ruby must meet:

| Benchmark | Minimum Speedup | Description |
|-----------|-----------------|-------------|
| Single GET | **1.3x** faster | Basic GET operation |
| Single SET | **1.3x** faster | Basic SET operation |
| Pipeline 10 | **1.5x** faster | 10-command pipeline |
| Pipeline 100 | **2.0x** faster | 100-command pipeline |
| Connection Setup | **1.0x** (equal or faster) | Connection overhead |

### Verifying Gates (CI/CD Integration)

```bash
# Returns exit code 0 if all gates pass, 1 if any fail
bundle exec rake benchmark:gates

# In CI/CD pipeline (GitHub Actions example):
- name: Verify Performance Gates
  run: RUBYOPT="--yjit" bundle exec rake benchmark:gates
```

## Available Rake Tasks

### Core Benchmarks

| Task | Description |
|------|-------------|
| `benchmark:all` | Run all benchmarks (micro + integration + gates) |
| `benchmark:micro` | Basic operations: PING, GET, SET, EXISTS, DEL |
| `benchmark:integration` | Pipelines, mixed workloads, connection setup |
| `benchmark:resp3` | RESP3 protocol parsing (isolated) |
| `benchmark:async` | Fiber-based async client |
| `benchmark:hiredis` | Direct comparison with hiredis |

### Performance Gates

| Task | Description |
|------|-------------|
| `benchmark:gates` | Verify all performance gates (CI/CD compatible) |
| `benchmark:quick` | Fast feedback (reduced warmup/iterations) |

### Profiling

| Task | Description |
|------|-------------|
| `benchmark:profile_cpu` | CPU profiling with StackProf |
| `benchmark:profile_memory` | Memory allocation profiling |
| `benchmark:profile_vernier` | Modern YJIT-aware profiling with Vernier |

### Reports

| Task | Description |
|------|-------------|
| `benchmark:report` | Generate both JSON and HTML reports |
| `benchmark:report_json` | JSON report (for CI/CD integration) |
| `benchmark:report_html` | HTML report with charts |

### YJIT Comparison

| Task | Description |
|------|-------------|
| `benchmark:yjit` | Run with YJIT explicitly enabled |
| `benchmark:no_yjit` | Run without YJIT (baseline) |
| `benchmark:yjit_comparison` | Side-by-side comparison |

## Benchmark Configuration

Default settings (based on benchmark-ips best practices):

| Setting | Value | Rationale |
|---------|-------|-----------|
| Warmup | 2 seconds | Allows YJIT compilation and CPU stabilization |
| Measurement | 5 seconds | Produces statistically significant results |

For quick feedback during development:
```bash
BENCHMARK_QUICK=1 bundle exec rake benchmark:micro
```

## Report Formats

### JSON Report (CI/CD Integration)

```json
{
  "metadata": {
    "timestamp": "2026-01-22T12:00:00Z",
    "ruby_version": "3.4.1",
    "yjit_enabled": true
  },
  "results": {
    "Single GET": {
      "redis_rb": { "ips": 15000.5, "stddev": 150.2 },
      "redis_ruby": { "ips": 19500.8, "stddev": 180.1 },
      "speedup": 1.3,
      "passed": true
    }
  },
  "summary": {
    "all_gates_passed": true,
    "average_speedup": 1.45
  }
}
```

### HTML Report

Interactive report with:
- Performance gate summary cards
- Speedup comparison bar chart
- IPS (iterations per second) comparison
- Detailed results table

Generated at: `tmp/benchmark_report.html`

## Profiling Workflow

### 1. Identify CPU Hotspots

```bash
bundle exec rake benchmark:profile_cpu

# View flamegraph
bundle exec stackprof --flamegraph tmp/stackprof_*.json > tmp/flamegraph.html
open tmp/flamegraph.html
```

### 2. Memory Profiling

```bash
bundle exec rake benchmark:profile_memory

# Results saved to tmp/memory_profile.txt
cat tmp/memory_profile.txt
```

### 3. Modern Profiling (YJIT-aware)

```bash
bundle exec rake benchmark:profile_vernier

# View at https://vernier.prof/ or:
vernier view tmp/vernier_*.json
```

## Architecture

```
benchmarks/
├── lib/
│   └── benchmark_suite.rb    # Core infrastructure
├── compare_basic.rb          # Basic operations benchmark
├── compare_comprehensive.rb  # Full benchmark suite
├── compare_resp3_parser.rb   # Protocol parsing
├── compare_async.rb          # Async client
├── compare_vs_hiredis.rb     # hiredis comparison
├── verify_gates.rb           # Performance gate verification
├── generate_report.rb        # Report generator
└── profile_hotspots.rb       # Profiling utilities
```

## Methodology

### Statistical Validity

Following benchmark-ips best practices:
- **Warmup period**: Allows JIT compilation and memory stabilization
- **Measurement period**: Long enough for statistical significance
- **Comparison**: Direct redis-rb vs redis-ruby comparison
- **Standard deviation**: Reported for all measurements

### What We Measure

1. **Throughput (IPS)**: Operations per second
2. **Speedup Ratio**: redis-ruby IPS / redis-rb IPS
3. **Memory Allocations**: Objects allocated per operation
4. **CPU Time**: Via sampling profilers

### Fair Comparison Principles

- Same Redis server for both clients
- Same test data and workload
- Same warmup procedures
- YJIT enabled for both (when comparing)
- Connection reuse patterns matched

## Learnings from Other Redis Clients

### Lettuce (Gold Standard)
- JMH-based benchmarking with proper statistical rigor
- Tests sync, async, and reactive modes
- Documents 5-8x speedup with batch/flush optimization
- Single shared connection often outperforms pooling

### Jedis
- Connection pool tuning is critical (maxTotal = maxIdle)
- Pipeline sweet spot: 100-1,000 commands
- Context switches are expensive; reduce concurrent threads

### redis-py
- hiredis provides 10-80x speedup for large collections
- Async excels at concurrent I/O, not isolated operations
- Socket buffer configuration impacts large payload performance

### redis-rb/redis-client
- Pure Ruby can match hiredis with YJIT
- Largest gains in large list/hash parsing
- Pipeline improvements scale with batch size

## Performance Optimization Techniques

Based on research across Redis client libraries:

### High Impact
1. **Non-backtracking RESP3 parser** - State machine design
2. **Buffer pre-allocation** - Know sizes before reading
3. **Connection pooling** - Eliminate per-request overhead
4. **Pipeline batching** - 100-1000 commands optimal

### Medium Impact
5. **TCP_NODELAY** - Disable Nagle's algorithm
6. **Zero-copy parsing** - Use byte slices
7. **String freezing** - Reduce allocations

### For Async
8. **Fiber-based pooling** - Async::Pool integration
9. **Backpressure handling** - Queue when saturated
10. **Persistent connections** - Amortize setup cost

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Performance Benchmarks

on: [push, pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    services:
      redis:
        image: redis:7
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: true

      - name: Verify Performance Gates
        run: RUBYOPT="--yjit" bundle exec rake benchmark:gates
        env:
          REDIS_URL: redis://localhost:6379

      - name: Generate Benchmark Report
        run: RUBYOPT="--yjit" bundle exec rake benchmark:report
        env:
          REDIS_URL: redis://localhost:6379

      - name: Upload Benchmark Report
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-report
          path: |
            tmp/benchmark_report.json
            tmp/benchmark_report.html
```

### Regression Detection

Use [benchmark-action/github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark) for historical tracking:

```yaml
- name: Store Benchmark Result
  uses: benchmark-action/github-action-benchmark@v1
  with:
    name: redis-ruby Performance
    tool: 'customBiggerIsBetter'
    output-file-path: tmp/benchmark_report.json
    github-token: ${{ secrets.GITHUB_TOKEN }}
    auto-push: true
    alert-threshold: '150%'
    comment-on-alert: true
    fail-on-alert: true
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379` | Redis server URL |
| `BENCHMARK_QUICK` | unset | Enable quick mode (shorter warmup/measurement) |
| `RUBYOPT` | - | Ruby options (e.g., `--yjit`) |

## Troubleshooting

### "Connection refused" errors
```bash
# Ensure Redis is running
docker run -d -p 6379:6379 redis:7

# Or use devcontainer Redis
REDIS_URL=redis://redis:6379 bundle exec rake benchmark:micro
```

### Inconsistent results
- Ensure no other processes are using Redis
- Increase measurement time: modify CONFIG in benchmark files
- Run multiple times and compare

### Low speedup numbers
- Verify YJIT is enabled: `ruby --yjit -e "p RubyVM::YJIT.enabled?"`
- Profile to identify bottlenecks: `bundle exec rake benchmark:profile_cpu`
- Check for network latency if using remote Redis

## Contributing

When adding new benchmarks:

1. Use the `BenchmarkSuite` infrastructure in `lib/benchmark_suite.rb`
2. Follow the naming convention: `compare_*.rb` for comparisons
3. Add corresponding rake task in `Rakefile`
4. Document in this file
5. Add performance gate if applicable

## References

- [benchmark-ips](https://github.com/evanphx/benchmark-ips) - Ruby benchmarking
- [Lettuce Benchmarks](https://github.com/lettuce-io/lettuce-core/wiki/Pipelining-and-command-flushing)
- [Jedis Performance Guide](https://redis.io/docs/latest/develop/clients/jedis/)
- [redis-py Benchmarks](https://github.com/redis/redis-py/tree/master/benchmarks)
- [Jamie Gaskins' Pure Ruby vs Hiredis Benchmarks](https://gist.github.com/jgaskins/ecc0fc90d78cdec63c31e0ce5544faa1)
