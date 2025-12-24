# Performance Requirements

## Overview
These requirements define Service Level Objectives (SLOs) for the VPS-Setup provisioning tool. All implementations must meet these performance standards.

---

## Execution Time SLOs

### Provisioning Phases
| Phase | Target Time | Maximum | Enforcement |
|-------|-------------|---------|-------------|
| System Preparation | ≤3 min | 5 min | CI benchmark |
| Desktop Installation | ≤5 min | 8 min | CI benchmark |
| RDP Server Setup | ≤2 min | 4 min | CI benchmark |
| IDE Installation (each) | ≤3 min | 5 min | CI benchmark |
| User Provisioning | ≤1 min | 2 min | CI benchmark |
| **Total Provisioning** | **≤15 min** | **20 min** | **Hard limit** |

### CLI Operations
| Operation | Target | Maximum |
|-----------|--------|---------|
| `--help` display | <100ms | 500ms |
| `--version` display | <50ms | 200ms |
| `--verify` check | <30s | 60s |
| Checkpoint resume | <10s | 30s |

---

## Resource Usage Limits

### Memory
| Metric | Limit |
|--------|-------|
| Peak RSS (provisioning) | ≤256 MB |
| Idle memory (monitoring) | ≤32 MB |
| Temp file usage | ≤500 MB |

### Disk
| Metric | Requirement |
|--------|-------------|
| Minimum free space check | 10 GB |
| Log rotation | Max 100 MB total |
| Checkpoint storage | Max 50 MB |

### Network
| Metric | Limit |
|--------|-------|
| Parallel connections | ≤10 concurrent |
| Download timeout | 30s per request |
| Retry attempts | 3 with exponential backoff |
| Total bandwidth | No artificial limits |

---

## Idempotency Requirements

### All Operations Must Be
1. **Repeatable**: Running twice produces same result
2. **Resumable**: Continue from any failure point
3. **Non-destructive**: Don't overwrite user customizations

### Implementation Pattern
```bash
# Check before action
if checkpoint_completed "phase_name"; then
  logger_info "Phase already completed, skipping"
  return 0
fi

# Perform action
do_phase_work

# Mark complete
checkpoint_save "phase_name"
```

---

## Rollback Capability

### Requirements
| Aspect | Requirement |
|--------|-------------|
| Rollback time | ≤5 minutes |
| State tracking | All changes logged |
| Partial rollback | Per-phase granularity |
| User data | Never deleted during rollback |

### Rollback Strategy
```bash
# Priority order for rollback
1. Stop running services
2. Remove installed packages
3. Restore configuration files (from backup)
4. Clean temporary files
5. Reset checkpoints
```

---

## Network Operation Standards

### Timeouts
| Operation | Connect | Read | Total |
|-----------|---------|------|-------|
| Package download | 10s | 30s | 300s |
| Repository update | 10s | 60s | 180s |
| Health check | 5s | 10s | 15s |

### Retry Policy
```bash
MAX_RETRIES=3
INITIAL_BACKOFF=5  # seconds

for attempt in $(seq 1 "$MAX_RETRIES"); do
  if try_operation; then
    break
  fi
  sleep $((INITIAL_BACKOFF * attempt))
done
```

### Offline Handling
- Detect offline state before network operations
- Provide clear error message with suggestions
- Cache apt package lists when possible

---

## Concurrency Standards

### Parallel Operations
| Operation | Allowed Concurrency |
|-----------|---------------------|
| Package downloads | 5 parallel |
| File operations | 10 parallel |
| Service checks | 3 parallel |
| RDP sessions | 3 concurrent users |

### Resource Locking
```bash
# Use lockfiles for shared resources
LOCK_FILE="/var/lock/vps-provision.lock"

acquire_lock() {
  exec 200>"$LOCK_FILE"
  flock -n 200 || {
    logger_error "Another provisioning process is running"
    return 1
  }
}
```

---

## Monitoring and Observability

### Required Metrics
- Total provisioning time
- Per-phase execution time
- Retry count per operation
- Disk usage before/after
- Memory peak usage

### Log Performance Events
```bash
# Log timing for performance-critical operations
logger_debug "Starting desktop installation at $(date +%s)"
# ... operation ...
logger_debug "Desktop installation completed in ${elapsed}s"
```

---

## Performance Testing

### CI Requirements
```bash
# Run performance benchmarks
make benchmark

# Fail CI if thresholds exceeded
- Provisioning > 20 minutes: FAIL
- Memory peak > 256MB: WARN
- Any phase > 2x target: FAIL
```

### Local Profiling
```bash
# Time execution
time ./bin/vps-provision --dry-run

# Memory profiling
/usr/bin/time -v ./bin/vps-provision
```

---

## Review Checklist

- [ ] Operation completes within time SLO
- [ ] Memory usage under limit
- [ ] Proper timeout handling
- [ ] Retry logic with backoff
- [ ] Idempotent implementation
- [ ] Rollback capability present
- [ ] Concurrency limits respected
- [ ] Performance logged for monitoring
