<!-- SPDX-FileCopyrightText: 2026 OlympusDAO -->
<!-- SPDX-License-Identifier: MIT -->

# Third-party notices and provenance

This document records source evidence and local boundaries; it does not replace the applicable
upstream terms or resolve license compatibility. File-level declarations and the verbatim texts in
`LICENSES/` control over this summary.

## Chainlink CCIP v1.6

| Field | Verified value |
| --- | --- |
| Upstream | `smartcontractkit/chainlink` |
| Pinned revision | `5dd09706665ee0073f8db7d5ec6e5c97eb44fb69` |
| Licensed work | Chainlink CCIP v1.6, copyright 2023 SmartContract Chainlink Limited SEZC |
| License | `LicenseRef-Chainlink-CCIP-1.6`, representing the exact pinned BUSL parameters and additional-use grant |
| Change date and license | 2028-11-01; MIT |
| Additional-use grant | Client libraries/example clients for CCIP integration, and token-pool contracts developed, deployed, and operated solely for CCIP integration and use |
| Preserved text | `LICENSES/LicenseRef-Chainlink-CCIP-1.6.txt` |

The exact pinned dependency is declared in both `foundry.toml` and `soldeer.lock`. Upstream
`TokenPool.sol` and `BurnMintTokenPoolAbstract.sol` use the customized BUSL terms, while
`CCIPReceiver.sol`, `IRouterClient.sol`, `Client.sol`, `Pool.sol`, `IPool.sol`, and
`ITypeAndVersion.sol` use MIT at that revision.

Local boundaries:

- `src/policies/bridge/BurnMintTokenPoolBase.sol` is a BUSL-licensed derivative of upstream
  `BurnMintTokenPoolAbstract.sol`. It replaces direct minting with the virtual `_mint` hook used by
  the Olympus policy. Its header uses the custom `LicenseRef-Chainlink-CCIP-1.6` identifier so REUSE
  resolves the exact pinned BUSL parameters and grant reproduced in `LICENSES/`; its Chainlink
  copyright notice is retained.
- `src/policies/bridge/CCIPBurnMintTokenPool.sol` is the Olympus MIT integration wrapper. It inherits the
  BUSL-derived base and upstream token-pool code. Repository tracing found no use of the CCIP-derived
  contracts outside CCIP token-pool integration. Developing, deploying, and operating token-pool
  contracts solely for CCIP integration and use is the activity expressly named by the pinned
  additional-use grant; this is an engineering reading of the text, not legal advice.
- `src/periphery/bridge/CCIPCrossChainBridge.sol` consumes upstream MIT client, receiver, and router
  surfaces rather than the BUSL token-pool base.
- `src/external/bridge/ICCIPClient.sol` reproduces MIT-licensed client structs and remains MIT.

The MIT wrapper does not relicense the inherited Chainlink code or the combined deployed artifact.
The combined artifact remains subject to the pinned BUSL terms, conspicuous-display requirement,
and additional-use grant until the applicable change date. No broader production use was found;
counsel or written Chainlink confirmation remains appropriate if the use or distribution model
changes.

Primary sources:

- Chainlink pin: <https://github.com/smartcontractkit/chainlink/tree/5dd09706665ee0073f8db7d5ec6e5c97eb44fb69>
- CCIP v1.6 license: <https://github.com/smartcontractkit/chainlink/blob/5dd09706665ee0073f8db7d5ec6e5c97eb44fb69/contracts/src/v0.8/ccip/LICENSE.md>
- Additional-use grant: <https://github.com/smartcontractkit/chainlink/blob/5dd09706665ee0073f8db7d5ec6e5c97eb44fb69/contracts/src/v0.8/ccip/v1.6-CCIP-License-grants.md>

## Axis/Bond Labs `CloneERC20`

| Field | Verified value |
| --- | --- |
| Local file | `src/external/clones/CloneERC20.sol` |
| Introduction commit | `25d631abad158b5f059bb4b5fd960c9150665fe8` |
| Cited upstream revision | `Axis-Fi/axis-core@8bbe4d48e2e512dff7b5aa7656c17f533112bbe6` |
| File license | `BSD-3-Clause` locally; upstream deliberately changed `AGPL-3.0-only` to bare `BSD` |
| SPDX precision | Olympus selected `BSD-3-Clause` for local SPDX normalization; Axis has not confirmed the variant |
| Axis repository default | Customized BUSL-1.1, which does not override this deliberate file-specific carve-out |
| Status | `BSD-3-Clause` applied; complete upstream copyright notice or confirmation remains recommended |

