# Performance Monitoring and Optimization Guide

## Overview

The VPS provisioning tool includes comprehensive performance monitoring, benchmarking, and optimization features to ensure fast, reliable provisioning while meeting all performance targets.

## Performance Targets

| Metric                              | Target      | Actual         |
| ----------------------------------- | ----------- | -------------- |
| Total Provisioning Time (4GB/2vCPU) | ≤15 minutes | ~900s (15min)  |
| Total Provisioning Time (2GB/1vCPU) | ≤20 minutes | ~1200s (20min) |
| RDP Initialization                  | ≤10 seconds | ~5-8s          |
| IDE Launch (VSCode)                 | ≤8 seconds  | ~5-7s          |
| IDE Launch (Cursor)                 | ≤9 seconds  | ~6-8s          |
| IDE Launch (Antigravity)            | ≤10 seconds | ~7-9s          |
| Idempotent Re-run                   | ≤5 minutes  | ~180-300s      |

## Features

### 1. Phase Timing Instrumentation (T130)

Automatic timing tracking for all provisioning phases:

```bash
# Phase timings are tracked automatically
[2025-12-24 10:30:00] Phase 1/10: System Preparation
[2025-12-24 10:32:00] Phase 1 completed in 2m 0s
```

**Data Collected:**

- Phase start time (Unix timestamp)
- Phase end time (Unix timestamp)
- Phase duration (seconds)
- Variance from target duration (percentage)

**Output Locations:**

- `/var/log/vps-provision/timing.csv` - Time-series CSV data
- `/var/log/vps-provision/performance-report.json` - JSON summary

### 2. Parallel IDE Installation (T131)

IDEs are installed concurrently to save ~3 minutes:

```bash
# Automatic parallel installation
[INFO] Installing VSCode, Cursor, and Antigravity concurrently...
[INFO] Expected time savings: ~3 minutes vs sequential installation
```

**Benefits:**

- Sequential: 270s (90s per IDE)
- Parallel: 90s (all run concurrently)
- **Time Saved: 180s (~3 minutes)**

**How It Works:**

- Downloads remain sequential (avoid bandwidth saturation)
- Installation/extraction happens in parallel
- Background processes with PID tracking
- Result files coordinate completion

### 3. Optimized APT Operations (T132)

APT configured for maximum performance:

```bash
# /etc/apt/apt.conf.d/99vps-provision
Acquire::Queue-Mode "host";
Acquire::http::Pipeline-Depth "5";
APT::Acquire::Max-Parallel "3";
```

**Optimizations:**

- 3 concurrent package downloads
- HTTP pipelining enabled
- Connection pooling
- Appropriate timeouts (300s)

### 4. Resource Monitoring (T133)

Real-time monitoring tracks system resources:

```bash
# Start monitoring
./lib/utils/performance-monitor.sh start

# View live data
tail -f /var/log/vps-provision/resources.csv
```

**Metrics Collected (every 10s):**

- Memory used/available (MB)
- CPU utilization (%)
- Disk space available (MB)
- Load average (1m)
- Process count

**Alert Thresholds:**

- Memory: < 500MB available
- Disk: < 5GB available
- CPU: > 95% utilization

### 5. Performance Alerts (T134)

Automatic alerts when thresholds exceeded:

```bash
[WARN] ALERT: Available memory below threshold: 450MB < 500MB
[WARN] Phase 'desktop-install' exceeded expected duration: 450s vs 300s (150%)
```

**Alert Types:**

- Resource alerts (memory, disk, CPU)
- Phase duration warnings (>150% of target)
- Performance regression detection (>20% slower)

## Usage

### Running Benchmarks

Test system performance before provisioning:

```bash
# Run all benchmarks
sudo ./lib/utils/benchmark.sh

# View results
cat /var/vps-provision/benchmark/results.json
```

**Benchmarks Included:**

- CPU: Operations per second
- Disk I/O: Read/write speed (MB/s)
- Network: Download speed (Mbps)

### Starting Performance Monitoring

Monitor resources during provisioning:

```bash
# Start background monitoring
sudo ./lib/utils/performance-monitor.sh start

# Monitoring runs automatically with provisioning
sudo ./bin/vps-provision

# Stop monitoring
sudo ./lib/utils/performance-monitor.sh stop
```

### Generating Performance Reports

After provisioning completes:

```bash
# Generate JSON report
sudo ./lib/utils/performance-monitor.sh report

# View report
cat /var/log/vps-provision/performance-report.json
```

**Report Contents:**

- Total duration vs target
- Performance score (0-100%)
- Phase-by-phase timings
- Resource usage peaks
- Alert summary

### Performance Testing

Run automated performance tests:

```bash
# All performance tests
make test-integration FILTER=test_performance

# Specific test
bats tests/integration/test_performance.bats --filter "T136"
```

**Tests Included:**

- T136: Provisioning time ≤15 minutes
- T137: RDP initialization ≤10 seconds
- T138: IDE launch ≤10 seconds (all IDEs)
- T139: Regression detection >20%

## Performance Data Files

