# Copilot Instructions for RideMetricX

## Pull Request Standards

### PR Title Format
**REQUIRED**: Always include issue number(s) in PR titles using the format:
- Single issue: `[#<issue-number>] <descriptive title>`
  - Example: `[#43] Implement app shell and navigation framework`
- Multiple issues: `[#<issue-1>, #<issue-2>] <descriptive title>`
  - Example: `[#31, #32] Add 3D model and camera controls`

### PR Body Requirements
- Include `Closes #<issue-number>` for each issue that will be resolved
- Reference any related issues that are not closed
- Summarize what was changed and why
- List test validation performed

## Pre-Commit Validation

Before creating commits or PRs, **always run**:
1. `flutter analyze` - ensure no linting errors
2. `flutter test` - ensure all tests pass
3. Platform-specific builds when code impacts that platform:
   - `flutter build windows --debug` (if Windows code changed)
   - `flutter build apk --debug` (if Android code changed)
   - `flutter build web` (if web code changed)

If any validation fails, fix the issues before committing.

## Code Quality Standards

- Follow Dart/Flutter style guidelines (`dart format`)
- Add tests for new functionality
- Update documentation when adding features
- Keep commits focused and atomic (one logical change per commit)
- Write clear commit messages: `<type>: <description>` (e.g., `feat: add suspension model`, `fix: resolve chart rendering bug`)

## Project Structure Awareness

This is a Flutter cross-platform app targeting:
- **Windows** (primary desktop platform)
- **Android** (mobile platform)
- **Web** (browser platform, new addition)

Key components (see [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)):
1. Data Collection & Import
2. Data Import Pipeline
3. Suspension Physics Model
4. Visualization Module
5. UI & Tuning Interface
6. Web Platform Support

## Issue Workflow

- Check issue dependencies before starting work
- Update issue status to "In Progress" when starting
- Mark issues as closed via PR (using `Closes #N` for each issue)
- For blocked issues, resolve dependencies first
- Multiple related issues can be addressed in a single PR when appropriate
