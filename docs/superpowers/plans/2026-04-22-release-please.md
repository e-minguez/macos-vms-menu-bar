# Release Please Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate releases via release-please: merging to `main` updates a Release PR with changelog; merging that PR creates a GitHub Release and triggers a build that uploads a zipped `.app` artifact.

**Architecture:** Two GitHub Actions workflows — `release-please.yml` (manages Release PRs and tags) and `build-release.yml` (compiles on `macos-15`, zips `.app`, uploads to release). Two release-please config files (`release-please-config.json`, `.release-please-manifest.json`) plus `version.txt` track the current version. `Info.plist`'s `CFBundleShortVersionString` is kept in sync via the generic extra-files updater using an inline `x-release-please-version` marker comment.

**Tech Stack:** GitHub Actions, `google-github-actions/release-please-action@v4`, `softprops/action-gh-release@v2`, `actions/checkout@v4`, `swiftc` CLI, macOS 15 runner.

---

### Task 1: Initialize version tracking files and update Info.plist

**Files:**
- Create: `version.txt`
- Create: `.release-please-manifest.json`
- Modify: `Info.plist`

- [ ] **Step 1: Create `version.txt`**

```bash
echo "0.0.1" > version.txt
```

- [ ] **Step 2: Create `.release-please-manifest.json`**

```bash
echo '{ ".": "0.0.1" }' > .release-please-manifest.json
```

- [ ] **Step 3: Update `Info.plist` — change version to `0.0.1` and add marker comment**

Replace the `CFBundleShortVersionString` block in `Info.plist`. The `<!-- x-release-please-version -->` marker tells the release-please generic updater exactly which string to replace on future releases.

The block currently reads:
```xml
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
```

Change it to:
```xml
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string><!-- x-release-please-version -->
```

- [ ] **Step 4: Verify Info.plist is still valid XML**

```bash
plutil -lint Info.plist
```

Expected output: `Info.plist: OK`

- [ ] **Step 5: Commit**

```bash
git add version.txt .release-please-manifest.json Info.plist
git commit -m "chore: initialize version tracking at 0.0.1"
```

---

### Task 2: Create release-please-config.json

**Files:**
- Create: `release-please-config.json`

- [ ] **Step 1: Create `release-please-config.json`**

```json
{
  "release-type": "simple",
  "packages": {
    ".": {
      "extra-files": [
        {
          "type": "generic",
          "path": "Info.plist"
        }
      ]
    }
  }
}
```

Write this to `release-please-config.json`.

The `simple` release type manages `CHANGELOG.md` and `version.txt`. The `extra-files` entry instructs the generic updater to find the line tagged with `<!-- x-release-please-version -->` in `Info.plist` and replace the version string on that line.

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('release-please-config.json')); print('OK')"
```

Expected output: `OK`

- [ ] **Step 3: Commit**

```bash
git add release-please-config.json
git commit -m "chore: add release-please config"
```

---

### Task 3: Create release-please workflow

**Files:**
- Create: `.github/workflows/release-please.yml`

- [ ] **Step 1: Create the workflows directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Write `.github/workflows/release-please.yml`**

```yaml
name: Release Please

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: google-github-actions/release-please-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 3: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-please.yml')); print('OK')" 2>/dev/null || \
python3 -c "
import sys
content = open('.github/workflows/release-please.yml').read()
# basic structure check
assert 'on:' in content
assert 'jobs:' in content
assert 'release-please-action' in content
print('OK')
"
```

Expected output: `OK`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release-please.yml
git commit -m "ci: add release-please workflow"
```

---

### Task 4: Create build-release workflow

**Files:**
- Create: `.github/workflows/build-release.yml`

- [ ] **Step 1: Write `.github/workflows/build-release.yml`**

```yaml
name: Build Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build app
        run: |
          chmod +x build.sh
          ./build.sh

      - name: Zip app bundle
        run: zip -r "VMMenuBar-${{ github.ref_name }}.zip" build/VMMenuBar.app

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: "VMMenuBar-${{ github.ref_name }}.zip"
```

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "
content = open('.github/workflows/build-release.yml').read()
assert 'macos-15' in content
assert 'build.sh' in content
assert 'softprops/action-gh-release' in content
assert \"VMMenuBar-\${{ github.ref_name }}.zip\" in content
print('OK')
"
```

Expected output: `OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-release.yml
git commit -m "ci: add build-release workflow for tagged releases"
```

---

### Task 5: Verify end-to-end setup

**Files:** (none — verification only)

- [ ] **Step 1: Confirm all expected files exist**

```bash
for f in \
  version.txt \
  .release-please-manifest.json \
  release-please-config.json \
  .github/workflows/release-please.yml \
  .github/workflows/build-release.yml; do
  [ -f "$f" ] && echo "OK  $f" || echo "MISSING  $f"
done
```

Expected output:
```
OK  version.txt
OK  .release-please-manifest.json
OK  release-please-config.json
OK  .github/workflows/release-please.yml
OK  .github/workflows/build-release.yml
```

- [ ] **Step 2: Confirm version consistency across files**

```bash
echo "version.txt:       $(cat version.txt)"
echo "manifest:          $(python3 -c "import json; print(json.load(open('.release-please-manifest.json'))['.'])")"
echo "Info.plist:        $(plutil -extract CFBundleShortVersionString raw Info.plist)"
```

Expected output (all three lines show `0.0.1`):
```
version.txt:       0.0.1
manifest:          0.0.1
Info.plist:        0.0.1
```

- [ ] **Step 3: Confirm build still works**

```bash
./build.sh
```

Expected output:
```
Building VMMenuBar...
Build complete! App created at: build/VMMenuBar.app
```

- [ ] **Step 4: Confirm x-release-please-version marker is present in Info.plist**

```bash
grep "x-release-please-version" Info.plist && echo "marker found"
```

Expected output:
```
    <string>0.0.1</string><!-- x-release-please-version -->
marker found
```
