# constructor

Sources: `src/periphery/BurnerLoansComposites.sol`, `IBurnerLoansCoreBound`,
Collateral/Debt interfaces and ERC-165. Constructor identities are immutable; deployment requires
compatible contracts and matching Core bindings. The migrator, swap adapter and flash lender are required. The explicit owner is nonzero and the executor starts disabled. See [enable](enable.md) for first enablement. No tokens move.
Address getters use SafeCallDecoder with at most 33 copied bytes; only an exact canonical
32-byte address is accepted. Any account may deploy. Failure deploys no executor; existing protocol state stays unchanged.

| ID | Caller | Dependency condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRECT-I01 | Deployer | Core is zero or has no code | `BurnerLoansComposites_InvalidDependency(core)` | No deployment | Covered: [test][test_whenCoreHasNoCode_reverts] |
| BLRECT-I02 | Deployer | Collateral is zero or has no code | `BurnerLoansComposites_InvalidDependency(collateral)` | No deployment | Covered: [test][test_whenCollateralHasNoCode_reverts] |
| BLRECT-I03 | Deployer | Debt lacks Debt interface | `BurnerLoansComposites_InvalidDependency(debt)` | No deployment | Covered: [test][test_whenActionDoesNotAdvertiseRequiredInterface_reverts] |
| BLRECT-I04 | Deployer | Collateral bound to another Core | `BurnerLoansComposites_InvalidDependency(collateral)` | No deployment | Covered: [test][test_whenCollateralHasWrongCore_reverts] |
| BLRECT-I05 | Deployer | Debt binding getter returns malformed ABI | `BurnerLoansComposites_InvalidDependency(debt)` | No deployment | Covered: [test][test_whenActionCoreBindingIsMalformed_reverts] |
| BLRECT-I06 | Deployer | Core without required interface, malformed OHM getter or OHM lacking code (separate tests) | `BurnerLoansComposites_InvalidDependency(core)` | No deployment | Covered: [test][test_whenCoreDoesNotAdvertiseItsInterface_reverts], [test][test_whenCoreOhmGetterIsMalformed_reverts], [test][test_whenCoreOhmHasNoCode_reverts] |
| BLRECT-I07 | Deployer | Collateral lacks its own or CoreBound interface, or its Core getter reverts or returns malformed or noncanonical data | `BurnerLoansComposites_InvalidDependency(collateral)` | No deployment | Covered: [test][test_whenActionDoesNotAdvertiseRequiredInterface_reverts], [test][test_whenActionCoreBindingGetterFails_reverts], [test][test_whenActionCoreBindingIsMalformed_reverts] |
| BLRECT-I08 | Deployer | Debt binding getter returns a valid address word plus 4096 trailing bytes | BurnerLoansComposites_InvalidDependency(debt) | No deployment; oversized return rejected | Covered: [test][test_whenDebtCoreGetterIsOversized_reverts] |
| BLRECT-I09 | Deployer | Debt binding getter returns the correct Core address with bit 160 set | BurnerLoansComposites_InvalidDependency(debt) | No deployment; noncanonical address rejected | Covered: [test][test_whenActionCoreBindingIsMalformed_reverts] |
| BLRECT-I10 | Deployer | Core OHM getter reverts with opaque data | BurnerLoansComposites_InvalidDependency(core) | No deployment; downstream error normalized | Covered: [test][test_whenCoreOhmGetterFails_reverts] |
| BLRECT-P01 | Deployer | Compatible Core/Collateral/Debt with same binding | Deploy | Version 1.0; correct ERC165/version/API identifiers; invalid ID unsupported | Covered: [test][test_whenConstructed] |
| BLRECT-P02 | Fuzz deployer | Compatible dependencies paused/inactive independently | Deploy | Readiness remains an operation-specific downstream check | Covered: [test][test_whenDependencyIsUnavailable] |
| BLRECT-I11 | Deployer | Migrator has no code or either asset getter returns malformed ABI | InvalidDependency(migrator) | No deployment | Covered: [test][test_whenMigratorHasNoCode_reverts], [test][test_whenMigratorGetterIsMalformed_reverts] |
| BLRECT-I12 | Deployer | Migrator assets are identical or either asset has no code | InvalidDependency(migrator) | No deployment | Covered: [test][test_whenMigratorAssetsAreIdentical_reverts], [test][test_whenMigratorAssetHasNoCode_reverts] |
| BLRECT-I13 | Deployer | Adapter or lender is a nonzero address without code | InvalidDependency(candidate) | No deployment | Covered: [test][test_whenAdapterHasNoCode_reverts], [test][test_whenLenderHasNoCode_reverts] |
| BLRECT-I14 | Deployer | Each integration is zero while the other two are valid | InvalidDependency(0) | No deployment | Covered: [test][test_whenAnyIntegrationIsZero_reverts] |
| BLRECT-I15 | Deployer | Adapter supports ERC-165 but omits the swap interface | InvalidDependency(adapter) | No deployment | Covered: [test][test_whenAdapterDoesNotSupportSwapInterface_reverts] |
| BLRECT-I16 | Deployer | Debt is zero or has no code | `BurnerLoansComposites_InvalidDependency(debt)` | No deployment | Covered: [test][test_whenDebtHasNoCode_reverts] |
| BLRECT-I17 | Deployer | Debt lacks its own or CoreBound interface, or its Core getter reverts or returns malformed or noncanonical data | `BurnerLoansComposites_InvalidDependency(debt)` | No deployment | Covered: [test][test_whenActionDoesNotAdvertiseRequiredInterface_reverts], [test][test_whenActionCoreBindingGetterFails_reverts], [test][test_whenActionCoreBindingIsMalformed_reverts] |
| BLREX-L07 | Deployer | Explicit nonzero owner | Deploy | Designated owner reported, starts disabled with zero transition timestamp, advertises IEnabler and IEnablerV2 | Covered: [test][test_whenDeployed] |
| BLREX-L08 | Deployer | Owner is zero | `OwnableInvalidOwner(0)` | No deployment | Covered: [test][test_whenOwnerIsZero_reverts] |

