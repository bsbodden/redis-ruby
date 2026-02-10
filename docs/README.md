# Documentation

This directory contains detailed documentation for redis-ruby development and analysis.

## Performance Documentation

### [BENCHMARKS.md](BENCHMARKS.md)
Comprehensive benchmark results comparing redis-ruby against redis-rb (plain and with hiredis) across different Ruby versions and YJIT configurations. Includes:
- Single operation benchmarks (GET, SET)
- Pipeline benchmarks (10 and 100 commands)
- Performance recommendations
- Instructions for running benchmarks

### [BENCHMARKING.md](BENCHMARKING.md)
Historical benchmarking methodology and earlier performance analysis.

## Development Documentation

### [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)
Original development roadmap and implementation plan for redis-ruby.

### [CODE_QUALITY_REPORT.md](CODE_QUALITY_REPORT.md)
Code quality analysis including:
- Complexity metrics
- Code smells
- Refactoring recommendations
- Test coverage analysis

### [QUALITY_REPORT.md](QUALITY_REPORT.md)
Additional quality metrics and analysis.

## Feature Parity Documentation

### [REDIS_PY_PARITY.md](REDIS_PY_PARITY.md)
Detailed comparison of redis-ruby features against redis-py (Python Redis client), tracking feature parity and implementation status.

### [REDIS_PY_GAP_ANALYSIS.md](REDIS_PY_GAP_ANALYSIS.md)
Gap analysis identifying missing features and differences between redis-ruby and redis-py.

## Testing Documentation

### [MISSING_TESTS_REPORT.md](MISSING_TESTS_REPORT.md)
Analysis of test coverage gaps and recommendations for additional test cases.

## Quick Links

- [Main README](../README.md) - Project overview and getting started
- [Benchmarks Directory](../benchmarks/) - Benchmark scripts and tools
- [Test Directory](../test/) - Test suite

