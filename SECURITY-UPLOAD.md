# Safe source snapshot

This snapshot excludes local Git history, environment files, private credentials, user data, dependencies, caches and generated distribution packages. Original source directories were not modified. A local secret scan is required before upload. This is not a complete application security audit or a claim of release readiness.

For future commits, install Gitleaks and run `git config core.hooksPath .githooks` in this checkout. The hook scans staged changes with values redacted. Never commit production credentials, personal records, database exports or signing keys. Configure credentials in the environment or system keychain.
