# Security

> Verified: 2026-11-21 · Source: `8375cbb`

Report a vulnerability privately by email to `vk@tolkara.org` or through GitHub’s private vulnerability reporting for this repository. Do not open a public issue for a security problem.

Include the affected version, a minimal reproduction, and relevant device/OS information. Redact account information, credentials, signing identities, provisioning profiles, pairing records, and device identifiers.

Security reports are in scope when they affect parser memory safety, pairing-key confidentiality, the private Developer-service route, debugger detachment before guest entry, Local-signing page verification, or execution-mode boundaries. Gameplay automation, integrity bypasses, and game-code modification are not supported project work.

## This fork (TecN01R/wolkaraforever)

The contact above belongs to the upstream project. Report a problem there only if it also affects
[upstream WolkaraForever](https://github.com/jklock/wolkaraforever).

Code that exists only in this fork is unofficial and unsupported. Don't report it to the upstream
maintainers: they don't ship it. That code is the Built-in JIT helper (`wolkaraforever/JIT/`,
`wolkaraforever/JITHelper/`), the `09xx` patches, `duo/`, and the `duo-ipa`, `xtool-duo` and
`upstream-sync` workflows. The fork has no security contact; it's provided as is, without warranty.
