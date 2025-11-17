# Contributing to QNAP RTL8159 Driver Builder

Thank you for your interest in contributing!

## How to Contribute

### Reporting Bugs
1. Check if the bug has already been reported in [Issues](https://github.com/hooyao/qnap-rtl8159-driver/issues)
2. Create a new issue using the bug report template
3. Include your QNAP model, QTS/QuTS version, kernel version, and complete logs

### Suggesting Features
1. Check existing [Issues](https://github.com/hooyao/qnap-rtl8159-driver/issues) for similar requests
2. Create a new issue using the feature request template
3. Clearly describe the use case and benefit

### Submitting Pull Requests

#### Before You Start
1. Fork the repository
2. Create a new branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

#### Development Guidelines
1. **Test your changes**:
   - Build the Docker image successfully
   - Compile the driver without errors
   - Test QPKG creation
   - Test on actual QNAP hardware if possible

2. **Code style**:
   - Follow existing bash scripting conventions
   - Add comments for complex logic
   - Use meaningful variable names

3. **Documentation**:
   - Update README.md if you add new features
   - Add inline comments where necessary

4. **Commit messages**:
   - Use clear, descriptive commit messages
   - Follow conventional commits format:
     - `feat:` for new features
     - `fix:` for bug fixes
     - `docs:` for documentation changes
     - `refactor:` for code refactoring

#### Submitting Your PR
1. Push your branch to your fork
2. Create a pull request to the `main` branch
3. Fill out the PR template completely
4. Link any related issues
5. Wait for review and address feedback

## Development Setup

### Prerequisites
- Docker installed and running
- Git for version control
- Basic knowledge of bash scripting

### Building Locally
```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/qnap-rtl8159-driver.git
cd qnap-rtl8159-driver

# Build everything
./build.sh all

# Test with different driver versions
DRIVER_VERSION=2.18.0 ./build.sh all
```

## Community Guidelines
- Be respectful and inclusive
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Keep discussions professional and on-topic

## License
By contributing, you agree that your contributions will be licensed under the same license as the project (see [LICENSE](LICENSE)).

Thank you for contributing! 🙏
