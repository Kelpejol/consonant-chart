# Contributing to Consonant Relayer Helm Chart

Thank you for your interest in contributing! This guide will help you get started.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)
- [Community](#community)

## 📜 Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please read our [Code of Conduct](CODE_OF_CONDUCT.md).

**TL;DR:**
- Be respectful and inclusive
- Welcome newcomers
- Give and accept constructive feedback
- Focus on what's best for the community

## 🚀 Getting Started

### Ways to Contribute

- 🐛 **Report bugs** - Found an issue? Let us know!
- 💡 **Suggest features** - Have an idea? We'd love to hear it!
- 📝 **Improve docs** - Help others understand better
- 🔧 **Fix issues** - Submit a PR with a fix
- ✨ **Add features** - Implement new functionality
- 🧪 **Write tests** - Improve test coverage
- 👀 **Review PRs** - Help review others' contributions

### Good First Issues

Look for issues labeled `good-first-issue`:
https://github.com/consonant/helm-charts/labels/good-first-issue

These are great for getting started!

## 🛠️ Development Setup

### Prerequisites
```bash
# Required
- Kubernetes cluster (kind, minikube, or cloud)
- Helm 4.0+
- kubectl 1.33+
- Git

# Recommended
- helm-docs (for documentation)
- yamllint (for YAML linting)
- helm unittest plugin (for tests)
```

### Install Tools
```bash
# Helm docs
go install github.com/norwoodj/helm-docs/cmd/helm-docs@latest

# Helm unittest
helm plugin install https://github.com/helm-unittest/helm-unittest

# yamllint
pip install yamllint

# kind (local Kubernetes)
go install sigs.k8s.io/kind@latest
```

### Clone Repository
```bash
# Fork the repository first on GitHub
# Then clone your fork
git clone https://github.com/YOUR-USERNAME/helm-charts.git
cd helm-charts/charts/consonant-relayer

# Add upstream remote
git remote add upstream https://github.com/consonant/helm-charts.git
```

### Create Local Cluster
```bash
# Create kind cluster
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: consonant-dev
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# Verify
kubectl cluster-info
kubectl get nodes
```

### Install Dependencies
```bash
# Update Helm dependencies
helm dependency update

# Install External Secrets Operator (optional)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

## 🔨 Making Changes

### Branch Naming

Use descriptive branch names:
```bash
git checkout -b feature/add-redis-cache
git checkout -b fix/networkpolicy-dns
git checkout -b docs/improve-readme
```

**Conventions:**
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation
- `test/` - Test improvements
- `refactor/` - Code refactoring
- `chore/` - Maintenance tasks

### Coding Standards

#### YAML Style
```yaml
# ✅ Good
metadata:
  name: {{ include "consonant-relayer.fullname" . }}
  labels:
    {{- include "consonant-relayer.labels" . | nindent 4 }}

# ❌ Bad
metadata:
  name: {{include "consonant-relayer.fullname" .}}
  labels:
    {{ include "consonant-relayer.labels" . | nindent 4}}
```

#### Template Comments
```yaml
{{/*
Function Name - Brief Description
==================================
Longer description of what this function does.
Arguments:
  - arg1: Description
Returns: Description
Example: {{ include "function" . }}
*/}}
{{- define "function" -}}
...
{{- end -}}
```

#### Values Organization
```yaml
# Group related settings
# Use comments to explain non-obvious settings
# Provide sensible defaults

# Backend Configuration
backend:
  # Backend server URL (required)
  url: ""
  
  # Connection timeout in seconds (5-300)
  connectionTimeout: 15
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):
```bash
# Format
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `test:` - Tests
- `refactor:` - Code refactoring
- `style:` - Formatting
- `chore:` - Maintenance

**Examples:**
```bash
feat(networkpolicy): add support for custom egress rules

Allow users to specify custom egress rules in NetworkPolicy
for specific use cases requiring additional destinations.

Closes #123

---

fix(secrets): handle missing external secret gracefully

When ExternalSecret resource doesn't exist, provide clear
error message instead of generic failure.

Fixes #456

---

docs(readme): improve installation instructions

Add step-by-step guide with screenshots and common pitfalls
to help new users get started faster.
```

### Documentation

**Always update documentation:**
- [ ] Update README.md if adding features
- [ ] Update values.yaml comments
- [ ] Add/update examples
- [ ] Update CHANGELOG.md
- [ ] Regenerate docs: `helm-docs`

**Documentation locations:**
- `README.md` - Main documentation
- `values.yaml` - Configuration reference
- `templates/NOTES.txt` - Post-install notes
- `*.md` files - Detailed guides

## 🧪 Testing

### Lint Chart
```bash
# YAML linting
yamllint .

# Helm linting
helm lint .

# Template validation
helm template test . --debug
```

### Unit Tests
```bash
# Run all tests
helm unittest .

# Run specific test file
helm unittest -f tests/deployment_test.yaml .

# Update snapshots
helm unittest -u .
```

**Test file structure:**
```yaml
# tests/deployment_test.yaml
suite: test deployment
templates:
  - deployment.yaml
