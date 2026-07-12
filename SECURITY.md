# Security Policy

## Supported versions

Before rmp 1.0, security fixes are provided for the latest released minor version only. After 1.0,
the supported-version policy will be stated here for each release line.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability involving permanent data loss, protected
path bypasses, test-whitelist escapes, unsafe Trash cleanup, privilege handling, code signing, or
release-secret exposure.

Use the repository Security tab and its private vulnerability-reporting flow. If private reporting
is unavailable, contact the maintainer privately through the repository owner profile before public
disclosure.

Include:

- affected version or commit;
- reproduction conditions;
- paths, flags, filesystem, and volume type involved;
- whether a real Trash operation occurred;
- expected and actual behavior;
- impact and any known mitigation.

Reports should use synthetic data only. Never reproduce a report against `/`, a real home directory,
or user data.

## Response process

The maintainer will acknowledge the report, assess severity, prepare a regression test using the
project's fake filesystem or authorized test whitelist, and coordinate disclosure. Security releases
must pass the complete safety review and release gates in `docs/development.md`.
