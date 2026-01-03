# Publishing Guide

Guide for publishing Consonant Relayer Helm chart to registries.

## 📋 Table of Contents

- [Chart Registries](#chart-registries)
- [GitHub Container Registry](#github-container-registry)
- [Artifact Hub](#artifact-hub)
- [Helm Repository](#helm-repository)
- [CI/CD Automation](#cicd-automation)
- [Verification](#verification)

## 📦 Chart Registries

### Supported Registries

1. **GitHub Container Registry (GHCR)** - Recommended
   - Free for public charts
   - OCI support
   - Integrated with GitHub

2. **Artifact Hub**
   - Chart discovery
   - Automatic verification
   - Community visibility

3. **ChartMuseum**
   - Self-hosted option
   - Traditional Helm repository
   - Full control

## 🐙 GitHub Container Registry

### Prerequisites
```bash
# GitHub personal access token
# Settings → Developer settings → Personal access tokens
# Permissions: write:packages, read:packages, delete:packages

export GITHUB_TOKEN="ghp_..."
export GITHUB_USERNAME="your-username"
```

### Login
```bash
# Login to GHCR
echo $GITHUB_TOKEN | helm registry login ghcr.io \
  --username $GITHUB_USERNAME \
  --password-stdin
```

### Package Chart
```bash
# Update dependencies
helm dependency update

# Package chart
helm package .

# Output: consonant-relayer-1.0.0.tgz
```

### Push to Registry
```bash
# Push chart
helm push consonant-relayer-1.0.0.tgz \
  oci://ghcr.io/consonant/helm-charts

# Verify
helm show chart oci://ghcr.io/consonant/helm-charts/consonant-relayer \
  --version 1.0.0
```

### Install from Registry
```bash
# Install from OCI registry
helm install consonant-prod \
  oci://ghcr.io/consonant/helm-charts/consonant-relayer \
  --version 1.0.0 \
  --namespace consonant-system \
  --create-namespace
```

### Make Package Public
```bash
# Via GitHub UI:
# 1. Go to package: https://github.com/orgs/consonant/packages
# 2. Click package name
# 3. Package settings → Change visibility → Public
```

## 🎯 Artifact Hub

### Register Repository

1. **Create artifacthub-repo.yml:**
```yaml
# artifacthub-repo.yml
repositoryID: <UUID>
owners:
  - name: Consonant Team
    email: helm@consonant.xyz

# Chart metadata
#
# This file must be in the root of the repository
```

2. **Add to Chart.yaml:**
```yaml
# Chart.yaml annotations
annotations:
  # Artifact Hub metadata
  artifacthub.io/changes: |
    - kind: added
      description: Initial release
    - kind: security
      description: Enable external secrets by default
  
  artifacthub.io/containsSecurityUpdates: "true"
  artifacthub.io/prerelease: "false"
  
  artifacthub.io/images: |
    - name: relayer
      image: ghcr.io/consonant/relayer:1.0.0
      whitelisted: true
    - name: cloudflared
      image: cloudflare/cloudflared:2025.1.1
    - name: kubectl
      image: bitnami/kubectl:1.28
  
  artifacthub.io/operator: "false"
  artifacthub.io/operatorCapabilities: ""
  
  artifacthub.io/links: |
    - name: Documentation
      url: https://docs.consonant.xyz
    - name: Source Code
      url: https://github.com/consonant/helm-charts
    - name: Support
      url: https://consonant.xyz/support
  
  artifacthub.io/maintainers: |
    - name: Consonant Team
      email: helm@consonant.xyz
  
  artifacthub.io/recommendations: |
    - url: https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets
    - url: https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
  
  artifacthub.io/signKey: |
    fingerprint: ABC123...
    url: https://keybase.io/consonant/pgp_keys.asc
```

3. **Register on Artifact Hub:**
   - Go to https://artifacthub.io
   - Sign in with GitHub
   - Add repository
   - Verify ownership

### Update Chart Metadata
```bash
# Metadata is read from:
# - Chart.yaml
# - README.md
# - artifacthub-repo.yml

# Artifact Hub scans repository every hour
# Force sync in UI if needed
```

## 📚 Helm Repository

### Setup GitHub Pages
```bash
# 1. Create gh-pages branch
git checkout --orphan gh-pages
git rm -rf .

# 2. Create index
cat > index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Consonant Helm Charts</title>
</head>
<body>
    <h1>Consonant Helm Charts</h1>
    <p>Add repository:</p>
    <pre>helm repo add consonant https://consonant.github.io/helm-charts</pre>
</body>
</html>
EOF

# 3. Package all charts
helm package ../charts/consonant-relayer

# 4. Generate index
helm repo index . --url https://consonant.github.io/helm-charts

# 5. Commit and push
git add .
git commit -m "Initial Helm repository"
git push origin gh-pages

# 6. Enable GitHub Pages
# Settings → Pages → Source: gh-pages branch
```

### Use Repository
```bash
# Add repository
helm repo add consonant https://consonant.github.io/helm-charts

# Update
helm repo update

# Search
helm search repo consonant

# Install
helm install consonant-prod consonant/consonant-relayer
```

## 🤖 CI/CD Automation

### GitHub Actions Workflow
```yaml
# .github/workflows/release.yml
name: Release Charts

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Configure Git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
      
      - name: Install Helm
        uses: azure/setup-helm@v3
        with:
          version: '3.13.0'
      
      - name: Login to GHCR
        run: |
          echo ${{ secrets.GITHUB_TOKEN }} | helm registry login ghcr.io \
            --username ${{ github.actor }} \
            --password-stdin
      
      - name: Package Chart
        run: |
          cd charts/consonant-relayer
          helm dependency update
          helm package .
      
      - name: Push to GHCR
        run: |
          helm push charts/consonant-relayer/consonant-relayer-*.tgz \
            oci://ghcr.io/${{ github.repository_owner }}/helm-charts
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: charts/consonant-relayer/consonant-relayer-*.tgz
          generate_release_notes: true
```

### Chart Testing Workflow
```yaml
# .github/workflows/test.yml
name: Test Charts

on:
  pull_request:
    paths:
      - 'charts/**'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Helm
        uses: azure/setup-helm@v3
      
      - name: Lint Chart
        run: |
          helm lint charts/consonant-relayer
      
      - name: yamllint
        run: |
          pip install yamllint
          yamllint charts/consonant-relayer
  
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Helm
        uses: azure/setup-helm@v3
      
      - name: Install unittest plugin
        run: |
          helm plugin install https://github.com/helm-unittest/helm-unittest
      
      - name: Run tests
        run: |
          helm unittest charts/consonant-relayer
  
  install:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Kind
        uses: helm/kind-action@v1
      
      - name: Install Chart
        run: |
          helm install test charts/consonant-relayer \
            --namespace test-system \
            --create-namespace \
            --set cluster.name=test \
            --set backend.url=http://backend:3000 \
            --set secrets.mode=kubernetes \
            --set secrets.kubernetes.llmApiKey=test \
            --set secrets.kubernetes.tunnelToken=test \
            --wait --timeout 5m
      
      - name: Verify Installation
        run: |
          kubectl get pods -n test-system
          kubectl get svc -n test-system
```

## ✅ Verification

### Verify Chart Package
```bash
# Extract and inspect
tar -xzf consonant-relayer-1.0.0.tgz
cd consonant-relayer

# Check structure
tree

# Expected:
# consonant-relayer/
# ├── Chart.yaml
# ├── README.md
# ├── values.yaml
# ├── templates/
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   └── ...
# └── charts/  # Dependencies
```

### Verify in Registry
```bash
# GHCR
helm show chart oci://ghcr.io/consonant/helm-charts/consonant-relayer

# Traditional repository
helm show chart consonant/consonant-relayer

# Check all versions
helm search repo consonant --versions
```

### Test Installation
```bash
# Install from registry
helm install test \
  oci://ghcr.io/consonant/helm-charts/consonant-relayer \
  --dry-run --debug

# Verify rendered templates
helm template test \
  oci://ghcr.io/consonant/helm-charts/consonant-relayer \
  | kubectl apply --dry-run=client -f -
```

### Security Scanning
```bash
# Scan chart for security issues
trivy config consonant-relayer-1.0.0.tgz

# Scan images referenced in chart
helm template test consonant-relayer-1.0.0.tgz \
  | grep 'image:' \
  | awk '{print $2}' \
  | xargs -I {} trivy image {}
```

## 📝 Checklist

Before publishing:

**Chart Quality:**
- [ ] Version incremented in Chart.yaml
- [ ] CHANGELOG.md updated
- [ ] README.md current
- [ ] All tests pass
- [ ] No linting errors

**Metadata:**
- [ ] Artifact Hub annotations complete
- [ ] Images whitelisted
- [ ] Links working
- [ ] Maintainers listed

**Security:**
- [ ] Images scanned
- [ ] Security updates documented
- [ ] No HIGH/CRITICAL vulnerabilities

**Documentation:**
- [ ] Installation guide updated
- [ ] Examples working
- [ ] NOTES.txt helpful

**Testing:**
- [ ] Dry-run succeeds
- [ ] Test installation works
- [ ] Upgrade from previous version works

## 🚨 Troubleshooting

### Push Fails
```bash
# Error: failed to authorize: authentication required
# Solution: Login again
echo $GITHUB_TOKEN | helm registry login ghcr.io \
  --username $GITHUB_USERNAME \
  --password-stdin
```

### Package Not Found
```bash
# Error: chart not found
# Solution: Check package visibility (must be public)

# Also try with version
helm show chart oci://ghcr.io/consonant/helm-charts/consonant-relayer \
  --version 1.0.0
```

### Artifact Hub Not Updating
```bash
# Force sync:
# 1. Go to Artifact Hub
# 2. Repository settings
# 3. Click "Trigger webhook"

# Or wait up to 1 hour for automatic sync
```

---

**Need help?** support@consonant.xyz
```

---

## 25. **.helmignore** - Files to Exclude
```
# .helmignore - Files to exclude from Helm package

# Development files
.git/
.gitignore
.github/
.vscode/
.idea/

# CI/CD
.gitlab-ci.yml
.travis.yml
Jenkinsfile

# Documentation (exclude from package, not from repo)
CONTRIBUTING.md
PUBLISHING.md
FUTURE_ROADMAP.md

# Test files
tests/
ci/
*.test.yaml

# Build artifacts
*.tgz
dist/
build/

# Temporary files
*.swp
*.swo
*~
.DS_Store
Thumbs.db

# Logs
*.log

# Scripts (development only)
scripts/
tools/
hack/

# Examples (keep in repo, exclude from package)
examples/

# Terraform
*.tfstate
*.tfstate.backup
.terraform/

# Python
__pycache__/
*.py[cod]
*$py.class
.venv/
venv/

# Node
node_modules/
package-lock.json
yarn.lock

# IDEs
*.iml
.project
.classpath
.settings/

# OS files
.DS_Store
._.DS_Store
**/.DS_Store
**/._.DS_Store

# Backup files
*.bak
*.backup
*.old

# Local development
local/
tmp/
temp/

# Documentation build
site/
_site/

# Coverage
coverage/
*.coverprofile