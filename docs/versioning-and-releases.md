# Versioning and releases

## Scope

This policy versions this repository's source, documentation, and source-only
delivery controls. It does not version a world save, a player's game client, a
SakuraFrp tunnel, the Palworld dedicated-server build, the official
documentation site, or the container image. Those identities must remain
separate in release notes and incident reports.

## Version format

Source releases use semantic versioning and annotated Git tags in the form
`vMAJOR.MINOR.PATCH`. The current public baseline is `v0.1.1`; future releases
must record their changes before tagging them.

- **MAJOR**: an incompatible operator workflow, configuration, REST/Web Console,
  runtime-switch, or data-layout change.
- **MINOR**: backwards-compatible functionality or a documented operational
  capability added to the source.
- **PATCH**: backwards-compatible fixes, documentation corrections, or static
  validation improvements.

Pre-release tags may use the standard suffix, such as `v0.1.0-rc.1`. A tag is
immutable: corrections require a new tag and a changelog entry.

## Required release record

Every tagged release must state all applicable identities separately:

| Identity | Required form |
|---|---|
| Repository source | Git tag and commit SHA |
| Container image | Full image digest |
| Palworld dedicated server | Exact runtime build reported by the server, if tested |
| Official documentation | Source URL and review date, if relied on |
| Runtime evidence | Date, scope, pass criteria, result, and recovery path |

Do not translate a successful build, a container start, a backup archive, or a
tunnel registration into a runtime acceptance claim.

## Release checklist

Before creating a public source release, the release owner must complete and
record the following:

1. Confirm the release scope, update `CHANGELOG.md`, and ensure no secret,
   player data, world save, backup, diagnostic log, or local endpoint is staged.
2. Run `./scripts/test-clean-checkout.ps1` and record its exit result. This is a
   source-only, disposable-data check; it does not start Docker.
3. Run `./scripts/verify-project.ps1`. If Docker is intentionally unavailable,
   use `-SkipDocker` and state that the Compose rendering check was skipped.
4. Review the compatibility contract and record any changed source, image, or
   game-server identity in the release notes.
5. Treat browser smoke tests, runtime switching, backup restore, tunnel access,
   and multiplayer stability as separate evidence. Only report those that were
   run in an approved maintenance window with the required recovery path.
6. Create an annotated `vMAJOR.MINOR.PATCH` tag from the reviewed commit, publish
   source checksums if release archives are attached, and keep the release notes
   aligned with the tag.

Artifact signing is not configured in this repository. Do not imply signed
provenance until a maintainer has chosen and documented a signing identity and
verification command.
