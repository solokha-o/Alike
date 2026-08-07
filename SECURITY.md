# Security Policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability or exposed credential. Email [oleksandr.solokha@gmail.com](mailto:oleksandr.solokha@gmail.com) with the affected commit, reproduction steps, expected impact, and any suggested mitigation.

Please avoid accessing other users' data, disrupting services, or publishing details before a fix is available. You can expect an acknowledgement within seven days.

## Credential handling

Alike does not accept real credentials in the repository. Keep App Store Connect, Apple signing, and App Review values in ignored local files or environment variables.

If a credential is committed, revoke or rotate it immediately, remove it from all reachable history, and notify maintainers privately.

## Supported versions

Security fixes target the latest code on `main`. Older versions may not receive separate patches.
