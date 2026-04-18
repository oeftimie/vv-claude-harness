---
globs:
  - "**/*.env*"
  - "**/*.key"
  - "**/*.pem"
  - "**/*.ts"
  - "**/*.py"
  - "**/*.js"
  - "**/*.go"
---

# Security Awareness

## Secrets and Credentials
- NEVER commit secrets, API keys, tokens, passwords
- NEVER hardcode sensitive values
- Flag strings matching credential patterns
- Ask the user how to obtain credentials securely

## Environment Variables
- Reference by variable name; never hardcode values
- Add new vars to `.env.example` with placeholders
- NEVER create or modify actual `.env` files
- Document required env vars in README

## PII
- Flag potential PII in code
- Do not use real user data in tests
- Flag logging that might expose sensitive info
