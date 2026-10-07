<!-- SPDX-FileCopyrightText: 2026 OlympusDAO -->
<!-- SPDX-License-Identifier: MIT -->

# Licensing policy

This document records the repository's engineering policy for new work and its licensing
boundaries. It is not a claim that unrelated existing files have been relicensed and is not legal
advice.

## File-level licenses control

A file's SPDX declaration and preserved upstream notices control for that file. Repository-level
defaults do not override file-specific licenses, third-party terms, generated notices, or audit and
vendor material. The repository therefore has no blanket root `LICENSE` while those different terms
coexist.

For Olympus-authored files:

- Olympus-authored protocol implementations, modules, policies, deployable contracts, and
  protocol-specific libraries default to `AGPL-3.0-only`.
- Standalone public interfaces, ABI definitions, SDK and integration helpers, and deliberately
  adoption-oriented examples default to `MIT`.
- `GPL-3.0-only` is reserved for GPL-derived work or a deliberate choice of distribution-triggered
  copyleft without the AGPL network provision.
- Wholly Olympus-authored non-production files default to `Unlicense`. This includes tests, mocks,
  fixtures, simulations, deployment and operations scripts, governance proposals, and examples.
  The declaration is an intentional public-domain dedication, not a placeholder for missing terms.
- Third-party code retains its exact upstream license, copyright notice, additional-use grant, and
  provenance.
- Production contracts use `AGPL-3.0-only`; `-or-later` is retained only where inherited provenance
  requires it or it is explicitly approved.

The repository maintainer approved migrating verified Olympus-authored files to these standards.
Third-party, copied, adapted, and provenance-unresolved files retain their existing terms unless the
relevant rights holders authorize a change. Directory placement or non-production use alone is not
relicensing evidence.

## Integration boundary

The `MIT` default is an integration carve-out for deliberately reusable surfaces, not a default for
the protocol implementation behind them. An MIT interface may describe an AGPL implementation.
Likewise, an Olympus wrapper does not change the license of a third-party base contract that it
inherits or copies. The Chainlink CCIP boundary and other third-party cases are mapped in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## License identifiers and texts

`LICENSES/` contains standard texts for licenses actually used and exact customized third-party
terms that must accompany retained code. It does not retain unrelated repository-default licenses
or duplicate provenance evidence. Standard texts are taken from SPDX
license-list-data revision `5bf6d9610255540bfbee6890765a616042bf1e11` (list release
`e4c1f27`, dated 2026-07-16). `LicenseRef-*` files preserve customized upstream BUSL terms or
required grants that a generic SPDX identifier would not describe accurately.

`Unlicense` is a current SPDX license identifier and the default for the Olympus-authored
non-production categories above. Existing files using it retain that grant unless their rights
holders approve a different license.

SPDX marks `AGPL-3.0` as deprecated. This repository replaces that historical identifier according
to file ownership and purpose: Olympus production contracts use `AGPL-3.0-only`, Olympus-authored
interfaces use `MIT`, and Olympus-authored non-production files use `Unlicense`. Third-party
interfaces retain the originating project's license. `AGPL-3.0-or-later` remains only where the
applicable provenance expressly grants the later-version option. See the
[SPDX `AGPL-3.0` record](https://spdx.org/licenses/AGPL-3.0.html) and the current
[`AGPL-3.0-only` record](https://spdx.org/licenses/AGPL-3.0-only.html).

Commentable files generally carry inline SPDX license declarations. `REUSE.toml` supplies the
Olympus copyright fallback for source files that do not carry an inline copyright notice and uses
specific overrides for copied or adapted third-party components. It also annotates structured,
binary, and generated files that should not be edited inline. Standard texts use REUSE-compatible
names, and generated audit notices are mapped in the third-party sidecar.

## Contributions and relicensing

No CLA, copyright assignment, or equivalent blanket relicensing authority is documented in the
tracked repository. Commit history can establish provenance, but commit access or repository
ownership alone does not establish contributor consent. The repository maintainer explicitly
selected `AGPL-3.0-only`, `MIT`, and `Unlicense` for the verified Olympus-authored categories above.
Recording and applying that decision does not assert that contributor-consent or assignment
evidence was found.
