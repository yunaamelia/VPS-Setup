# GitHub Copilot Tools Directory

## 📁 What's Here

This directory contains **492 GitHub Copilot tools** imported from [github/awesome-copilot](https://github.com/github/awesome-copilot) to supercharge development workflows for the VPS provisioning project.

## 🗂️ Directory Structure

```
.github/
├── README.md                      # This file
├── QUICK_REFERENCE.md            # ⭐ START HERE - Fast access to common tools
├── COPILOT_TOOLS_SUMMARY.md      # 📖 Complete guide with workflows
├── TOOLS_INDEX.md                # 📚 Full catalog organized by category
├── IMPORT_SUMMARY.md             # 📋 Import execution details
├── copilot-instructions.md       # 🎯 Project-specific instructions
│
├── prompts/                       # 137 task-specific automation templates
│   ├── architecture-blueprint-generator.prompt.md
│   ├── breakdown-feature-implementation.prompt.md
│   ├── code-exemplars-blueprint-generator.prompt.md
│   ├── review-and-refactor.prompt.md
│   └── ... (133 more)
│
├── instructions/                  # 152 language/framework guidelines
│   ├── bash.instructions.md
│   ├── python.instructions.md
│   ├── terraform.instructions.md
│   ├── code-review-generic.instructions.md
│   └── ... (148 more)
│
├── agents/                        # 138 specialized AI assistants
│   ├── bash-expert.agent.md
│   ├── terraform-expert.agent.md
│   ├── python-expert.agent.md
│   ├── security-expert.agent.md
│   └── ... (134 more)
│
└── collections/                   # 65 curated tool bundles
    ├── azure-cloud-development.collection.yml
    ├── database-data-management.collection.yml
    ├── devops-oncall.collection.yml
    └── ... (62 more)
```

## 🚀 Quick Start

### 1. First Time? Start Here
```bash
👉 Read: QUICK_REFERENCE.md
```

### 2. Want to Browse All Tools?
```bash
👉 Read: TOOLS_INDEX.md
```

### 3. Need Detailed Workflows?
```bash
👉 Read: COPILOT_TOOLS_SUMMARY.md
```

### 4. Curious About the Import?
```bash
👉 Read: IMPORT_SUMMARY.md
```

## 💡 Common Use Cases

### I want to...

**Plan a new feature**
→ Use `prompts/breakdown-feature-implementation.prompt.md`

**Review code**
→ Use `prompts/review-and-refactor.prompt.md` with `agents/bash-expert.agent.md`

**Write better documentation**
→ Use `prompts/readme-blueprint-generator.prompt.md`

**Improve test coverage**
→ Use `prompts/pytest-coverage.prompt.md`

**Follow Bash best practices**
→ Reference `instructions/bash.instructions.md` (auto-applies when editing .sh files)

**Get Terraform help**
→ Chat with `agents/terraform-expert.agent.md`

**Optimize database queries**
→ Use `prompts/sql-optimization.prompt.md`

**Setup CI/CD**
→ Use `prompts/create-github-action-workflow-specification.prompt.md`

## 🎯 Essential Tools for This Project

### Top 10 Prompts
1. `code-exemplars-blueprint-generator.prompt.md` - Identify coding standards
2. `architecture-blueprint-generator.prompt.md` - Document architecture
3. `breakdown-feature-implementation.prompt.md` - Plan features
4. `review-and-refactor.prompt.md` - Improve code quality
5. `breakdown-test.prompt.md` - Plan testing
6. `readme-blueprint-generator.prompt.md` - Enhance documentation
7. `conventional-commit.prompt.md` - Standardize commits
8. `create-implementation-plan.prompt.md` - Create roadmaps
9. `pytest-coverage.prompt.md` - Analyze test coverage
10. `sql-optimization.prompt.md` - Optimize queries

### Top 10 Instructions
1. `bash.instructions.md` - Shell scripting best practices
2. `python.instructions.md` - Python coding standards
3. `terraform.instructions.md` - Infrastructure as code guidelines
4. `code-review-generic.instructions.md` - General code review
5. `testing-best-practices.instructions.md` - Testing strategies
6. `security-best-practices.instructions.md` - Security guidelines
7. `containerization-docker-best-practices.instructions.md` - Docker standards
8. `github-actions-ci-cd-best-practices.instructions.md` - CI/CD patterns
9. `azure-verified-modules-terraform.instructions.md` - Azure Terraform
10. `performance-optimization.instructions.md` - Performance tuning

### Top 10 Agents
1. `bash-expert.agent.md` - Shell scripting expert
2. `terraform-expert.agent.md` - Infrastructure specialist
3. `python-expert.agent.md` - Python development expert
4. `security-expert.agent.md` - Security specialist
5. `test-engineer.agent.md` - Testing expert
6. `arch.agent.md` - Architecture advisor
7. `infrastructure-automation.agent.md` - Automation specialist
8. `database-expert.agent.md` - Database specialist
9. `devops-expert.agent.md` - DevOps specialist
10. `technical-writer.agent.md` - Documentation expert

## 📖 How to Use

### Using Prompts
```bash
# In VS Code with GitHub Copilot
@workspace Use [prompt-name].prompt.md

# Example:
@workspace Use code-exemplars-blueprint-generator.prompt.md
```

### Using Instructions
```bash
# Instructions automatically apply based on file extensions
# Just edit files and get context-aware suggestions:
- Edit .sh files → bash.instructions.md applies
- Edit .py files → python.instructions.md applies
- Edit .tf files → terraform.instructions.md applies
```

### Using Agents
```bash
# Chat with specialized agents
@workspace /chat with [agent-name].agent.md

# Example:
@workspace /chat with bash-expert.agent.md "Review my error handling"
```

### Using Collections
```bash
# Load collections via VS Code settings
# Collections bundle related tools for specific workflows
```

## 🔗 Integration with Project

These tools complement your existing project structure:

```
Your Code             Copilot Tools
─────────────         ──────────────
bin/scripts      ←→   bash.instructions.md
lib/modules      ←→   code-review-generic.instructions.md + review-and-refactor.prompt.md
tests/           ←→   breakdown-test.prompt.md + pytest-coverage.prompt.md
specs/           ←→   create-implementation-plan.prompt.md
config/          ←→   terraform.instructions.md
```

## 📊 Statistics

- **Total Tools**: 492 files
- **Prompts**: 137 task templates
- **Instructions**: 152 language/framework guides
- **Agents**: 138 specialized assistants
- **Collections**: 65 curated bundles
- **Documentation**: 4 comprehensive guides
- **Total Size**: ~1.5 MB of pure knowledge

## 🎓 Learning Path

### Week 1: Basics
1. Read QUICK_REFERENCE.md
2. Try 3-5 essential prompts
3. Edit files to see instructions in action

### Week 2: Deep Dive
1. Explore TOOLS_INDEX.md
2. Chat with relevant agents
3. Read COPILOT_TOOLS_SUMMARY.md workflows

### Week 3: Integration
1. Apply tools to your daily workflow
2. Create custom prompts based on patterns
3. Load collections for comprehensive workflows

### Week 4+: Mastery
1. Contribute new patterns
2. Share knowledge with team
3. Optimize workflows based on experience

## 🆘 Need Help?

1. **Quick answers**: Check QUICK_REFERENCE.md
2. **Find a tool**: Browse TOOLS_INDEX.md
3. **Learn workflows**: Read COPILOT_TOOLS_SUMMARY.md
4. **Understand import**: See IMPORT_SUMMARY.md
5. **Specific guidance**: Chat with relevant agent

## 🌟 Pro Tips

1. **Start small**: Use 1-2 prompts per week, gradually expand
2. **Let instructions work**: They auto-apply based on file types
3. **Ask agents**: They're always ready to help
4. **Load collections**: Bundle tools for complex workflows
5. **Create patterns**: Document successful workflows for reuse

## 🔄 Keeping Updated

```bash
# To update tools from awesome-copilot:
cd /tmp
git clone https://github.com/github/awesome-copilot.git
# Review new tools and copy relevant ones to .github/
```

## 📞 Resources

- **Original Repo**: https://github.com/github/awesome-copilot
- **GitHub Copilot Docs**: https://docs.github.com/en/copilot
- **VS Code Copilot**: https://code.visualstudio.com/docs/copilot

---

**Last Updated**: 2025-12-25  
**Source**: github/awesome-copilot  
**Project**: VPS Developer Workstation Provisioning Tool  

**Next Action**: Open `QUICK_REFERENCE.md` and start using these powerful tools! 🚀