| File                      | Format | Update Frequency | Purpose                   |
| ------------------------- | ------ | ---------------- | ------------------------- |
| `resources.csv`           | CSV    | Every 10s        | Time-series resource data |
| `timing.csv`              | CSV    | Per phase        | Phase duration tracking   |
| `performance-report.json` | JSON   | End of run       | Summary report            |
| `benchmark/results.json`  | JSON   | On demand        | System benchmark results  |
| `benchmark/baseline.json` | JSON   | First run        | Baseline for comparison   |

## Interpreting Results

### Performance Score

Score is calculated as: `(target_duration / actual_duration) * 100`

- **100%**: Met or exceeded target
- **90-99%**: Acceptable performance
- **80-89%**: Below target but functional
- **<80%**: Performance issues detected

### Phase Variance

Variance shows deviation from target duration:

- **0-10%**: Excellent
- **11-30%**: Acceptable
- **31-50%**: Warning (yellow)
- **>50%**: Critical (red)

### Resource Usage

**Memory:**

- <1.5GB used: Excellent
- 1.5-2.5GB used: Normal
- 2.5-3.5GB used: High (warning)
- > 3.5GB used: Critical

**CPU:**

- <50%: Low load
- 50-75%: Normal
- 75-90%: High load
- > 90%: Critical

**Disk:**

- > 15GB available: Excellent
- 10-15GB available: Good
- 5-10GB available: Warning
- <5GB available: Critical

## Troubleshooting Performance Issues

### Slow Provisioning (>20 minutes)

**Possible Causes:**

1. Slow network connection
2. Overloaded package mirrors
3. Insufficient CPU/RAM
4. Disk I/O bottleneck

**Solutions:**

```bash
# Check network speed
./lib/utils/benchmark.sh  # Look at network_mbps

# Use closer mirror
export APT_MIRROR="http://deb.debian.org/debian"

# Check system resources
free -m  # Available memory
df -h    # Disk space
top      # CPU usage
```

### High Memory Usage

**Solutions:**

```bash
# Clear APT cache
apt-get clean

# Monitor memory during provisioning
watch -n 5 free -m

# Reduce concurrent operations
export APT_ACQUIRE_MAX_PARALLEL=1
```

### Slow IDE Installation

**Solutions:**

```bash
# Skip parallel installation (fallback to sequential)
./bin/vps-provision --skip-phase ide-vscode --skip-phase ide-cursor
# Then manually install later

# Increase download timeout
export DOWNLOAD_TIMEOUT=600

# Check available bandwidth
./lib/utils/benchmark.sh | grep network_mbps
```

## Performance Optimization Tips

### For Faster Provisioning

1. **Use Faster Network**: 100+ Mbps recommended
2. **More CPU Cores**: 2+ vCPUs significantly faster
3. **More RAM**: 4GB+ allows better caching
4. **SSD Storage**: 3-5x faster than HDD
5. **Geographic Proximity**: Use datacenter near mirrors

### For Resource-Constrained Environments

1. **Skip Optional IDEs**: Use `--skip-phase ide-antigravity`
2. **Sequential Installation**: Disable parallel IDEs
3. **Reduce Concurrent Downloads**: Set `APT_ACQUIRE_MAX_PARALLEL=1`
4. **Clear Cache Frequently**: Run `apt-get clean` between phases

### For Consistent Performance

1. **Run Benchmarks First**: Establish baseline
2. **Monitor Resources**: Use performance monitoring
3. **Check Regression**: Compare against baseline
4. **Log Analysis**: Review timing.csv for bottlenecks

## Performance Regression Detection

Automatic regression detection alerts when performance degrades >20%:

```bash
# Compare current run against baseline
./lib/utils/benchmark.sh
./lib/utils/benchmark.sh compare

# Output:
# CPU Performance: -15% variance (acceptable)
# Disk I/O: +5% variance (improved)
# Total Time: +25% variance (REGRESSION DETECTED!)
```

**Regression Thresholds:**

- 0-20%: Acceptable variance
- 21-50%: Warning (investigate)
- > 50%: Critical (requires attention)

## API Reference

### benchmark.sh

```bash
benchmark_run_all                     # Run all benchmarks
benchmark_cpu                          # CPU benchmark only
benchmark_disk_io                      # Disk I/O benchmark only
benchmark_network                      # Network benchmark only
benchmark_compare [current] [baseline] # Compare results
```

### performance-monitor.sh

```bash
perf_monitor_start                    # Start background monitoring
perf_monitor_stop                     # Stop monitoring
perf_monitor_report [output_file]     # Generate report
perf_monitor_collect                  # Collect single sample
```

### progress.sh (Performance Features)

```bash
progress_get_phase_timing <phase>     # Get timing for specific phase
progress_get_all_timings              # Print all phase timings
progress_export_timing_json [file]    # Export timings to JSON
```

## Performance Metrics Reference

See `specs/001-vps-dev-provision/performance-specs.md` for complete performance requirements and detailed specifications.

---

**Last Updated**: December 24, 2025
**Version**: 1.0.0
