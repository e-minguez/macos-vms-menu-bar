# Release Automation Design — release-please + GitHub Actions

**Date:** 2026-04-22

## Goal

Automate releases using the release-please GitHub Action. Every merge to `main` updates a "Release PR" with a changelog derived from conventional commit messages. Merging the Release PR creates a versioned GitHub Release and triggers a build that uploads a zipped `.app` artifact.

---

## Constraints

- No Apple Developer account → unsigned `.app` zipped (no `.dmg`, no notarization)
- Build target: `arm64-apple-macos13.0` → runner must be Apple Silicon (`macos-15`)
- Versioning: Conventional Commits (`feat:` → minor, `fix:` → patch, `feat!:` → major)
- Initial version: `0.0.1`

---

## Files Created or Modified

| File | Action |
|---|---|
| `.github/workflows/release-please.yml` | Create |
| `.github/workflows/build-release.yml` | Create |
| `release-please-config.json` | Create |
| `.release-please-manifest.json` | Create |
| `version.txt` | Create (initial: `0.0.1`) |
| `Info.plist` | Modify — `CFBundleShortVersionString` → `0.0.1` |

---

## Workflows

### 1. `release-please.yml`

**Trigger:** `push` to `main`

**Permissions:** `contents: write`, `pull-requests: write`

**Action:** `google-github-actions/release-please-action@v4`

**Behaviour:**
- On every merge to `main`, opens or updates a Release PR titled `chore: release X.Y.Z`
- The PR body contains an auto-generated changelog grouped by commit type (`feat`, `fix`, etc.)
- When the Release PR is merged, release-please:
  - Creates git tag `vX.Y.Z`
  - Creates a GitHub Release with the changelog as the body
  - Updates `version.txt` and `Info.plist` in the repo

### 2. `build-release.yml`

**Trigger:** `push: tags: ['v*']`

**Permissions:** `contents: write`

**Runner:** `macos-15`

**Steps:**
1. Checkout repo at the tag
2. Run `./build.sh` (compiles all Swift source files via `swiftc`)
3. Zip the output: `zip -r VMMenuBar-${{ github.ref_name }}.zip build/VMMenuBar.app`
4. Upload `VMMenuBar-<tag>.zip` to the existing GitHub Release using `softprops/action-gh-release@v2`

---

## release-please Configuration

### `release-please-config.json`

```json
{
  "release-type": "simple",
  "packages": {
    ".": {
      "extra-files": [
        "Info.plist"
      ]
    }
  }
}
```

The `simple` release type maintains `CHANGELOG.md` and `version.txt`. `Info.plist` is listed as an extra file; release-please's generic updater finds and replaces the version string (`0.0.1` → next version) using a regex that matches the `CFBundleShortVersionString` value.

### `.release-please-manifest.json`

```json
{
  ".": "0.0.1"
}
```

Tracks the current released version for the root package.

---

## Version Sync: Info.plist

`CFBundleShortVersionString` is updated from `1.0` to `0.0.1` as a one-time setup commit. release-please will keep it in sync with `version.txt` on every subsequent release by using the generic file updater.

`CFBundleVersion` (the build number, currently `1`) is left unmanaged — it is not meaningful for this distribution model.

---

## End-to-End Flow

```
merge feat: PR to main
        │
        ▼
release-please opens/updates Release PR
  - CHANGELOG.md updated
  - version.txt: 0.0.2
  - Info.plist CFBundleShortVersionString: 0.0.2
        │
        ▼ (merge Release PR)
release-please creates tag v0.0.2 + GitHub Release
        │
        ▼ (tag push triggers build-release.yml)
macos-15 runner:
  ./build.sh → build/VMMenuBar.app
  zip → VMMenuBar-v0.0.2.zip
  upload to GitHub Release
```

---

## Permissions Note

The `GITHUB_TOKEN` provided automatically by GitHub Actions is sufficient for all operations (opening PRs, creating releases, uploading assets) as long as the workflow permissions are set correctly. No additional secrets required.