tests:
  - it: should create deployment
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: metadata.name
          value: RELEASE-NAME-consonant-relayer
  
  - it: should set replicas
    set:
      relayer.replicas: 5
    asserts:
      - equal:
          path: spec.replicas
          value: 5
```

### Integration Tests
```bash
# Install in test cluster
helm install test-release . \
  --namespace test-system \
  --create-namespace \
  --set cluster.name=test-cluster \
  --set backend.url=http://backend:3000 \
  --set secrets.mode=kubernetes \
  --set secrets.kubernetes.llmApiKey=test \
  --set secrets.kubernetes.tunnelToken=test

# Run smoke tests
kubectl get pods -n test-system
kubectl logs -n test-system -l app.kubernetes.io/name=consonant-relayer

# Cleanup
helm uninstall test-release -n test-system
kubectl delete namespace test-system
```

### Test Checklist

Before submitting PR:
- [ ] YAML linting passes
- [ ] Helm linting passes
- [ ] Unit tests pass
- [ ] Integration tests pass (manual)
- [ ] Documentation updated
- [ ] Examples work

## 📤 Submitting Changes

### Before Submitting
```bash
# Sync with upstream
git fetch upstream
git rebase upstream/main

# Run all checks
make test  # or manual steps above

# Update documentation
helm-docs
git add README.md

# Commit changes
git commit -m "feat: add redis caching support"

# Push to fork
git push origin feature/add-redis-cache
```

### Create Pull Request

1. **Go to GitHub:**
   https://github.com/consonant/helm-charts/compare

2. **Select your branch:**
   - Base: `main`
   - Compare: `your-username:feature/add-redis-cache`

3. **Fill PR template:**
```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [x] New feature
   - [ ] Breaking change
   - [ ] Documentation update
   
   ## Checklist
   - [x] Tests pass
   - [x] Documentation updated
   - [x] CHANGELOG.md updated
   - [x] Follows coding standards
   
   ## Testing
   Describe testing performed
   
   ## Screenshots
   If applicable
   
   ## Related Issues
   Closes #123
```

4. **Submit PR**

### PR Review Process

1. **Automated checks:**
   - CI/CD pipeline runs
   - Linting checks
   - Unit tests
   - Security scanning

2. **Code review:**
   - Maintainer reviews code
   - May request changes
   - Approves when ready

3. **Merge:**
   - Squash and merge
   - Delete branch

**Timeline:**
- Initial review: 2-3 business days
- Follow-up: 1-2 business days

### Review Guidelines

When reviewing PRs:
- Be respectful and constructive
- Ask questions instead of making demands
- Explain the "why" behind suggestions
- Approve when ready, even if minor issues remain
- Test the changes locally if significant

## 🚢 Release Process

### Versioning

We use [Semantic Versioning](https://semver.org/):
- **MAJOR:** Breaking changes
- **MINOR:** New features (backward compatible)
- **PATCH:** Bug fixes

### Release Checklist

For maintainers:
```bash
# 1. Update version
# Edit Chart.yaml:
version: 1.1.0

# 2. Update changelog
# Edit CHANGELOG.md

# 3. Commit changes
git commit -am "chore: release v1.1.0"
git tag v1.1.0
git push origin main --tags

# 4. Create GitHub release
# - Go to Releases
# - Create new release
# - Tag: v1.1.0
# - Copy CHANGELOG entry
# - Attach artifacts

# 5. Publish chart
helm package .
helm push consonant-relayer-1.1.0.tgz oci://ghcr.io/consonant/helm-charts

# 6. Update documentation
# Update docs.consonant.xyz

# 7. Announce
# - GitHub Discussions
# - Slack
# - Twitter
```

## 👥 Community

### Communication Channels

- **GitHub Issues:** Bug reports, feature requests
- **GitHub Discussions:** General discussions, questions
- **Slack:** Real-time chat, support
- **Twitter:** Announcements, updates

### Community Calls

- **When:** First Wednesday of each month, 10 AM PST
- **Where:** Zoom (link in Slack)
- **Agenda:** Posted in discussions 1 week before

### Getting Help

- **Documentation:** https://docs.consonant.xyz
- **Slack:** https://consonant.xyz/slack
- **GitHub Issues:** https://github.com/consonant/helm-charts/issues
- **Email:** support@consonant.xyz

### Recognition

Contributors are recognized:
- Listed in CHANGELOG.md
- Mentioned in release notes
- Added to CONTRIBUTORS.md
- Invited to contributor meetings

## ❓ FAQ

**Q: How long does review take?**  
A: Usually 2-3 business days for initial review.

**Q: Can I work on multiple PRs?**  
A: Yes! But focus on getting one merged before starting many others.

**Q: What if my PR conflicts with another?**  
A: Rebase on latest main: `git rebase upstream/main`

**Q: Can I update someone else's PR?**  
A: Yes, if they request help or it's been inactive for 2+ weeks.

**Q: Who decides what gets merged?**  
A: Maintainers make final decisions, considering community feedback.

**Q: How do I become a maintainer?**  
A: Consistent contributions, good reviews, community involvement.

## 📜 License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

---

**Thank you for contributing! 🎉**

For questions: support@consonant.xyz