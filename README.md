# Bot Template Repository

**Central source of truth for CI/CD infrastructure and configuration across all Bot Army bot repositories.**

This template ensures consistency, simplifies new bot setup, and makes it easy to propagate improvements across the ecosystem.

## Overview

Instead of manually creating infrastructure files for each new bot, use this template to:
- ✅ Ensure all bots have consistent CI/CD pipelines
- ✅ Reduce setup time from hours to minutes
- ✅ Maintain a single source of truth for best practices
- ✅ Easily update all bots when infrastructure improves

## Files Included

### Core Infrastructure Files

| File | Purpose |
|------|---------|
| `git-hooks/pre-push` | Pre-push validation: compile, lint, build release, publish to GitHub |
| `Makefile` | Development commands: setup, test, release, publish |
| `Jenkinsfile` | Jenkins CI/CD pipeline: download pre-built releases, deploy, notify |
| `mix.exs` | Elixir project config with OTP release settings |
| `docs/SETUP.md` | Developer setup guide and workflow documentation |

### Documentation Files

| File | Purpose |
|------|---------|
| `TEMPLATE_README.md` | Detailed guide on using this template |
| `README.md` | This file - overview of the template |
| `setup_new_bot.sh` | Automated script to create new bot from template |

## Quick Start: Creating a New Bot

### Option 1: Using the Automated Setup Script (Recommended)

```bash
cd bot_template
./setup_new_bot.sh bot_army_newbot newbot_bot newbot "Newbot Bot"
```

This automatically:
- Creates the new bot directory
- Copies all template files
- Replaces all placeholders with correct values
- Makes scripts executable

### Option 2: Manual Setup

1. **Copy template files:**
   ```bash
   cp -r bot_template/git-hooks ./
   cp -r bot_template/docs ./
   cp bot_template/{Makefile,Jenkinsfile,mix.exs} ./
   ```

2. **Replace placeholders** using the mapping below

3. **Update infrastructure** configuration (see TEMPLATE_README.md)

## Parameter Reference

Every bot needs these parameters configured:

| Placeholder | Example | What to Use |
|-------------|---------|------------|
| `{{BOT_APP_NAME}}` | `bot_army_newbot` | Elixir app name in snake_case |
| `{{BOT_APP_NAME_CAMEL}}` | `BotArmyNewbot` | Module name in PascalCase |
| `{{BOT_RELEASE_NAME}}` | `newbot_bot` | OTP release name (always `{word}_bot`) |
| `{{BOT_NAME_TITLE}}` | `Newbot Bot` | Display name with spaces and capitals |
| `{{GITHUB_REPO_SUFFIX}}` | `newbot` | GitHub repo name after "ergon-" |
| `{{DEFAULT_VERSION}}` | `0.1.0` | Version fallback (usually `0.1.0`) |

### Naming Convention

For consistency, follow this pattern for a new bot `xyz`:

- **GitHub repo:** `ergon-xyz`
- **App name:** `bot_army_xyz`
- **Release name:** `xyz_bot`
- **Module name:** `BotArmyXyz`
- **Title:** `Xyz Bot` (with capital B)

### Examples

**GTD Bot:**
- GitHub: `ergon-gtd` | App: `bot_army_gtd` | Release: `gtd_bot` | Module: `BotArmyGtd`

**LLM Bot (exception):**
- GitHub: `ergon-llm` | App: `bot_army_llm` | Release: `llm_proxy` | Module: `BotArmyLlm`

**Fitness Bot:**
- GitHub: `ergon-fitness` | App: `bot_army_fitness` | Release: `fitness_bot` | Module: `BotArmyFitness`

## What Each File Does

### git-hooks/pre-push

Runs automatically when you push to `main`. Validates and publishes releases:

```
git push
  ↓
Pre-push hook runs
  ↓
mix deps.get (install dependencies)
  ↓
mix compile (validate compilation)
  ↓
mix credo (linting, non-blocking)
  ↓
MIX_ENV=prod mix release (build OTP release)
  ↓
Create tarball: bot_name-VERSION.tar.gz
  ↓
gh release create (publish to GitHub)
  ↓
Push completes
```

### Makefile

Standard development commands:

- `make setup` - Install deps + git hooks
- `make setup-hooks` - Configure git core.hooksPath
- `make test` - Run tests
- `make credo` - Run linter
- `make dialyzer` - Static type checking
- `make check` - All checks (test, credo, dialyzer)
- `make format` - Format code
- `make release` - Build release locally
- `make publish-release` - Package and publish to GitHub

### Jenkinsfile

Jenkins CI/CD pipeline that runs on every commit:

