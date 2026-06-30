# Code Quality Hard Limits

These are mechanical limits, not guidelines. Violating them is a bug.

## Function Size
- Maximum 100 lines per function/method (excluding blank lines and comments)
- If a function exceeds this, split it. No exceptions.

## Complexity
- Maximum cyclomatic complexity: 8 per function
- Maximum nesting depth: 4 levels
- If you need more nesting, extract a function

## Parameters
- Maximum 5 positional parameters per function
- Beyond 5, use an options object/dataclass/struct

## Line Length
- Maximum 100 characters per line
- URLs and string literals in tests are exempt

## Imports
- Use absolute imports only (no relative `..` paths)
- Exception: relative imports within the same package/module are acceptable in Python

## Warnings
- Zero warnings policy: every warning from every tool (linter, type checker, compiler) must be fixed
- Do not suppress warnings without a comment explaining why
- `# type: ignore`, `// @ts-ignore`, `# noqa` require a justification comment

## Dead Code
- No commented-out code blocks
- No unused imports, variables, or functions
- No TODO/FIXME comments older than the current feature scope
