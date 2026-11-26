# setAssetRoutes scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: RD route creation, replacement and reactivation of a retired asset; distribution arithmetic belongs to [distribute](./distribute.md).

Co-located getters: before/after success or rejection, independently assert assetState, getAssetDistribution, assetDistributionHash and the full active set/count/indexes. Compare membership as a set because removal may reorder entries. Hash = keccak256(abi.encode(assetState, repurchaseBps, ordered routes, global yieldRecipient)). Fuzz getter callers without exclusions; getters remain readable while RD disabled/inactive. Route creation, replacement and retirement assertions include NeverListed defaults and empty/single/multiple membership.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin and the current nonzero config operator are separate permitted caller classes; revenue_distributor_admin alone grants no direct RD configuration authority. Fuzz unauthorized callers excluding every granted admin and the current operator; seed former operator, revenue admin, emergency and payout recipient. No dual-role case is required. Configuration guard order: nonReentrant, own Kernel activity, local enabled, caller authority, then inputs. Asset states are NeverListed, Active and Retired. BPS uses uint16 inputs and a wide total; the cap is 10,000. There is no explicit recipient-array cap. Positive BPS mathematically bounds recipients by 10,000 minus repurchaseBps, but execution is also limited by transaction gas; do not claim a 10,000-route call fits a supported chain budget.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: compare stored route and hash against independent abi.encode; active membership appears once; existing pending obligations and custody do not change; exactly one AssetDistributionSet with the supplied ordered routes.

## Authorization

Own Kernel activity and local enablement precede caller authorization and route validation. For SAR-A03, use active/enabled RD and independently fuzz `asset_` (zero/EOA/contract), `repurchaseBps_` (0/10,000/`type(uint16).max`) and `routes_` (empty/valid/invalid). Exclude admin and the current nonzero config operator from the caller generator.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SAR-A01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | RD active/enabled; changed valid route | Success | Activate and store route | Covered: [test][test_givenAdmin], [test][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute], [test][test_updatesActiveSetAndHash], [test][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute], [test][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt], [test][test_givenAdmin_AdminOnlySeed], [test][test_givenAdmin_OperatorOnlySeed], [test][test_givenAdmin_RolesOverlapSeed], [test][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_AdminOnlySeed], [test][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_RolesOverlapSeed], [test][test_updatesActiveSetAndHash_AdminOnlySeed], [test][test_updatesActiveSetAndHash_OperatorOnlySeed], [test][test_updatesActiveSetAndHash_RolesOverlapSeed], [test][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_AdminOnlySeed], [test][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_RolesOverlapSeed], [test][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_AdminOnlySeed], [test][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_OperatorOnlySeed], [test][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_RolesOverlapSeed] |
| SAR-A03 | Any caller outside the permitted set, fuzz | Active/enabled RD; full input domain above | RevenueDistributor_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [evidence][test_whenUnauthorizedCallerConfiguresRoute_reverts], [revenue admin][test_givenRevenueDistributorAdmin_whenCallingDistributorDirectly_reverts], [full matrix][test_givenPolicyActiveEnabledAndInputState_whenUnauthorizedCallerSetsRoute_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenRouteSet_reverts] |

## Lifecycle

For lifecycle rows, fuzz the current asset state, pending liabilities and all three function parameters across their valid and invalid domains; none may change the lifecycle error. Exercise admin and the current config operator separately.

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SAR-L01 | Fuzz permitted callers and unauthorized callers | true | false | NotEnabled() | Unchanged | Covered: [evidence][test_givenDisabled_reverts], [full matrix][test_givenDisabled_whenPermittedCallerSetsAnyRoute_reverts], [activity precedence][test_givenPolicyActiveDisabledAndInputState_whenUnauthorizedCallerSetsRoute_reverts] |
| SAR-L02 | Fuzz permitted callers and unauthorized callers | false | true | RevenueDistributor_PolicyNotActive(RD) | Unchanged | Covered: [evidence][test_givenPolicyInactive_reverts], [full matrix][test_givenPolicyInactive_whenPermittedCallerSetsAnyRoute_reverts], [activity precedence][test_givenPolicyInactiveAndInputState_whenUnauthorizedCallerSetsRoute_reverts] |
| SAR-L03 | Fuzz permitted callers and unauthorized callers | false | false | RevenueDistributor_PolicyNotActive(RD) before local enablement and caller checks | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenRouteSet_revertsActivityFirst], [activity precedence][test_givenPolicyInactiveAndInputState_whenUnauthorizedCallerSetsRoute_reverts] |