```
GitHub commit detected
  ↓
Jenkins polls every 5 minutes
  ↓
Downloads latest release tarball
  ↓
Extracts release
  ↓
Deploys to /opt/ergon/releases/BOT_NAME/
  ↓
Restarts service
  ↓
Publishes NATS notification (success/failure)
```

Key features:
- Downloads pre-built releases (not building from source)
- Uses `gh` CLI for GitHub interactions
- Publishes deployment notifications to NATS
- Cleans workspace after deployment

### mix.exs

Elixir project configuration with:
- Standard dependencies (bot_army_core, bot_army_runtime, ecto, postgres, etc.)
- OTP release configuration with custom release name
- Development dependencies (credo, dialyxir, excoveralls)

### docs/SETUP.md

Developer-facing documentation covering:
- Prerequisites and installation
- Development workflow
- How pushing to GitHub triggers the pipeline
- Troubleshooting common issues
- Manual release commands (if needed)

## Infrastructure Integration

After using the template, you need to register the bot in `bot_army_infra`:

### 1. Update jenkins_bot_config.sh

Add bot mapping to `bot_army_infra/salt/common/files/jenkins_bot_config.sh`:

```bash
*ergon-newbot*)
  echo "BOT_NAME=newbot_bot"
  echo "RELEASE_DIR=/opt/ergon/releases/newbot_bot"
  ;;
```

### 2. Update pillar/common.sls

Add to `bot_army_infra/pillar/common.sls` under `services.bots`:

```yaml
newbot:
  name: newbot_bot
  release_dir: /opt/ergon/releases/newbot_bot
  github_repo: ergon-automation-labs/ergon-newbot
```

Add to `repositories.schemas` if there's a schema repo:

```yaml
newbot:
  url: "git@github.com:ergon-automation-labs/ergon-schemas-newbot.git"
  dest: "/etc/bot_army/schemas/newbot"
```

Add to `repositories.bots`:

```yaml
newbot:
  url: "git@github.com:ergon-automation-labs/ergon-newbot.git"
  dest: "/opt/ergon/bots/newbot"
```

## End-to-End Workflow

After setup, the bot follows this workflow:

1. **Developer** makes changes in the bot repo
2. **git push** triggers the pre-push hook
3. **Pre-push hook** validates, builds, and publishes to GitHub
4. **Jenkins** (running on Air node) polls GitHub
5. **Jenkins** detects new release and downloads tarball
6. **Jenkins** deploys to `/opt/ergon/releases/BOT_NAME/`
7. **Jenkins** restarts the launchd service
8. **Jenkins** publishes deployment notification to NATS
9. **Service** is running with new code

Total time: ~2-5 minutes from push to deployed.

## Customization & Future Enhancements

### Potential Additions to Template

- **CLAUDE.md template** - Bot-specific development guidelines
- **GitHub Actions workflows** - For testing, coverage, linting
- **Contributing guidelines** - Contributor expectations
- **.gitignore template** - Elixir-specific ignores
- **Docker setup** - For local development environment
- **Database migration helpers** - Ecto migration templates

### Keeping Template Updated

When you improve infrastructure (e.g., add a new lint rule, update dependencies):

1. Update the template files here first
2. Create a PR documenting the change
3. Once merged, new bots get the improvement automatically
4. Optionally backport to existing bots

## Existing Bots Using This Template

| Bot | Release | GitHub |
|-----|---------|--------|
| GTD | `gtd_bot` | `ergon-gtd` |
| LLM | `llm_proxy` | `ergon-llm` |
| Fitness | `fitness_bot` | `ergon-fitness` |
| Chore | `chore_bot` | `ergon-chore` |
| Job | `job_bot` | `ergon-job` |

All of these are created from this template and follow the same pipeline.

## Troubleshooting

### Placeholder Not Replaced

If you see `{{PLACEHOLDER}}` in your files, search and replace was incomplete.

```bash
# Find remaining placeholders
grep -r "{{" .
```

### Setup Script Fails

Ensure you have:
- `sh` available (bash/zsh)
- `sed` available (macOS has this)
- Write permissions in the parent directory

### Release Not Detected by Jenkins

Check:
1. Release is marked as "published" (not draft) on GitHub
2. Tarball matches pattern `BOT_NAME-*.tar.gz`
3. Jenkins job is enabled for the repository
4. Jenkins is polling (check logs every 5 minutes)

## Questions or Improvements?

If you find issues with the template or want to suggest improvements:

1. Test locally in a bot repo
2. Document the issue/improvement
3. Update the template and documentation
4. Add to the backport list for existing bots

---

**Template Version:** 1.0
**Last Updated:** 2026-03-05
**Used By:** 5 production bots
