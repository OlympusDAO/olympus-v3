---
name: licensing
description: Select and document licenses for new or changed Olympus files, imports, copied code, generated artifacts, and dependencies.
---

<!-- SPDX-FileCopyrightText: 2026 OlympusDAO -->
<!-- SPDX-License-Identifier: MIT -->

# Licensing

Read `LICENSING.md` and `THIRD_PARTY_NOTICES.md` before recommending or changing a license. Treat
this skill as engineering compliance guidance, not a substitute for counsel or rights-holder
confirmation.

## Select the file license

Classify ownership and provenance before considering the directory name.

| File or content | Default SPDX expression |
| --- | --- |
| Olympus protocol implementation, module, policy, deployable contract, or protocol-specific library | `AGPL-3.0-only` |
| Olympus-authored standalone interface, ABI, SDK helper, integration surface, or adoption-oriented production example | `MIT` |
| Wholly Olympus-authored test, mock, fixture, simulation, deployment or operations script, governance proposal, or non-production example | `Unlicense` |
| GPL- or AGPL-derived work | Exact inherited license and version choice |
| Third-party, copied, or adapted work | Exact upstream license, notices, grants, and provenance |
| Generated, audit, or vendor material | Preserve embedded notices; use `REUSE.toml` or a `.license` sidecar when inline metadata is unsuitable |

These are repository standards for Olympus-authored files. Before migrating an existing file,
inspect its introduction commit, substantive contributors, copied-code history, neighboring
provenance, and any assignment or consent evidence. Apply an explicit maintainer licensing decision
only to verified Olympus-authored work. Flag unresolved rights and preserve third-party terms.

## Place SPDX metadata

- Keep an executable script's shebang on line 1 and place SPDX comment lines immediately after it.
- Put SPDX HTML comments directly in authored Markdown. When Markdown begins with YAML frontmatter,
  keep the frontmatter first and place the SPDX comments immediately after its closing delimiter.
- Use `REUSE.toml` or a `.license` sidecar when inline comments are unsupported, would change how a
  structured file is parsed, or would modify generated, binary, audit, or vendor material.

## Imports, copying, and inheritance

- An import does not by itself change the importing file's license. Preserve and document the
  dependency's license and comply with distribution requirements.
- Copied or adapted source retains the upstream license and required copyright notices.
- Third-party interfaces retain the originating interface's license; the Olympus `MIT` interface
  default does not apply to them.
- An Olympus wrapper may use its own compatible license, but it never relicenses an inherited or
  copied base. Document the source-file boundary and the combined-artifact obligations.
- Do not assert license compatibility when copyleft, source-available, additional-use, or
  field-of-use terms overlap. Record the question for counsel or the rights holder.

## Add or update a dependency

Use primary upstream sources at the exact pinned revision. Record:

1. repository URL, version, and immutable revision;
2. files or components consumed and whether they are imported, copied, modified, generated, or
   inherited;
3. copyright holder and exact SPDX expression;
4. full license text, change date or change license, exceptions, and additional-use grants;
5. local modifications and production consumers; and
6. unresolved provenance or compatibility questions.

Update `THIRD_PARTY_NOTICES.md`. Add the applicable verbatim text under `LICENSES/` using its SPDX
identifier, or `LicenseRef-*` only when standard SPDX matching cannot accurately represent the
terms. Update `REUSE.toml` when the file cannot or should not carry inline metadata.

## Validate

- Validate every SPDX expression against the current SPDX License List.
- Run `reuse lint` when available; do not install it without approval.
- Run `pnpm run lint` for header or documentation changes.
- Review the final diff for accidental relicensing, removed notices, generated-file edits, and
  unsupported ownership or compatibility claims.
- Do not run a full build or protocol test suite for licensing-only changes without approval.
