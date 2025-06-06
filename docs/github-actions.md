# GitHub Actions Workflows

This repository uses GitHub Actions for continuous integration, automated testing, and release automation. Here's an overview of the workflows and how to use them.

## 🔄 Available Workflows

### 1. CI Workflow (`main.yml`)

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches

**What it does:**
- Tests the gem across multiple Ruby versions (3.1, 3.2, 3.3)
- Tests against multiple Rails versions (7.0, 7.1)
- Runs RuboCop for code style checking
- Performs security audits with bundler-audit
- Validates gem can be built successfully

### 2. Pre-release Validation (`pre-release.yml`)

**Triggers:**
- Push of version tags (e.g., `v1.0.0`)

**What it does:**
- Validates version consistency across files
- Checks CHANGELOG.md has entry for the version
- Runs full test suite
- Tests gem build and installation
- Verifies documentation completeness
- Ensures release readiness

### 3. Release Workflow (`release.yml`)

**Triggers:**
- GitHub release is published

**What it does:**
- Builds the gem
- Publishes to RubyGems.org
- Uploads gem file as release asset
- Updates release notes with installation instructions
- Performs cleanup

## 🚀 Release Process

### Step 1: Prepare the Release

1. **Update version** in `lib/action_webhook/version.rb`
2. **Update CHANGELOG.md** with release notes
3. **Commit changes** and push to main branch
4. **Create and push a version tag**:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

### Step 2: Validate Pre-release

The pre-release validation workflow will automatically run when you push the tag. It will:
- ✅ Verify all version numbers match
- ✅ Check CHANGELOG.md has the version entry
- ✅ Run all tests
- ✅ Validate gem can be built and installed
- ✅ Check documentation completeness

### Step 3: Create GitHub Release

1. Go to the [Releases page](../../releases)
2. Click "Create a new release"
3. Select the tag you created (e.g., `v1.0.0`)
4. Fill in the release title and description
5. Click "Publish release"

### Step 4: Automatic Publication

Once you publish the GitHub release, the release workflow will automatically:
- 🔨 Build the gem
- 📦 Publish to RubyGems.org
- 📎 Attach gem file to the release
- 📝 Update release notes with installation instructions

## 🔧 Setup Requirements

### Secrets Configuration

The release workflow requires the following GitHub secret:

#### `RUBYGEMS_API_KEY`

1. Go to [RubyGems.org](https://rubygems.org/profile/edit)
2. Create an API key with push permissions
3. Add it as a repository secret:
   - Go to **Settings** → **Secrets and variables** → **Actions**
   - Click **New repository secret**
   - Name: `RUBYGEMS_API_KEY`
   - Value: Your RubyGems API key

### Permissions

Ensure the repository has the following permissions:
- **Contents**: Read and write (for creating releases)
- **Actions**: Read (for running workflows)

## 🐛 Troubleshooting

### Release Workflow Fails

**Version Mismatch Error:**
```
❌ Version mismatch! Gemspec has 1.0.0 but tag is 1.0.1
```
- Ensure `lib/action_webhook/version.rb` matches your git tag
- Update the version and create a new tag

**RubyGems Authentication Error:**
```
❌ Authentication failed
```
- Check that `RUBYGEMS_API_KEY` secret is correctly set
- Verify the API key has push permissions
- Ensure you have ownership/maintainer rights on the gem

**Missing CHANGELOG Entry:**
```
❌ CHANGELOG.md does not contain entry for version 1.0.0
```
- Add a section in CHANGELOG.md for your version:
  ```markdown
  ## [1.0.0] - 2025-06-06
  ### Added
  - Initial release
  ```

### CI Workflow Issues

**Test Failures:**
- Check the test output in the workflow logs
- Run tests locally: `bundle exec rspec`
- Fix failing tests before merging

**RuboCop Violations:**
- Run locally: `bundle exec rubocop`
- Auto-fix: `bundle exec rubocop -A`

## 📋 Workflow Status Badges

Add these badges to your README.md to show workflow status:

```markdown
[![CI](https://github.com/vinayuttam/action_webhook/workflows/CI/badge.svg)](https://github.com/vinayuttam/action_webhook/actions/workflows/main.yml)
[![Release](https://github.com/vinayuttam/action_webhook/workflows/Release/badge.svg)](https://github.com/vinayuttam/action_webhook/actions/workflows/release.yml)
```

## 🔄 Manual Testing

You can manually trigger workflows for testing:

```bash
# Test pre-release validation
git tag v1.0.0-test
git push origin v1.0.0-test

# Delete test tag when done
git tag -d v1.0.0-test
git push origin :refs/tags/v1.0.0-test
```

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [RubyGems API Documentation](https://guides.rubygems.org/rubygems-org-api/)
- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)

---

This automated release process ensures consistent, reliable gem publishing while maintaining quality standards through comprehensive testing and validation.
