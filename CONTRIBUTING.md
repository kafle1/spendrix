# Contributing to Spendrix

Thank you for considering contributing to Spendrix! We welcome contributions from the community.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue with:
- A clear description of the problem
- Steps to reproduce the issue
- Expected vs actual behavior
- Screenshots if applicable
- Your environment (Flutter version, OS, device)

### Suggesting Features

We love new ideas! To suggest a feature:
- Open an issue with the "enhancement" label
- Describe the feature and its benefits
- Provide use cases if possible

### Code Contributions

1. **Fork the repository**
   ```bash
   git clone https://github.com/yourusername/spendrix.git
   cd spendrix
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Write clean, readable code
   - Follow Flutter/Dart style guidelines
   - Add comments for complex logic
   - Test your changes thoroughly

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

   Use conventional commit messages:
   - `feat:` for new features
   - `fix:` for bug fixes
   - `docs:` for documentation
   - `style:` for formatting changes
   - `refactor:` for code refactoring
   - `test:` for adding tests
   - `chore:` for maintenance tasks

5. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open a Pull Request**
   - Provide a clear description of changes
   - Reference any related issues
   - Ensure all tests pass

## Development Setup

1. Install Flutter (SDK 3.8.1 or higher)
2. Clone the repository
3. Run `flutter pub get`
4. Run `flutter run` to start the app

## Code Style

- Follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use `flutter analyze` to check for issues
- Format code with `flutter format .`

## Testing

- Test on both light and dark themes
- Test on different screen sizes
- Verify database operations work correctly
- Check for memory leaks and performance issues

## Questions?

Feel free to open an issue for any questions or reach out to the maintainers.

Thank you for contributing! 🎉
