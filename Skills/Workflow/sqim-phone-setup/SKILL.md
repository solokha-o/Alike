---
name: sqim-phone-setup
description: Set up and deliver the Alike iOS app to the user's physical iPhone with SQIM. Use only when the user explicitly asks to set up, install, or push the app on/to their phone or iPhone. Do not use for ordinary build, run, test, share, simulator, deployment, or SQIM-information requests, even if SQIM is mentioned; never make SQIM a default build-completion step.
---

# SQIM Phone Setup

Install an Alike development build on the user's real iPhone through the SQIM CLI while preserving the repository's normal build and signing rules.

## Activation Gate

Proceed only when the request explicitly targets the user's physical phone, such as:

- "Set up the app on my phone."
- "Install Alike on my iPhone with SQIM."
- "Push this build to my phone."

Do not activate for:

- "Build/test/run Alike."
- "Upload or share a simulator build."
- "How does SQIM work?"
- "Add or change SQIM integration."

If the target could mean Simulator rather than a physical iPhone, ask one concise clarification before uploading.

## Workflow

1. Read [references/sqim-cli.md](references/sqim-cli.md) before invoking SQIM.
2. Check `command -v sqim` and `sqim --version`. Do not install or upgrade system software without the required user approval.
3. Run `sqim status --json`. If authentication is missing, run `sqim login` or `sqim login --no-browser` and let the user complete authentication. Never echo or persist login codes.
4. Verify that the iPhone has previously been paired with this Mac through Xcode and that development signing is available. The Alike project currently uses team `X8NNCQ3HW6`.
5. Preserve the repository build-completion gate. If the active task changed compilable source or build configuration, complete the required full app compile before the SQIM delivery step.
6. From the repository root, use the explicit Alike device command:

   ```sh
   sqim upload --device Alike --build --project Alike.xcodeproj --scheme Alike --team-id X8NNCQ3HW6 --allow-provisioning-updates
   ```

7. Treat only the final line from a successful command as the install URL. If the command fails, do not expose a partial or earlier URL; report the relevant failure and continue fixing safe, in-scope build or signing issues.
8. Return the successful HTTPS result as `[Install Alike on iPhone](https://...)` and state that the user should open it on the target iPhone.

## Guardrails

- Use `--device`; do not silently substitute a simulator or remote build.
- Do not upload an existing IPA unless the user explicitly identifies that artifact.
- Do not invent project, scheme, team, asset, or URL values.
- Do not run the vendor's `sqim setup all`; this repo-local skill intentionally has a narrower trigger than the bundled vendor skill.
- Do not upload if the user asks for local-only output or withdraws the phone-install request.
- Treat authentication codes, signing data, and tokenized install URLs as sensitive. Show the final install URL only in the user response and never write it to repo files or application logs.

## Logging Policy

When phone setup also requires Alike source changes for SQIM-related lifecycle handling, follow [references/logging-policy.md](references/logging-policy.md). CLI/build output remains terminal diagnostics and must not be copied into production `print` statements.

## Related Skills

- `Skills/SwiftConcurrency/ios-debugger-agent/SKILL.md`
- `Skills/GitFlow/ios-git-flow/SKILL.md`
- `Skills/Meta/skill-authoring-governance/SKILL.md`