The local code matches the cited Axis file apart from the Solidity pragma, clone-library version,
formatting, and use of inherited `IERC20` event declarations. Axis commit
`2f6e9093364fa5b7e76c02ecfe6a068566ece317` deliberately changed the file header from
`AGPL-3.0-only` to `BSD`. That same license-update commit changed protocol files to BUSL and an
interface to MIT, which establishes `BSD` as the intentional file-specific license rather than a
typo or an application of the root BUSL license. The commit does not specify two-clause versus
three-clause terms or include a complete notice. Olympus has selected `BSD-3-Clause` for the local
SPDX declaration as directed by the repository maintainer; this records the local choice but does
not represent rights-holder confirmation of Axis's intended variant.

The file's comments also cite Solmate and Uniswap provenance. Those references explain source
influences but do not identify which BSD variant Axis intended.

Production consumers are:

`CloneERC20.sol` → `src/libraries/CloneableReceiptToken.sol` →
`src/policies/deposits/ReceiptTokenManager.sol`, which supplies receipt tokens to the convertible
deposit and redemption stack.

No code replacement is required merely because the Axis repository default is BUSL. Remaining
provenance options are:

1. obtain a short clarification from Axis/Bond Labs confirming the `BSD-3-Clause` mapping and
   supplying the complete copyright notice;
2. retain the local `BSD-3-Clause` mapping with the unresolved upstream precision clearly noted; or
3. replace or cleanly reimplement the component if a rights-holder-confirmed grant becomes a
   release requirement.

Primary sources:

- Axis file: <https://github.com/Axis-Fi/axis-core/blob/8bbe4d48e2e512dff7b5aa7656c17f533112bbe6/src/lib/clones/CloneERC20.sol>
- Axis root license: <https://github.com/Axis-Fi/axis-core/blob/8bbe4d48e2e512dff7b5aa7656c17f533112bbe6/LICENSE>
- Header-change commit: <https://github.com/Axis-Fi/axis-core/commit/2f6e9093364fa5b7e76c02ecfe6a068566ece317>

## Provable Things `Uint2Str`

| Field | Verified value |
| --- | --- |
| Local file | `src/libraries/Uint2Str.sol` |
| Introduction commit | `2c28d33e05a934b6752bd1ecb474458901eb300a` |
| Compared upstream revision | `provable-things/ethereum-api@c5c926eae55e2616729cc79df7d7d4e2e97d528f` |
| License | MIT |
| Copyright | 2015-2016 Oraclize SRL; 2016-2019 Oraclize LTD; 2019-2020 Provable Things Limited |

The function structure and conversion algorithm are copied/adapted from the cited upstream source,
with Solidity 0.8 updates and a later local arithmetic simplification. The former local “courtesy
of” comment did not preserve the upstream permission and disclaimer. The exact file-specific MIT
notice is restored in the source.

Primary source:

- Provable API source: <https://github.com/provable-things/ethereum-api/blob/c5c926eae55e2616729cc79df7d7d4e2e97d528f/contracts/solidity-v0.6.x/provableAPI_0.6.sol>

## Maker/Sky DAI-USDS migrator interface

| Field | Verified value |
| --- | --- |
| Local files | `src/interfaces/maker-dao/IDaiUsdsMigrator.sol`, `IERC3156FlashBorrower.sol`, and `IERC3156FlashLender.sol` |
| Olympus introduction | `e83f06d2dfb342e1f600cdfb0a0dc6a2088f99c0` on 2024-10-23 |
| Upstream | `sky-ecosystem/usds` |
| Compared revision | `1e91268374d2796abcbb1af2b75473b2af488265` on 2024-08-27 |
| Source | `src/DaiUsds.sol` |
| License | `AGPL-3.0-or-later` |
| Copyright | 2023 Dai Foundation |

The migrator interface is an ABI subset of the upstream `DaiUsds` contract. Its two events and two
conversion functions match exactly. Its `dai`, `daiJoin`, `usds`, and `usdsJoin` getters correspond
to the upstream contract's public immutable fields. Upstream initially introduced the converter as
`DaiNst.sol` in commit `c504166a52420362a4b37624fc19e0d2bb27285e`; commit
`9b90e8cbe7d1d7782df367a6292a4196c10bae12` added the `usr` function parameters and matching
two-address events; and commit `1e91268374d2796abcbb1af2b75473b2af488265` renamed it to
`DaiUsds.sol`. That last revision predates the Olympus interface and carries the Dai Foundation
copyright and `AGPL-3.0-or-later` declaration now restored locally.

