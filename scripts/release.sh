#!/bin/bash

# Release helper script for ActionWebhook
# This script helps create releases with proper tagging and validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if version is provided
if [ $# -eq 0 ]; then
    error "Please provide a version number (e.g., ./release.sh 1.0.0)"
fi

VERSION=$1
TAG="v${VERSION}"

info "Preparing release for ActionWebhook v${VERSION}"

# Validate version format
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Version must be in format X.Y.Z (e.g., 1.0.0)"
fi

# Check git status
if ! git diff-index --quiet HEAD --; then
    warning "You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Check if we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    warning "You're not on the main branch. Current branch: $CURRENT_BRANCH"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    error "Tag $TAG already exists"
fi

# Update version file
info "Updating version file..."
sed -i.bak "s/VERSION = \".*\"/VERSION = \"${VERSION}\"/" lib/action_webhook/version.rb
rm lib/action_webhook/version.rb.bak
success "Updated lib/action_webhook/version.rb"

# Update CHANGELOG
info "Checking CHANGELOG.md..."
if ! grep -q "## \[${VERSION}\]" CHANGELOG.md; then
    warning "CHANGELOG.md doesn't contain entry for version ${VERSION}"
    echo "Please add a changelog entry and run this script again."
    exit 1
fi
success "CHANGELOG.md contains entry for version ${VERSION}"

# Run tests
info "Running tests..."
if [ -d "spec" ]; then
    bundle exec rspec
elif [ -d "test" ]; then
    bundle exec rake test
else
    bundle exec rake
fi
success "All tests passed"

# Test gem build
info "Testing gem build..."
gem build action_webhook.gemspec > /dev/null
GEM_FILE="action_webhook-${VERSION}.gem"
if [ ! -f "$GEM_FILE" ]; then
    error "Gem build failed"
fi
rm "$GEM_FILE"
success "Gem builds successfully"

# Commit version change
info "Committing version update..."
git add lib/action_webhook/version.rb
git commit -m "Bump version to ${VERSION}"
success "Committed version update"

# Create and push tag
info "Creating and pushing tag..."
git tag -a "$TAG" -m "Release version ${VERSION}"
git push origin main
git push origin "$TAG"
success "Created and pushed tag $TAG"

# Instructions for GitHub release
echo
info "Tag $TAG has been created and pushed!"
echo
echo "Next steps:"
echo "1. Go to https://github.com/vinayuttam/action_webhook/releases/new"
echo "2. Select tag: $TAG"
echo "3. Release title: ActionWebhook $VERSION"
echo "4. Copy release notes from CHANGELOG.md"
echo "5. Click 'Publish release'"
echo
echo "The GitHub Actions workflow will automatically:"
echo "- Build and publish the gem to RubyGems"
echo "- Upload the gem file as a release asset"
echo "- Update the release notes"
echo
success "Release preparation complete!"
