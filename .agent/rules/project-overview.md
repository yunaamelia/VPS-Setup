---
trigger: always_on
---

# Project Overview Rules

## Overview
These rules are derived from `README.md` and define the high-level goals and architectural principles of the project.

## 1. Project Purpose
**Rule**: The system MUST transform a fresh **Debian 13 (Trixie)** VPS into a fully-functional developer workstation.
- **Target**: Fresh install, minimal dependencies.
- **Outcome**: XFCE4 Desktop, XRDP access, Development Tools (VSCode, Cursor).

## 2. Core Principles
**Rule**: All components must adhere to these three pillars:
1.  **Idempotency**: Safe to re-run multiple times. Skips completed steps.
2.  **Fail-Safe**: "Strict Mode" (`set -euo pipefail`) is mandatory. Failures trigger automatic rollback.
3.  **Modularity**: Logic MUST be isolated in `lib/modules/`. Core logic (`lib/core/`) MUST NOT contain business logic.

## 3. Technology Stack Standards
**Rule**: Adhere to the following versions:
- **OS**: Debian 13
- **Shell**: Bash 5.1+
- **Python**: 3.11+
- **Desktop**: XFCE4 (Performance optimized)
- **Browser**: Firefox ESR

## 4. Architecture Layers
**Rule**: Respect the Four-Layer Architecture:
1.  **CLI Layer** (`bin/`): Entry points and argument parsing.
2.  **Core Layer** (`lib/core/`): Logging, config, infrastructure.
3.  **Module Layer** (`lib/modules/`): Feature implementation.
4.  **Utility Layer** (`lib/utils/`): Python helpers.

## 5. Usage & Configuration
**Rule**:
- **Entry Point**: MUST be `sudo ./bin/vps-provision`.
- **Customization**: Support `--username` argument.
- **Access**: Final output MUST provide credentials for RDP access.
