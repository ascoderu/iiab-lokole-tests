# Contributing to IIAB-Lokole Integration Tests

Thank you for helping improve the integration testing between Lokole and IIAB!

## How to Contribute

### Reporting Test Failures

If tests fail:
1. Check [existing issues](https://github.com/ascoderu/iiab-lokole-tests/issues)
2. Gather logs: `./scripts/analyze/collect-diagnostics.sh`
3. Create issue with:
   - Ubuntu version
   - Test scenario
   - Full error output
   - Diagnostic archive

### Adding New Tests

See [docs/ADDING_TESTS.md](docs/ADDING_TESTS.md) for detailed guide.

**Quick steps**:
1. Add verification script to `scripts/verify/`
2. Update relevant scenario in `scripts/scenarios/`
3. Test locally before PR
4. Document changes

### Improving Documentation

Documentation lives in `docs/`. PRs for typos, clarity improvements, or new guides are welcome!

### Code Style

**Bash scripts**:
- Use `#!/bin/bash`
- Include `set -e` for error handling
- Comment complex logic
- Use descriptive variable names

**Python scripts**:
- PEP 8 style
- Type hints where appropriate
- Docstrings for functions

## Development Workflow

1. **Fork and clone**:
   ```bash
   git clone --recursive https://github.com/youruser/iiab-lokole-tests.git
   ```

2. **Create feature branch**:
   ```bash
   git checkout -b feature/your-feature
   ```

3. **Make changes and test**:
   ```bash
   ./scripts/scenarios/fresh-install.sh --ubuntu-version 24.04
   ```

4. **Commit with clear messages**:
   ```bash
   git commit -m "feat: add verification for socket permissions"
   ```

5. **Push and create PR**

## Questions?

- **IIAB Community**: https://wiki.iiab.io/go/FAQ
- **GitHub Discussions**: [iiab-lokole-tests/discussions](https://github.com/ascoderu/iiab-lokole-tests/discussions)