## Valid routes

Exercise admin and the current config operator separately. The selected `asset_` is the asset whose RD route is created, replaced or reactivated; other supported or listed assets are unrelated and remain unchanged.

| ID | Caller | Prior asset state | `repurchaseBps_` | `routes_` and pending state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SAR-P01 | ADMIN_ROLE holder | NeverListed | 0 | Empty | Success; Treasury receives future receipts | Active state; empty route; correct hash | Covered: [evidence][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute] |
| SAR-P02 | ADMIN_ROLE holder | NeverListed | 0 | Fuzz valid nonempty length 1..8; seed 1, 2, 5 and 8; fuzz positive total BPS 1..10,000 with seeds 1, 9,999 and 10,000. Eight is a representative bounded test length, not a protocol maximum | Success | Exact ordered route stored; one active membership; exact independent hash/event | Covered: [single route][test_updatesActiveSetAndHash], [five routes][test_givenFiveRecipients_distributesEachShare], [fuzz matrix][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute], [boundary seeds][test_givenNeverListedAsset_whenBoundaryRecipientSetsConfigured_storesExactRoutes] |
| SAR-P03 | ADMIN_ROLE holder | Active | Fuzz valid 0..10,000 | Empty or valid nonempty route; fuzz identical/changed replacement; pending configured/yield/Treasury debt independently present/absent | Success, including same-value replacement | No duplicate active entry; future route changes; every historical liability retains its assignment | Covered: [configured debt behavior][test_givenConfiguredPayoutPending_whenRouteChanges_thenOldRecipientKeepsAllocation], [debt and route matrix][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt], [same route][test_givenActiveAsset_whenSameRouteSet_rewritesWithoutDuplicateMembership] |
| SAR-P04 | ADMIN_ROLE holder | Retired | Fuzz valid 0..10,000 | Empty or valid nonempty route; old configured/yield/Treasury debt independently present/absent | Success | Retired becomes Active exactly once; old debts retained | Covered: [empty route][test_givenRetiredAssetWithPendingDebt_whenRouteSet_reactivatesAndPreservesDebt], [nonempty matrix][test_givenRetiredAssetWithAnyPendingBuckets_whenNonemptyRouteSet_reactivatesAndPreservesDebt] |
| SAR-P05 | ADMIN_ROLE holder | NeverListed, Active or Retired | Fuzz 1..10,000; seed 1 and 10,000 | Selected yield recipient supports `asset_` as a direct vault share or enabled-vault underlying; configured routes keep total at or below 10,000 | Success | Store exact repurchase share and ordered routes; pending liabilities unchanged | Covered: [underlying seed][test_givenYieldRecipientUnderlyingSupported_whenRepurchaseRouteSet], [full matrix][test_givenCompatibleYieldRecipient_whenPositiveRepurchaseRouteSet_succeeds] |
| SAR-P06 | Selected config operator | NeverListed | Positive | ERC7575 vault has a distinct share token equal to `asset_` | Success in validator and execution | Asset becomes Active | Covered: [separate share token][test_givenERC7575ShareToken_whenRepurchaseRouteSet] |
| SAR-V01 | ADMIN_ROLE holder | After any successful row, then optionally Retired | Any stored value | Empty/single/multiple active set; fuzz `getActiveAssetAt` over valid indexes and invalid 0 for empty, count, count+1 and MAX | Valid indexes return expected members; out-of-range Panic(0x32) | Getters do not mutate routes, debt, balances or events; remain available disabled/inactive | Covered: [single active seed][test_givenActiveAssets_whenIndexOutsideSet_reverts], [full matrix][test_givenEmptyOrMultipleAssets_whenGettersReadAcrossLifecycle_preservesState] |

## Invalid inputs

For these rows RD is active/enabled and every unspecified input is valid. Prior asset state and liabilities are independently fuzzed as NeverListed/Active/Retired and absent/present to prove rollback.

