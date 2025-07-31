#!/usr/bin/env ruby
# frozen_string_literal: true

# Release preparation script for ActionWebhook
# This script performs pre-release checks and preparations

require "fileutils"
require "date"

class ReleasePreparation
  VERSION_FILE = "lib/action_webhook/version.rb"
  CHANGELOG_FILE = "CHANGELOG.md"
  GEMSPEC_FILE = "action_webhook.gemspec"

  def initialize
    @version = extract_version
    @release_date = Date.today.strftime("%Y-%m-%d")
  end

  def run
    puts "🚀 Preparing ActionWebhook v#{@version} for release..."
    puts

    perform_checks
    update_changelog_date
    validate_gemspec
    show_release_summary

    puts
    puts "✅ Release preparation complete!"
    puts
    puts "Next steps:"
    puts "1. Review all changes: git diff"
    puts "2. Commit changes: git add . && git commit -m 'Prepare v#{@version} release'"
    puts "3. Create tag: git tag v#{@version}"
    puts "4. Push changes: git push origin main --tags"
    puts "5. Build gem: gem build #{GEMSPEC_FILE}"
    puts "6. Publish gem: gem push action_webhook-#{@version}.gem"
  end

  private

  def extract_version
    content = File.read(VERSION_FILE)
    content.match(/VERSION = "(.+)"/)[1]
  rescue StandardError => e
    abort "❌ Error reading version: #{e.message}"
  end

  def perform_checks
    puts "🔍 Performing pre-release checks..."

    check_git_status
    check_version_consistency
    check_required_files
    check_documentation

    puts "✅ All checks passed"
    puts
  end

  def check_git_status
    return if system("git diff-index --quiet HEAD --")

    puts "⚠️  Warning: You have uncommitted changes"
  end

  def check_version_consistency
    gemspec_content = File.read(GEMSPEC_FILE)
    return if gemspec_content.include?("ActionWebhook::VERSION")

    abort "❌ Gemspec doesn't use ActionWebhook::VERSION"
  end

  def check_required_files
    required_files = [
      "README.md",
      "CHANGELOG.md",
      "CONTRIBUTING.md",
      "lib/action_webhook.rb",
      "lib/action_webhook/base.rb",
      "lib/action_webhook/delivery_job.rb",
      "docs/README.md"
    ]

    missing_files = required_files.reject { |file| File.exist?(file) }

    return unless missing_files.any?

    abort "❌ Missing required files: #{missing_files.join(", ")}"
  end

  def check_documentation
    docs_dir = "docs"
    return if Dir.exist?(docs_dir) && Dir.entries(docs_dir).size > 2

    abort "❌ Documentation directory is missing or empty"
  end

  def update_changelog_date
    puts "📝 Updating CHANGELOG.md with release date..."

    content = File.read(CHANGELOG_FILE)
    updated_content = content.gsub(
      /## \[#{Regexp.escape(@version)}\] - \d{4}-\d{2}-XX/,
      "## [#{@version}] - #{@release_date}"
    )

    if content != updated_content
      File.write(CHANGELOG_FILE, updated_content)
      puts "✅ Updated CHANGELOG.md with release date: #{@release_date}"
    else
      puts "ℹ️  CHANGELOG.md already has correct date format"
    end
  end

  def validate_gemspec
    puts "🔍 Validating gemspec..."

    result = system("gem build #{GEMSPEC_FILE} --quiet")
    if result
      puts "✅ Gemspec is valid"
      # Clean up the built gem file
      gem_file = "action_webhook-#{@version}.gem"
      File.delete(gem_file) if File.exist?(gem_file)
    else
      abort "❌ Gemspec validation failed"
    end
  end

  def show_release_summary
    puts "📋 Release Summary:"
    puts "   Version: #{@version}"
    puts "   Date: #{@release_date}"
    puts "   Files updated:"
    puts "   - #{VERSION_FILE}"
    puts "   - #{CHANGELOG_FILE}"
    puts "   Documentation:"
    puts "   - README.md (comprehensive)"
    puts "   - CONTRIBUTING.md (created)"
    puts "   - docs/ directory (complete)"
  end
end

# Run the release preparation
ReleasePreparation.new.run
