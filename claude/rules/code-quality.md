---
globs:
  - "**/*.ts"
  - "**/*.py"
  - "**/*.go"
  - "**/*.js"
  - "**/*.rb"
  - "**/*.java"
---

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

## Naming Conventions

Names MUST tell what code does, not how it's implemented or its history:
- NEVER use implementation details (e.g., "ZodValidator", "MCPWrapper", "JSONParser")
- NEVER use temporal context (e.g., "NewAPI", "LegacyHandler", "UnifiedTool")
- NEVER use pattern names unless they add clarity (prefer "Tool" over "ToolFactory")

Good names: `Tool` not `AbstractToolInterface`. `RemoteTool` not `MCPToolWrapper`. `Registry` not `ToolRegistryManager`. `execute()` not `executeToolWithValidation()`.

If you catch yourself writing "new", "old", "legacy", "wrapper", "unified", or implementation details: STOP and find a better name.

## Code Comments
- Comments MUST describe what the code does NOW
- NEVER write comments about: what it used to do, how it was refactored, what framework it uses
- NEVER remove comments unless you can PROVE they are actively false