The two ERC-3156 interfaces retain the Dai Foundation's complete `AGPL-3.0-or-later` file notices
from `sky-ecosystem/dss-flash@b884418182a48323374bd211bedc0a80749703ad`.

Production consumers are `src/policies/LoanConsolidator.sol` and
`src/periphery/CoolerV2Migrator.sol`.

Primary sources:

- Compared source: <https://github.com/sky-ecosystem/usds/blob/1e91268374d2796abcbb1af2b75473b2af488265/src/DaiUsds.sol>
- Signature and event change: <https://github.com/sky-ecosystem/usds/commit/9b90e8cbe7d1d7782df367a6292a4196c10bae12>
- Dai-to-USDS rename: <https://github.com/sky-ecosystem/usds/commit/1e91268374d2796abcbb1af2b75473b2af488265>
- Upstream license: <https://github.com/sky-ecosystem/usds/blob/1e91268374d2796abcbb1af2b75473b2af488265/LICENSE>
- ERC-3156 lender interface: <https://github.com/sky-ecosystem/dss-flash/blob/b884418182a48323374bd211bedc0a80749703ad/src/interface/IERC3156FlashLender.sol>
- ERC-3156 borrower interface: <https://github.com/sky-ecosystem/dss-flash/blob/b884418182a48323374bd211bedc0a80749703ad/src/interface/IERC3156FlashBorrower.sol>

## Uniswap v2 interfaces

`src/interfaces/Uniswap/IUniswapV2ERC20.sol` and `IUniswapV2Pair.sol` are adapted from
`Uniswap/v2-core@d2bfbb3649b265559bec74a7dd878dc1cf01c63c` (`v1.0.1`). The local files update the
compiler pragma, use explicit integer widths and inheritance, and retain only the pair functions
needed by Olympus. The upstream package declares `GPL-3.0-or-later`, which the local files use.

Primary sources:

- ERC-20 interface: <https://github.com/Uniswap/v2-core/blob/d2bfbb3649b265559bec74a7dd878dc1cf01c63c/contracts/interfaces/IUniswapV2ERC20.sol>
- Pair interface: <https://github.com/Uniswap/v2-core/blob/d2bfbb3649b265559bec74a7dd878dc1cf01c63c/contracts/interfaces/IUniswapV2Pair.sol>
- Package license declaration: <https://github.com/Uniswap/v2-core/blob/d2bfbb3649b265559bec74a7dd878dc1cf01c63c/package.json>

## Gnosis EasyAuction interface

`src/interfaces/IEasyAuction.sol` is an Olympus-adapted ABI subset of Gnosis EasyAuction at
`gnosis/ido-contracts@c9fd91f87d12aa1472d7b83015960286c00cf53f`, the latest upstream revision
before the interface was introduced locally. The upstream repository licenses EasyAuction under
`LGPL-3.0-only`; the local interface retains that license.

Primary sources:

- EasyAuction source: <https://github.com/gnosis/ido-contracts/blob/c9fd91f87d12aa1472d7b83015960286c00cf53f/contracts/EasyAuction.sol>
- Upstream license: <https://github.com/gnosis/ido-contracts/blob/c9fd91f87d12aa1472d7b83015960286c00cf53f/LICENSE>

## Bond Protocol interfaces and test dependencies

The root `src/interfaces/IBond*.sol` files and `src/test/lib/bonds/` were copied and updated from
`Bond-Protocol/bonds`, most recently against the upstream state immediately preceding Olympus commit
`fbfc2f5515466f0b8f575b7442754dd707e40741`. At upstream revision
`7197f68354863c7b9be604d637cbc9b62105704b`, interface files declare the deprecated `AGPL-3.0`
identifier and implementation files declare `AGPL-3.0-or-later`. The local interface declarations
use the current `AGPL-3.0-only` identifier; implementations retain `AGPL-3.0-or-later`. These copied
test dependencies retain the upstream licenses. The upstream repository is currently private, so
the exact revision may require repository access.

Primary sources:

- Bond Protocol revision: <https://github.com/Bond-Protocol/bonds/tree/7197f68354863c7b9be604d637cbc9b62105704b>
- Aggregator interface: <https://github.com/Bond-Protocol/bonds/blob/7197f68354863c7b9be604d637cbc9b62105704b/src/interfaces/IBondAggregator.sol>
- Aggregator implementation: <https://github.com/Bond-Protocol/bonds/blob/7197f68354863c7b9be604d637cbc9b62105704b/src/BondAggregator.sol>

