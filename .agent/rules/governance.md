# Technical Governance

## Overview
This document defines how technical decisions are made, documented, and amended for the VPS-Setup project. It ensures consistent, well-reasoned choices that align with project goals.

---

## Decision Authority

### Decision Levels
| Level | Scope | Authority | Process |
|-------|-------|-----------|---------|
| **L1 - Trivial** | Variable names, comment fixes | Any contributor | Direct commit |
| **L2 - Standard** | New functions, bug fixes | PR author + 1 reviewer | Standard PR review |
| **L3 - Significant** | New modules, API changes | 2 reviewers + domain expert | RFC discussion |
| **L4 - Architectural** | Framework choice, major refactor | Team consensus + lead | Full RFC process |

---

## Request for Comments (RFC)

### When Required
- New provisioning phase or module
- Changes to CLI interface (flags, output format)
- Dependency additions or upgrades
- Cross-module architectural changes
- Changes affecting idempotency or rollback

### RFC Template
```markdown
# RFC: [Title]

## Status
Draft | In Review | Approved | Rejected | Superseded

## Context
What problem does this solve? Why now?

## Proposal
Technical description of the change.

## Alternatives Considered
What other approaches were evaluated?

## Impact
- Breaking changes: [yes/no]
- Performance impact: [description]
- Security implications: [description]
- Testing requirements: [description]

## Rollback Plan
How to revert if issues arise.

## Timeline
Proposed implementation schedule.
```

### RFC Process
1. **Draft**: Author creates RFC in `docs/rfcs/YYYY-MM-DD-title.md`
2. **Review**: Post in team channel, 3 business day comment period
3. **Discussion**: Address feedback, schedule sync if needed
4. **Decision**: Approve / Reject / Request Changes
5. **Implementation**: Link RFC to implementation tasks

---

## Architecture Decision Records (ADR)

### When Required
- Language or framework selections
- External service integrations
- Database/storage choices
- Authentication mechanisms
- Significant library dependencies

### ADR Template
```markdown
# ADR-NNN: [Title]

## Status
Proposed | Accepted | Deprecated | Superseded

## Context
What is the situation? What factors influenced this decision?

## Decision
What is the decision and its rationale?

## Consequences
### Positive
- [benefit 1]

### Negative
- [tradeoff 1]

### Neutral
- [observation 1]

## Related
- [Link to related ADRs, RFCs, or specs]
```

### Storage
ADRs are stored in `docs/architecture/` with sequential numbering.

---

## Module Ownership

### Responsibility Model
Each module in `lib/` has an implicit owner based on primary contributor:

| Directory | Scope |
|-----------|-------|
| `lib/core/` | Infrastructure: logging, config, validation |
| `lib/modules/` | Feature: desktop, rdp, ide installations |
| `lib/models/` | Data structures and schemas |
| `lib/utils/` | Utility scripts (Python helpers) |

### Ownership Responsibilities
1. Review PRs touching owned modules
2. Maintain documentation
3. Ensure test coverage
4. Respond to issues within 48 hours

---

## Dependency Management

### Adding Dependencies
| Type | Process |
|------|---------|
| System package (apt) | Document in `requirements.txt`, RFC if heavy |
| Python library | Add to `requirements.txt`, justify in PR |
| External script | Copy to vendor/ with license, RFC required |
| Shell library | Prefer inline or vendor, RFC required |

### Dependency Criteria
- [ ] Actively maintained (commit in last 6 months)
- [ ] Appropriate license (MIT, Apache 2.0, BSD preferred)
- [ ] No transitive dependency explosion
- [ ] Clear security track record
- [ ] Documented usage in codebase

---

## Code Review Requirements

### Review Matrix
| Change Type | Required Reviewers |
|-------------|-------------------|
| Bug fix | 1 reviewer |
| New feature | 2 reviewers |
| Security-related | Security-conscious reviewer |
| Architecture | Domain expert + 1 |
| Hotfix | 1 senior + async post-review |

### Review SLA
| Priority | Initial Review | To Merge |
|----------|----------------|----------|
| Critical | 4 hours | 8 hours |
| High | 8 hours | 24 hours |
| Normal | 24 hours | 72 hours |
| Low | 72 hours | 1 week |

---

## Amendment Process

### Changing These Rules
1. **Propose**: Create PR with rule changes
2. **Justify**: Document reason for change with evidence
3. **Review**: Minimum 2 reviewers, 3-day comment period
4. **Consensus**: No objections or majority approval
5. **Merge**: Update version and date

### Version Semantics
- **Major**: Fundamental principle changes
- **Minor**: New sections or significant clarifications
- **Patch**: Typos, formatting, minor clarifications

---

## Conflict Resolution

### Escalation Path
1. **Discussion**: Resolve in PR/RFC comments
2. **Sync Meeting**: Schedule call if async fails
3. **Tech Lead**: Escalate unresolved after 48 hours
4. **Team Vote**: Final resort, majority wins

### Default Behavior
If consensus cannot be reached within 5 days:
- Conservative approach wins (less change)
- Document disagreement in decision record
- Set review date for revisiting

---

## Compliance

### Self-Assessment
All PRs should verify:
- [ ] Follows code quality standards
- [ ] Includes appropriate tests
- [ ] Documentation updated
- [ ] No rule violations

### Periodic Review
- **Monthly**: Review open RFCs status
- **Quarterly**: Audit rule compliance
- **Annually**: Comprehensive rule review

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-12-24 | Initial governance document |
