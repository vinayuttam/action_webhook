# Contributing to ActionWebhook

Thank you for your interest in contributing to ActionWebhook! We welcome contributions from the community and are grateful for your support.

## 🚀 Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/action_webhook.git
   cd action_webhook
   ```
3. **Install dependencies**:
   ```bash
   bundle install
   ```
4. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🛠️ Development Setup

### Prerequisites

- Ruby >= 3.1.0
- Rails >= 7.0
- Bundler

### Running Tests

```bash
# Run the full test suite
bundle exec rspec

# Run with coverage
COVERAGE=true bundle exec rspec

# Run specific test files
bundle exec rspec spec/action_webhook/base_spec.rb
```

### Code Style

We use RuboCop to maintain code quality and consistency:

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues where possible
bundle exec rubocop -A
```

### Documentation

We use YARD for documentation:

```bash
# Generate documentation
bundle exec yard doc

# Serve documentation locally
bundle exec yard server
```

## 📝 Contribution Guidelines

### Code Standards

- Follow Ruby and Rails best practices
- Write clean, readable, and well-documented code
- Include tests for new features and bug fixes
- Maintain backward compatibility when possible
- Use descriptive commit messages

### Commit Message Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
type(scope): description

[optional body]

[optional footer(s)]
```

Examples:
- `feat: add webhook signature verification`
- `fix: resolve retry delay calculation bug`
- `docs: update installation instructions`
- `test: add specs for callback functionality`

### Pull Request Process

1. **Update documentation** if your changes affect the public API
2. **Add tests** for new functionality
3. **Ensure all tests pass** locally
4. **Update CHANGELOG.md** with your changes
5. **Create a pull request** with:
   - Clear title and description
   - Reference to any related issues
   - Screenshots (if applicable)
   - Testing instructions

### Types of Contributions

We welcome various types of contributions:

#### 🐛 Bug Reports

When filing a bug report, please include:
- Ruby and Rails versions
- ActionWebhook version
- Minimal reproduction case
- Expected vs actual behavior
- Error messages and stack traces

#### ✨ Feature Requests

For feature requests, please provide:
- Clear description of the feature
- Use case and motivation
- Proposed API (if applicable)
- Willingness to implement

#### 📚 Documentation

Documentation improvements are always welcome:
- Fix typos and grammar
- Add examples and use cases
- Improve clarity and organization
- Translate documentation

#### 🧪 Tests

Help us improve test coverage:
- Add missing test cases
- Improve test organization
- Add integration tests
- Performance benchmarks

## 🏗️ Project Structure

```
action_webhook/
├── lib/
│   └── action_webhook/
│       ├── base.rb              # Main webhook base class
│       ├── delivery_job.rb      # ActiveJob for background delivery
│       ├── configuration.rb     # Configuration management
│       ├── callbacks.rb         # Callback system
│       ├── test_helper.rb       # Testing utilities
│       └── version.rb           # Version definition
├── spec/                        # RSpec test files
├── docs/                        # Documentation
└── examples/                    # Usage examples
```

## 🧪 Testing Guidelines

### Writing Tests

- Use RSpec for testing
- Follow AAA pattern (Arrange, Act, Assert)
- Use descriptive test names
- Mock external HTTP calls
- Test both success and failure scenarios

### Example Test Structure

```ruby
RSpec.describe ActionWebhook::Base do
  describe '#deliver' do
    context 'when webhook delivery succeeds' do
      it 'sends the webhook to all endpoints' do
        # Test implementation
      end
    end

    context 'when webhook delivery fails' do
      it 'retries according to configuration' do
        # Test implementation
      end
    end
  end
end
```

## 🔍 Code Review Process

All submissions require review before merging:

1. **Automated checks** must pass (tests, linting, etc.)
2. **Code review** by maintainers
3. **Discussion** of implementation details if needed
4. **Approval** and merge by maintainers

### Review Criteria

- Code quality and style
- Test coverage
- Documentation updates
- Performance implications
- Backward compatibility
- Security considerations

## 🎯 Areas for Contribution

We especially welcome contributions in these areas:

- **Performance optimizations**
- **Additional callback hooks**
- **Enhanced error handling**
- **Testing utilities**
- **Documentation improvements**
- **Example applications**
- **Integration guides**

## 📞 Getting Help

If you need help or have questions:

- **GitHub Discussions** - For general questions and discussions
- **GitHub Issues** - For bug reports and feature requests
- **Code Review Comments** - For specific implementation questions

## 🏅 Recognition

Contributors will be recognized in:
- CHANGELOG.md for their contributions
- README.md acknowledgments
- GitHub contributor graphs

## 📜 Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to uphold this code.

## 📄 License

By contributing to ActionWebhook, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to ActionWebhook! 🎉
