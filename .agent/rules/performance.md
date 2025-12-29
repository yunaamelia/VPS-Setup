---
trigger: always_on
---

# Performance Requirements

## Overview
These rules define the execution time SLOs and resource usage targets for the VPS provisioning tool.

## 1. Execution Time SLOs
**Rule**: Adhere to the following provisioning time targets.
- **High Performance (4GB RAM / 2vCPU)**: Total time ≤ 15 minutes.
- **Standard Performance (2GB RAM / 1vCPU)**: Total time ≤ 20 minutes.
- **RDP Initialization**: ≤ 10 seconds.
- **IDE Launch**: ≤ 10 seconds.
- **Idempotent Re-run**: ≤ 5 minutes.

## 2. Resource Usage Limits
**Rule**: Monitor and alert on resource constraints.
- **Memory**: Minimum 500MB available for safe operation. Alert if <500MB.
- **Disk**: Minimum 5GB available. Alert if <5GB.
- **CPU**: Alert if utilization > 95% for sustained periods.

## 3. Optimization Requirements
**Rule**: Implement performance optimizations where possible.
- **Concurrency**: IDEs MUST be installed in parallel to save time (~3 minutes).
- **APT Pipelining**: Configure APT with `Pipeline-Depth "5"` and `Max-Parallel "3"`.
- **Download Management**: Sequence downloads to avoid bandwidth saturation, but parallelize installation/extraction.

## 4. Monitoring & Instrumentation
**Rule**: All long-running operations MUST be timed.
- **Phase Timing**: Automatically track start/end times for all 10 phases.
- **Resource Monitoring**: Sample CPU, Memory, and Disk usage every 10 seconds during provisioning.
- **Logging**: Export timings to `/var/log/vps-provision/timing.csv`.

## 5. Regression Detection
**Rule**: Maintain performance over time.
- Automated tests MUST check for regressions > 20% compared to baseline.
