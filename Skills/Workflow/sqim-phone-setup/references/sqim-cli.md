# SQIM CLI Reference

This reference was checked against the official SQIM CLI `0.2.4` and [sqim.dev](https://www.sqim.dev/) on 2026-07-16. Treat the installed CLI help as authoritative when versions differ.

## Installation and Authentication

- Official Homebrew package: `brew install milq-ai/tap/sqim`
- Login status: `sqim status --json`
- Browser login: `sqim login`
- Code-based login: `sqim login --no-browser`; complete authorization through
  the interactive flow and never pass a login code as a command argument.
- Credentials are stored by SQIM in the OS user configuration directory under `sqim/config.json`; never read or print that file.

The iPhone must have been connected to this Mac through Xcode at least once, and local development signing must work.

## Real-Device Uploads

Build, sign, and upload a project:

```sh
sqim upload --device PROJECT_PATH --build \
  --project APP.xcodeproj \
  --scheme SCHEME \
  --team-id TEAM_ID \
  --allow-provisioning-updates
```

Upload an explicitly supplied signed IPA:

```sh
sqim upload --device --ipa /path/to/App.ipa
```

Defaults are Debug, `iphoneos`, `generic/platform=iOS`, SQIM-managed export options, and automatic signing. Use `--workspace` only when the app builds from an `.xcworkspace`, and use `--configuration` only when Debug is not appropriate.

On success, the final output line is a Safari HTTPS install URL. Earlier or partial output is not a valid result.

## Diagnostics

Run the installed version's command help before changing arguments:

```sh
sqim help
sqim help upload
sqim help login
```

Preserve the relevant Xcode or signing error when upload exits nonzero. Do not surface tokenized URLs from failed runs.

## Out of Scope

This skill does not use simulator uploads or remote builds. SQIM supports them, but the user's trigger restriction limits this workflow to installing the app on a physical phone.
