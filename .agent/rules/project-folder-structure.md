---
trigger: always_on
---

# Project Folder Structure Rules

## Overview
These rules are derived from `docs/Project_Folder_Structure_Blueprint.md` and define the authoritative directory layout for the project.

## 1. Directory Purpose & Placement
**Rule**: All file creations must adhere to these placement standards:
- **Executables**: `bin/`. Must be executable.
- **Core Infrastructure**: `lib/core/`. Low-level shell logic only.
- **Business Logic**: `lib/modules/`. High-level features.
- **Python Code**: `lib/utils/`. Complex logic, data models, or helpers.
- **Data Schemas**: `lib/models/`. JSON schemas only.
- **Configuration**: `config/`.
- **Documentation**: `docs/`.

## 2. Naming Conventions
**Rule**: Follow these naming formats strictly:
- **Shell Scripts**: `kebab-case.sh`
- **Python Scripts**: `kebab-case.py`
- **Directories**: `kebab-case`
- **Functions**: `module_name_verb` (e.g., `desktop_env_install`)

## 3. Technology Constraints
**Rule**:
- `lib/core` and `lib/modules` are **Shell (Bash)** domains.
- `lib/utils` is the **Python** domain.
- Do not mix Shell logic into Python directories or vice versa unless wrapping a subprocess.

## 4. New Module Template
**Rule**: New modules in `lib/modules/` MUST start with:
```bash
#!/usr/bin/env bash
# @description Module for [Feature Name]
# @author [Author Name]

# shellcheck source=lib/core/logger.sh
source "${PROJECT_ROOT}/lib/core/logger.sh"
```

## 5. New Utility Template
**Rule**: New utilities in `lib/utils/` MUST start with:
```python
#!/usr/bin/env python3
"""
[Utility Name] - [Description]
"""
import sys
import logging
```