| ID | Caller | `asset_` kind | Repurchase BPS | Route recipient state | Route BPS state | Yield policy state | Asset/vault support | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SAR-I01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Fuzz zero/nonzero EOA | Valid | Valid, distinct | Valid total | Valid or unused | Compatible or unused | RevenueDistributor_InvalidAsset(asset) | Unchanged | Covered: [test][test_whenZeroAssetConfigured_reverts], [test][test_whenEOAAssetConfigured_reverts], [test][test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState], [test][test_whenZeroAssetConfigured_reverts_AdminOnlySeed], [test][test_whenZeroAssetConfigured_reverts_OperatorOnlySeed], [test][test_whenZeroAssetConfigured_reverts_RolesOverlapSeed], [test][test_whenEOAAssetConfigured_reverts_AdminOnlySeed], [test][test_whenEOAAssetConfigured_reverts_OperatorOnlySeed], [test][test_whenEOAAssetConfigured_reverts_RolesOverlapSeed], [test][test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_AdminOnlySeed], [test][test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_OperatorOnlySeed], [test][test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_RolesOverlapSeed] |
| SAR-I02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Valid | One is zero, RD, Kernel, current Treasury or current yield recipient | Valid total | Valid or unused | Compatible or unused | RevenueDistributor_InvalidRecipient(recipient) | Unchanged | Covered: [test][test_whenZeroRecipientConfigured_reverts], [test][test_givenSelfRecipient_reverts], [test][test_givenKernelRecipient_reverts], [test][test_whenNamedRecipientIsTreasury_reverts], [test][test_whenNamedRecipientIsYieldRecipient_reverts], [test][test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack], [test][test_whenZeroRecipientConfigured_reverts_AdminOnlySeed], [test][test_whenZeroRecipientConfigured_reverts_OperatorOnlySeed], [test][test_whenZeroRecipientConfigured_reverts_RolesOverlapSeed], [test][test_givenSelfRecipient_reverts_AdminOnlySeed], [test][test_givenSelfRecipient_reverts_OperatorOnlySeed], [test][test_givenSelfRecipient_reverts_RolesOverlapSeed], [test][test_givenKernelRecipient_reverts_AdminOnlySeed], [test][test_givenKernelRecipient_reverts_OperatorOnlySeed], [test][test_givenKernelRecipient_reverts_RolesOverlapSeed], [test][test_whenNamedRecipientIsTreasury_reverts_AdminOnlySeed], [test][test_whenNamedRecipientIsTreasury_reverts_OperatorOnlySeed], [test][test_whenNamedRecipientIsTreasury_reverts_RolesOverlapSeed], [test][test_whenNamedRecipientIsYieldRecipient_reverts_AdminOnlySeed], [test][test_whenNamedRecipientIsYieldRecipient_reverts_OperatorOnlySeed], [test][test_whenNamedRecipientIsYieldRecipient_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Valid | Valid, distinct | One route is zero | Valid or unused | Compatible or unused | RevenueDistributor_ZeroRecipientBasisPoints(recipient) | Unchanged | Covered: [test][test_whenRecipientBasisPointsAreZero_reverts], [test][test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack], [test][test_whenRecipientBasisPointsAreZero_reverts_AdminOnlySeed], [test][test_whenRecipientBasisPointsAreZero_reverts_OperatorOnlySeed], [test][test_whenRecipientBasisPointsAreZero_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I06 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Valid | Duplicate at adjacent/non-adjacent indexes | Positive, valid total | Valid or unused | Compatible or unused | RevenueDistributor_DuplicateRecipient(recipient) | Unchanged | Covered: [test][test_givenDuplicateConfiguredRecipients_reverts], [test][test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack], [test][test_givenDuplicateConfiguredRecipients_reverts_AdminOnlySeed], [test][test_givenDuplicateConfiguredRecipients_reverts_OperatorOnlySeed], [test][test_givenDuplicateConfiguredRecipients_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I04 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | 0 | Valid, distinct | Total 10,001 | Unused | Unused | RevenueDistributor_InvalidBasisPoints(10_001) | Unchanged | Covered: [test][test_whenAssetRouteBasisPointsExceedMaximum_reverts], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack], [test][test_whenAssetRouteBasisPointsExceedMaximum_reverts_AdminOnlySeed], [test][test_whenAssetRouteBasisPointsExceedMaximum_reverts_OperatorOnlySeed], [test][test_whenAssetRouteBasisPointsExceedMaximum_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I13 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | 0 | Valid, distinct | One route uint16.max | Unused | Unused | RevenueDistributor_InvalidBasisPoints(uint16.max) | Unchanged; no narrow-integer wrap | Covered: [test][test_whenMaximumUint16BasisPointsConfigured_reverts], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack], [test][test_whenMaximumUint16BasisPointsConfigured_reverts_AdminOnlySeed], [test][test_whenMaximumUint16BasisPointsConfigured_reverts_OperatorOnlySeed], [test][test_whenMaximumUint16BasisPointsConfigured_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I14 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | 10,001 | Valid or empty | Valid independently | Valid | Compatible | RevenueDistributor_InvalidBasisPoints(10_001) | Unchanged | Covered: [test][test_whenRepurchaseBasisPointsExceedMaximum_reverts], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack], [test][test_whenRepurchaseBasisPointsExceedMaximum_reverts_AdminOnlySeed], [test][test_whenRepurchaseBasisPointsExceedMaximum_reverts_OperatorOnlySeed], [test][test_whenRepurchaseBasisPointsExceedMaximum_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I15 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Individually valid | Valid, distinct | Individually valid; combined total 10,001 | Valid | Compatible | RevenueDistributor_InvalidBasisPoints(10_001) | Unchanged | Covered: [test][test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack], [test][test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_AdminOnlySeed], [test][test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_OperatorOnlySeed], [test][test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I16 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | 0 | Two valid, distinct recipients | Two uint16.max values | Unused | Unused | RevenueDistributor_InvalidBasisPoints(actual wide sum) | Unchanged; no uint16 wrap | Covered: [test][test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal], [test][test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_AdminOnlySeed], [test][test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_OperatorOnlySeed], [test][test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_RolesOverlapSeed] |
| SAR-I05 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Positive | Valid or empty | Valid total | Pointer zero | None | RevenueDistributor_YieldRecipientUnavailable(address(0), asset) | Unchanged; checked before route BPS | Covered: [test][test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts], [test][test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_AdminOnlySeed], [test][test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_OperatorOnlySeed], [test][test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_RolesOverlapSeed] |
| SAR-I17 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Positive | Valid or empty | Valid total | Active/enabled, interface-compatible | Fuzz no match, disabled direct vault, disabled underlying vault, reverting lookup without alternate match | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Unchanged | Covered: [test][test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts], [test][test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts], [test][test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack], [test][test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_AdminOnlySeed], [test][test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_OperatorOnlySeed], [test][test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_RolesOverlapSeed], [test][test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_AdminOnlySeed], [test][test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_OperatorOnlySeed], [test][test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_RolesOverlapSeed], [test][test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_AdminOnlySeed], [test][test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_RolesOverlapSeed] |
| SAR-I18 | Selected config operator | Contract | Positive | Valid or empty | Valid total | Active/enabled, interface-compatible | Vault address is neither shares nor underlying; noncanonical share/underlying words; return length other than 128 bytes, including legacy 96 bytes | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) in validator and execution | Route hash and active set unchanged | Covered: [wrong token][test_givenVaultIsNotShareToken_whenRepurchaseRouteSet_reverts], [address words][test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts], [maximum words][test_givenFourWordVaultConfig_whenAddressWordsAtMaximum_reverts], [lengths][test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts], [length seeds][test_givenVaultConfig_whenReturnLengthBoundaries_reverts] |
| SAR-I07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Contract | Positive | Valid or empty | Valid total | Fuzz locally disabled/Kernel-inactive after selection | Any | PolicyDependency_NotActive(recipient) | Unchanged; checked before route BPS or vault lookup | Covered: [test][test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts], [test][test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs], [test][test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_AdminOnlySeed], [test][test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_OperatorOnlySeed], [test][test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_RolesOverlapSeed], [test][test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_AdminOnlySeed], [test][test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_OperatorOnlySeed], [test][test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_RolesOverlapSeed] |

Retired duplicate caller IDs: SAR-A02, SAR-I08, SAR-I09, SAR-I10, SAR-I11, SAR-I12, SAR-I18, SAR-I19, SAR-I20, SAR-I21, SAR-I22, SAR-I23, SAR-I24. Retained caller families include explicit exclusive-role and overlapping-role seeds.

[test_givenAdmin]: ./setAssetRoutes.t.sol#L190
[test_updatesActiveSetAndHash]: ./setAssetRoutes.t.sol#L388
[test_whenUnauthorizedCallerConfiguresRoute_reverts]: ./setAssetRoutes.t.sol#L168
[test_givenRevenueDistributorAdmin_whenCallingDistributorDirectly_reverts]: ./setAssetRoutes.t.sol#L529
[test_givenDisabled_reverts]: ./setAssetRoutes.t.sol#L250
[test_givenPolicyInactive_reverts]: ./setAssetRoutes.t.sol#L309
[test_givenFiveRecipients_distributesEachShare]: ./setAssetRoutes.t.sol#L547
[test_givenConfiguredPayoutPending_whenRouteChanges_thenOldRecipientKeepsAllocation]: ./setAssetRoutes.t.sol#L734
[test_givenYieldRecipientUnderlyingSupported_whenRepurchaseRouteSet]: ./setAssetRoutes.t.sol#L630
[test_whenZeroAssetConfigured_reverts]: ./setAssetRoutes.t.sol#L207
[test_whenEOAAssetConfigured_reverts]: ./setAssetRoutes.t.sol#L229
[test_whenZeroRecipientConfigured_reverts]: ./setAssetRoutes.t.sol#L491
[test_givenSelfRecipient_reverts]: ./setAssetRoutes.t.sol#L684
[test_givenKernelRecipient_reverts]: ./setAssetRoutes.t.sol#L706
[test_whenNamedRecipientIsTreasury_reverts]: ./setAssetRoutes.t.sol#L823
[test_whenNamedRecipientIsYieldRecipient_reverts]: ./setAssetRoutes.t.sol#L846
[test_whenRecipientBasisPointsAreZero_reverts]: ./setAssetRoutes.t.sol#L447
[test_givenDuplicateConfiguredRecipients_reverts]: ./setAssetRoutes.t.sol#L570
[test_whenAssetRouteBasisPointsExceedMaximum_reverts]: ./setAssetRoutes.t.sol#L424
[test_whenMaximumUint16BasisPointsConfigured_reverts]: ./setAssetRoutes.t.sol#L469
[test_whenRepurchaseBasisPointsExceedMaximum_reverts]: ./setAssetRoutes.t.sol#L767
[test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts]: ./setAssetRoutes.t.sol#L795
[test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L596
[test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L651
[test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute]: ./setAssetRoutes.t.sol#L872
[test_givenRetiredAssetWithPendingDebt_whenRouteSet_reactivatesAndPreservesDebt]: ./setAssetRoutes.t.sol#L902
[test_givenActiveAssets_whenIndexOutsideSet_reverts]: ./setAssetRoutes.t.sol#L1002
[test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal]: ./setAssetRoutes.t.sol#L980
[test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L927
[test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts]: ./setAssetRoutes.t.sol#L954
[test_givenPolicyInactiveAndDisabled_whenRouteSet_revertsActivityFirst]: ./setAssetRoutes.t.sol#L347
[test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt]: ./setAssetRoutes.t.sol#L1040
[test_givenActiveAsset_whenSameRouteSet_rewritesWithoutDuplicateMembership]: ./setAssetRoutes.t.sol#L1102
[test_givenPolicyActiveEnabledAndInputState_whenUnauthorizedCallerSetsRoute_reverts]: ./setAssetRoutes.t.sol#L24
[test_givenCompatibleYieldRecipient_whenPositiveRepurchaseRouteSet_succeeds]: ./setAssetRoutes.t.sol#L1160
[test_givenDisabled_whenPermittedCallerSetsAnyRoute_reverts]: ./setAssetRoutes.t.sol#L259
[test_givenEmptyOrMultipleAssets_whenGettersReadAcrossLifecycle_preservesState]: ./setAssetRoutes.t.sol#L1194
[test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState]: ./setAssetRoutes.t.sol#L1253
[test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1361
[test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1392
[test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1285
[test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1330
[test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1441
[test_givenNeverListedAsset_whenBoundaryRecipientSetsConfigured_storesExactRoutes]: ./setAssetRoutes.t.sol#L1030
[test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute]: ./setAssetRoutes.t.sol#L1014
[test_givenPolicyInactive_whenPermittedCallerSetsAnyRoute_reverts]: ./setAssetRoutes.t.sol#L318
[test_givenRetiredAssetWithAnyPendingBuckets_whenNonemptyRouteSet_reactivatesAndPreservesDebt]: ./setAssetRoutes.t.sol#L1115
[test_givenSeededUnauthorizedIdentities_whenRouteSet_reverts]: ./setAssetRoutes.t.sol#L144
[test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs]: ./setAssetRoutes.t.sol#L1476
[test_givenAdmin_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1651
[test_givenAdmin_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1656
[test_givenAdmin_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1661
[test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1915
[test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1926
[test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1937
[test_updatesActiveSetAndHash_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2170
[test_updatesActiveSetAndHash_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2175
[test_updatesActiveSetAndHash_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2180
[test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1948
[test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1961
[test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1974
[test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1609
[test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1623
[test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1637
[test_whenZeroAssetConfigured_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2320
[test_whenZeroAssetConfigured_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2325
[test_whenZeroAssetConfigured_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2330
[test_whenEOAAssetConfigured_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2200
[test_whenEOAAssetConfigured_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2205
[test_whenEOAAssetConfigured_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2210
[test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1681
[test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1693
[test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1705
[test_whenZeroRecipientConfigured_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2335
[test_whenZeroRecipientConfigured_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2340
[test_whenZeroRecipientConfigured_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2345
[test_givenSelfRecipient_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2056
[test_givenSelfRecipient_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2061
[test_givenSelfRecipient_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2066
[test_givenKernelRecipient_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1900
[test_givenKernelRecipient_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1905
[test_givenKernelRecipient_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1910
[test_whenNamedRecipientIsTreasury_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2230
[test_whenNamedRecipientIsTreasury_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2235
[test_whenNamedRecipientIsTreasury_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2240
[test_whenNamedRecipientIsYieldRecipient_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2245
[test_whenNamedRecipientIsYieldRecipient_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2250
[test_whenNamedRecipientIsYieldRecipient_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2255
[test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1789
[test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1802
[test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1815
[test_whenRecipientBasisPointsAreZero_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2260
[test_whenRecipientBasisPointsAreZero_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2265
[test_whenRecipientBasisPointsAreZero_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2270
[test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1828
[test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1840
[test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1852
[test_givenDuplicateConfiguredRecipients_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1666
[test_givenDuplicateConfiguredRecipients_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1671
[test_givenDuplicateConfiguredRecipients_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1676
[test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1717
[test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1729
[test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1741
[test_whenAssetRouteBasisPointsExceedMaximum_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2185
[test_whenAssetRouteBasisPointsExceedMaximum_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2190
[test_whenAssetRouteBasisPointsExceedMaximum_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2195
[test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1753
[test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1765
[test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1777
[test_whenMaximumUint16BasisPointsConfigured_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2215
[test_whenMaximumUint16BasisPointsConfigured_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2220
[test_whenMaximumUint16BasisPointsConfigured_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2225
[test_whenRepurchaseBasisPointsExceedMaximum_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2290
[test_whenRepurchaseBasisPointsExceedMaximum_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2295
[test_whenRepurchaseBasisPointsExceedMaximum_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2300
[test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2275
[test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2280
[test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2285
[test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2305
[test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2310
[test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2315
[test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2137
[test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2148
[test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2159
[test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2104
[test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2115
[test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2126
[test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2071
[test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2082
[test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2093
[test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1864
[test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1876
[test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L1888
[test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_AdminOnlySeed]: ./setAssetRoutes.t.sol#L2023
[test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L2034
[test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2045
[test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_AdminOnlySeed]: ./setAssetRoutes.t.sol#L1987
[test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_OperatorOnlySeed]: ./setAssetRoutes.t.sol#L1999
[test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_RolesOverlapSeed]: ./setAssetRoutes.t.sol#L2011
[test_givenPolicyActiveDisabledAndInputState_whenUnauthorizedCallerSetsRoute_reverts]: ./setAssetRoutes.t.sol#L65
[test_givenPolicyInactiveAndInputState_whenUnauthorizedCallerSetsRoute_reverts]: ./setAssetRoutes.t.sol#L103
[test_givenERC7575ShareToken_whenRepurchaseRouteSet]: ./setAssetRoutes.t.sol#L2350
[test_givenVaultIsNotShareToken_whenRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L2377
[test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts]: ./setAssetRoutes.t.sol#L2392
[test_givenFourWordVaultConfig_whenAddressWordsAtMaximum_reverts]: ./setAssetRoutes.t.sol#L2416
[test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts]: ./setAssetRoutes.t.sol#L2430
[test_givenVaultConfig_whenReturnLengthBoundaries_reverts]: ./setAssetRoutes.t.sol#L2452