[test_whenCollateralHasWrongCore_reverts]: ./constructor.t.sol#L254
[test_whenDebtCoreGetterIsOversized_reverts]: ./constructor.t.sol#L288
[test_whenCoreOhmGetterFails_reverts]: ./constructor.t.sol#L300
[test_whenConstructed]: ./constructor.t.sol#L265
[test_whenCoreDoesNotAdvertiseItsInterface_reverts]: ./constructor.t.sol#L113
[test_whenCoreOhmGetterIsMalformed_reverts]: ./constructor.t.sol#L124
[test_whenCoreOhmHasNoCode_reverts]: ./constructor.t.sol#L131
[test_whenCoreHasNoCode_reverts]: ./constructor.t.sol#L142
[test_whenCollateralHasNoCode_reverts]: ./constructor.t.sol#L149
[test_whenDebtHasNoCode_reverts]: ./constructor.t.sol#L156
[test_whenActionDoesNotAdvertiseRequiredInterface_reverts]: ./constructor.t.sol#L163
[test_whenActionCoreBindingGetterFails_reverts]: ./constructor.t.sol#L192
[test_whenActionCoreBindingIsMalformed_reverts]: ./constructor.t.sol#L200
[test_whenDependencyIsUnavailable]: ./constructor.t.sol#L214
[test_whenMigratorHasNoCode_reverts]: ./constructor.t.sol#L22
[test_whenMigratorGetterIsMalformed_reverts]: ./constructor.t.sol#L30
[test_whenMigratorAssetsAreIdentical_reverts]: ./constructor.t.sol#L39
[test_whenMigratorAssetHasNoCode_reverts]: ./constructor.t.sol#L46
[test_whenAdapterHasNoCode_reverts]: ./constructor.t.sol#L56
[test_whenLenderHasNoCode_reverts]: ./constructor.t.sol#L72
[test_whenAnyIntegrationIsZero_reverts]: ./constructor.t.sol#L80
[test_whenAdapterDoesNotSupportSwapInterface_reverts]: ./constructor.t.sol#L64
[test_whenDeployed]: ./executeLifecycle.t.sol#L208
[test_whenOwnerIsZero_reverts]: ./executeLifecycle.t.sol#L229