## Other copied or adapted components

| Local component | Exact upstream revision | License and retained attribution |
| --- | --- | --- |
| `src/external/governance/` | [`compound-finance/compound-protocol@a3214f67b73310d547e00fc578e8355911c9d376`](https://github.com/compound-finance/compound-protocol/tree/a3214f67b73310d547e00fc578e8355911c9d376/contracts/Governance) | `BSD-3-Clause`; copyright 2020 Compound Labs, Inc.; locally modified |
| `src/interfaces/IPyth.sol` | [`pyth-network/pyth-sdk-solidity@7d8714298e082153ebc13b83364435079eb939e9`](https://github.com/pyth-network/pyth-sdk-solidity/blob/7d8714298e082153ebc13b83364435079eb939e9/IPyth.sol) | `Apache-2.0`; Pyth Data Association |
| `src/interfaces/morpho/IOracle.sol` | [`morpho-org/morpho-blue@cf3f0ce68db99421bcd808d505cfe49d61f4eaa0`](https://github.com/morpho-org/morpho-blue/blob/cf3f0ce68db99421bcd808d505cfe49d61f4eaa0/src/interfaces/IOracle.sol) | `GPL-2.0-or-later`; Morpho Labs |
| `src/policies/interfaces/price/IPriceOracle.sol`, `IERC7726Oracle.sol` | [`euler-xyz/euler-price-oracle@ffc3cb82615fc7d003a7f431175bd1eaf0bf41c5`](https://github.com/euler-xyz/euler-price-oracle/blob/ffc3cb82615fc7d003a7f431175bd1eaf0bf41c5/src/interfaces/IPriceOracle.sol) | `GPL-2.0-or-later`; Euler Labs |
| `src/libraries/FullMath.sol` | [`Uniswap/v3-core@4024732be626f4b4299a4314150d5c5471d59ed9`](https://github.com/Uniswap/v3-core/blob/4024732be626f4b4299a4314150d5c5471d59ed9/contracts/libraries/FullMath.sol) | `MIT`; copyright 2021 Remco Bloemen |
| `src/libraries/QuickSort.sol` | [Amxx gist revision `57157f63ba7d8eca0822b3f0c195dbbf091a6506`](https://gist.github.com/Amxx/d3a99fcb79abbe3c76a2f2a5773b3815/57157f63ba7d8eca0822b3f0c195dbbf091a6506) | `MIT`; Amxx |
| `src/libraries/Timestamp.sol` | [`bokkypoobah/BokkyPooBahsDateTimeLibrary@1dc26f977c57a6ba3ed6d7c53cafdb191e7e59ae`](https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/1dc26f977c57a6ba3ed6d7c53cafdb191e7e59ae/contracts/BokkyPooBahsDateTimeLibrary.sol) | `MIT`; copyright 2018-2019 BokkyPooBah / Bok Consulting Pty Ltd |
| `src/test/lib/solady/DynamicBufferLib.sol` | [`Vectorized/solady@4709550c4b7ae4bd6d65ff1c926799677a83f255`](https://github.com/Vectorized/solady/blob/4709550c4b7ae4bd6d65ff1c926799677a83f255/src/utils/DynamicBufferLib.sol), derived from [`samkingco/cozyco@75732113f480a62694264616883d7b2e0adc7267`](https://github.com/samkingco/cozyco/blob/75732113f480a62694264616883d7b2e0adc7267/contracts/utils/DynamicBuffer.sol) | `MIT`; Solady and cozyco contributors |
| `src/test/lib/zuniswapv2/` | [`Jeiwan/zuniswapv2@50fb69e95805970e9f0f118fc797b0a02f74f43e`](https://github.com/Jeiwan/zuniswapv2/tree/50fb69e95805970e9f0f118fc797b0a02f74f43e/src) | `Unlicense`; Ivan Kuznetsov |

## Balancer, Aura, and Lido components

The local Balancer tree contains selected interfaces and implementation libraries. Each file retains
the corresponding upstream declaration: `GPL-3.0-or-later` for the interfaces, `BalancerErrors`,
`VaultReentrancyLib`, `FixedPoint`, and `StableMath`; `MIT` for `BalancerReentrancyGuard`,
`LogExpMath`, and `Math`. The compact Aura integration interfaces in `IAura.sol` use Aura's MIT license.
`ILido.sol` reproduces the `stEthPerToken` surface from Lido's `WstETH.sol`; Lido declares
`GPL-3.0`, normalized locally to the current `GPL-3.0-only` identifier, and its copyright notice is
preserved.

Primary sources:

- Balancer v2 vault interface: <https://github.com/balancer/balancer-v2-monorepo/blob/e91a2b643a49856f51a648d175667c1b48cf3377/pkg/interfaces/contracts/vault/IVault.sol>
- Balancer implementation libraries: <https://github.com/balancer/balancer-v2-monorepo/tree/e91a2b643a49856f51a648d175667c1b48cf3377/pkg/solidity-utils/contracts>
- Aura contracts: <https://github.com/aurafinance/aura-contracts/tree/36599d53946aab701e2a1757e164261f49529399>
- Lido `WstETH.sol`: <https://github.com/lidofinance/core/blob/2da0f48f1a2a103a394dcf8760810fe9165697fb/contracts/0.6.12/WstETH.sol>

## Pigeon, LayerZero v1, and ENS Buffer

| Component | Exact revision | Local files | License evidence |
| --- | --- | --- | --- |
| Pigeon | `exp-table/pigeon@2edafae69fc70ed54411bbfd13ac5d10c9c8605b` | `src/test/lib/pigeon/layerzero/LayerZeroHelper.sol` | File and repository MIT; copyright 2022 asnared |
| LayerZero packet helper | Pigeon revision above; derived from `LayerZero-v1@3fb8f6962c1346eefa7e12f2cd8c299f0cfba944` | `src/test/lib/pigeon/layerzero/lib/LZPacket.sol` | `LicenseRef-LayerZero-BUSL-1.1` |
| LayerZero/ENS buffer | Same revisions; cites ENS Buffer | `src/test/lib/pigeon/layerzero/lib/Buffer.sol` | `BSD-2-Clause AND LicenseRef-LayerZero-BUSL-1.1` |

Repository commit `02cc40b7677f3ba04b6f64b9c20aa6eb2961bbb8` introduced the three files.
The only consumer is the deprecated test
`src/test/deprecated/policies/CrossChainBridgeFork.t.sol`; no production contract or current test
imports them.

The former `pigeonlabs/Pigeon` source moved to `exp-table/pigeon`; the exact cited commit remains
reachable there. `LayerZeroHelper.sol` is Pigeon-authored MIT code. Pigeon's `LZPacket.sol` and
`Buffer.sol` are modified copies of LayerZero v1 sources. The exact LayerZero versions preceding
the Pigeon import are at revision `3fb8f6962c1346eefa7e12f2cd8c299f0cfba944`. Both upstream files
carry `BUSL-1.1`; Pigeon retained it on `LZPacket.sol` but omitted it from `Buffer.sol`. The buffer
also retains ENS's BSD-2-Clause provenance. The local expressions select the exact customized
LayerZero terms through `LicenseRef-LayerZero-BUSL-1.1`.

LayerZero v1 moved from `LayerZero-Labs/LayerZero` to the archived
`LayerZero-Labs/LayerZero-v1` repository. Its root BUSL license at revision
`bcb84407c44a561c97e4e43e04de00e17bc06ac9` is identical to
`LayerZero-Labs/license@413effb9ccb031403febb98fac95688bc7c453bc/LICENSE-BUSL-1.1`. It
identifies LayerZero Labs Ltd, LayerZero Protocol copyright 2022, and a 2025-02-01 change date, but
omits both the Change License and Additional Use Grant parameter lines referenced by the template.
The v1 repository has only that one `LICENSE` history entry, and the later license repository has
only one history entry for `LICENSE-BUSL-1.1`; neither supplies the missing parameter. The separate
`LICENSE-LZBL-1.1` names GPL-2.0-or-later as its change license, but defines its Licensed Work as the
Delta Zero algorithm rather than the LayerZero v1 Protocol, so it does not resolve the v1 omission.
A passed change date alone therefore does not identify the successor license. The canonical BUSL
1.1 text requires a named Change License and says that the post-change rights arise under that
license; it does not supply a default when the parameter is absent. Current official LayerZero
documentation describes v1 as deprecated and provides it only for legacy integrations, but the
official repository, license repository, and documentation searches found no v1 successor-license
clarification. `Buffer.sol` contains both the cited ENS source and LayerZero modifications, so both
licenses and copyright notices are retained unless LayerZero clarifies the missing Change License.

The deprecated fork test and its helper tree are retained. The Olympus-authored test keeps its
existing `Unlicense`; that declaration does not override the imported helper licenses.

The standard `MIT` and `BSD-2-Clause` texts and the customized
`LICENSES/LicenseRef-LayerZero-BUSL-1.1.txt` terms are retained. Separate Pigeon and ENS
`LicenseRef` copies were removed because their file-specific notices plus the standard license
texts are sufficient; they were duplicate provenance evidence rather than distinct licenses.

Recommended treatment while the parameter remains unavailable: keep these helpers isolated to the
deprecated non-production fork test, preserve the original customized BUSL text, and do not claim
that the passed date converted the LayerZero-derived portions to MIT or GPL. If an identified
open-source successor becomes necessary for distribution, obtain written LayerZero clarification
or cleanly reimplement the two helpers while preserving the test.

Primary sources:

- Pigeon tree: <https://github.com/exp-table/pigeon/tree/2edafae69fc70ed54411bbfd13ac5d10c9c8605b/src/layerzero>
- Pigeon license: <https://github.com/exp-table/pigeon/blob/2edafae69fc70ed54411bbfd13ac5d10c9c8605b/LICENSE>
- LayerZero packet source: <https://github.com/LayerZero-Labs/LayerZero-v1/blob/3fb8f6962c1346eefa7e12f2cd8c299f0cfba944/contracts/proof/utility/LayerZeroPacket.sol>
- LayerZero buffer source: <https://github.com/LayerZero-Labs/LayerZero-v1/blob/3fb8f6962c1346eefa7e12f2cd8c299f0cfba944/contracts/proof/utility/Buffer.sol>
- LayerZero v1 root license: <https://github.com/LayerZero-Labs/LayerZero-v1/blob/bcb84407c44a561c97e4e43e04de00e17bc06ac9/LICENSE>
- LayerZero license repository: <https://github.com/LayerZero-Labs/license/blob/413effb9ccb031403febb98fac95688bc7c453bc/LICENSE-BUSL-1.1>
- Separate Delta Zero LZBL license: <https://github.com/LayerZero-Labs/license/blob/413effb9ccb031403febb98fac95688bc7c453bc/LICENSE-LZBL-1.1>
- LayerZero v1 deprecation notice: <https://docs.layerzero.network/v1/deployments/deployed-contracts>
- Canonical BUSL 1.1 terms: <https://mariadb.com/bsl11/>
- ENS Buffer source: <https://github.com/ensdomains/buffer/blob/9fc910f5e5d58839553be890948b9e22d3c7bc13/contracts/Buffer.sol>

## Solidity Metrics helper

`shell/metrics.js` identifies `github.com/tintinweb` as its author, declares MIT, and says it is
based on the Solidity Metrics CLI and VS Code extension. The repository introduced the helper at
commit `0cb84452159a1f200d2991fb12c54dc4d2de2ebd` on 2024-10-14. The latest upstream revisions before
that introduction were `ConsenSysDiligence/solidity-metrics@412fc666e598cd8a7c78a37cd79a133a46cff684`
and `ConsenSysDiligence/vscode-solidity-metrics@f3448c8f41b2ca18ace361d7f063f68f98587942`;
both relevant source files declare MIT, which the local file retains.

Primary sources:

- Solidity Metrics CLI: <https://github.com/ConsenSysDiligence/solidity-metrics/blob/412fc666e598cd8a7c78a37cd79a133a46cff684/src/cli.js>
- VS Code extension: <https://github.com/ConsenSysDiligence/vscode-solidity-metrics/blob/f3448c8f41b2ca18ace361d7f063f68f98587942/src/extension.js>

## Generated Solidity Metrics reports

The nine tracked `audit/*/solidity-metrics.html` reports are generated artifacts and remain
unmodified. Each report embeds:

- Solidity Metrics generator: copyright 2017 Chris Patuzzo, MIT;
- Viz.js 1.8.2: copyright 2014-2018 Michael Daines, MIT;
- Graphviz 2.40.1: Eclipse Public License 1.0;
- Expat 2.2.5: copyright 1998-2000 Thai Open Source Software Center and Clark Cooper, and
  2001-2006 Expat maintainers, MIT; and
- zlib: copyright 1995-2013 Jean-loup Gailly and Mark Adler, zlib license.

The corresponding standard texts are retained under `LICENSES/`. This sidecar mapping is metadata
only; it does not replace or remove the notices embedded in each generated report.
