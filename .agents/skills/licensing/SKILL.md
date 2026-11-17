---
name: licensing
description:
  Apply Olympus V3 SPDX license defaults when creating or modifying Solidity
  files, and review licenses across a branch or requested scope, including test
  interfaces, fixtures, templates and generators.
---

# Licensing

Use these defaults for new repository-owned Solidity files. File role and source
ownership determine the license; a neighboring file's header is not sufficient
evidence.

## Defaults

| File role                                                       | SPDX identifier |
| --------------------------------------------------------------- | --------------- |
| Implementation contracts and libraries                          | `AGPL-3.0-only` |
| Tests, mock implementations, fixtures and test helper libraries | `Unlicense`     |
| Interfaces, including test-only and mock interfaces             | `MIT`           |

Place exactly one `// SPDX-License-Identifier: <identifier>` comment on the
first line of each Solidity file. `Unlicense` is the public-domain license
identifier; `UNLICENSED` means no open-source license is specified. They are not
spelling variants. Avoid deprecated `AGPL-3.0` and malformed identifiers such as
`Unlicensed` or `MAGPL-3.0-only`.

SPDX applies to the whole file. Put an interface in a separate MIT-licensed file
when its test or mock implementation uses `Unlicense`; adding a second SPDX
comment cannot assign separate licenses to declarations in one file. Preserve
interface signatures and update imports when extracting it.

## Existing files and upstream code

- Preserve upstream licenses, copyright notices, license texts and provenance on
  copied or adapted code. Repository defaults do not authorize relicensing
  third-party code.
- Retain deliberate existing exceptions on repository utilities, shared
  API/constants files, proposals, and operational or deployment scripts unless
  license normalization is requested. Check the file's purpose, history and
  appropriate peers before choosing an exception for a new file.
- An ordinary functional edit does not authorize changing an existing license.
  For a licensing fix, follow the approved scope and defaults; flag unclear
  ownership or intent before changing that file. Do not narrow an explicit
  `-or-later` grant merely to make headers uniform.
- For an external protocol ABI, inspect its upstream interface, license,
  required methods and compiler pragma before reuse. Import a compatible pinned
  interface when dependencies are in scope. Otherwise use a minimal local ABI
  with an appropriate license and a pinned provenance reference; do not copy
  implementation code under the interface default.
- Do not add Solidity defaults to Markdown, configuration or other languages
  without a separate requirement. Preserve their existing licensing terms.

## Reviewing a branch or requested scope

Resolve the requested base and head to concrete revisions and record them.
Include task-owned working-tree changes when requested. Stay within the
requested review scope; review alone does not authorize edits, dependency
installation, rebases, commits or publication.

- Inventory added, modified and renamed surviving files. Exclude deleted files
  from current-header findings, and distinguish new deviations from inherited
  ones. After a rebase, refresh the inventory against the requested current base
  instead of reusing the earlier file list.
- Check license identifiers and retained notices. Scan actual interface
  declarations, including inline declarations in tests and mocks, rather than
  relying on filenames or `interfaces/` folders.
- Include fixtures, test helpers, proposal tests and code generators. Keep
  generated Solidity headers consistent with their generator templates, and
  align test-writing samples with the defaults.
- Report each deviation with its file and line, current header, expected license
  and applicable rule or upstream source. Explain deliberate exceptions. Do not
  classify every non-default existing header as a defect or claim that matching
  headers proves ownership or distribution compliance.

## Applying and validating fixes

Change headers and necessary interface imports only within the approved scope.
Preserve all other implementation and test behavior. Update a generator when its
output header changes.

Rescan the whole requested scope after fixes, including new or extracted
interfaces. For header-only edits, verify that the remainder of each file is
unchanged. For interface extraction, verify the signatures and run the affected
build/tests. Use repository formatting and lint commands appropriate to the
changed files; follow `AGENTS.md` for commit and publication gates.
