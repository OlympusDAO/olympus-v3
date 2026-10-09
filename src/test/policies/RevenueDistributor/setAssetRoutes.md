# setAssetRoutes scenario plan

Scope: RD route creation, replacement and reactivation of a retired asset; distribution arithmetic belongs to [distribute](./distribute.md).

Co-located getters: before/after success or rejection, independently assert assetState, getAssetDistribution, assetDistributionHash and the full active set/count/indexes. Compare membership as a set because removal may reorder entries. Hash = keccak256(abi.encode(assetState, repurchaseBps, ordered routes, global yieldRecipient)). Fuzz getter callers without exclusions; getters remain readable while RD disabled/inactive. Route creation, replacement and retirement assertions include NeverListed defaults and empty/single/multiple membership.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin and the current nonzero config operator are separate permitted caller classes; revenue_distributor_admin alone grants no direct RD configuration authority. Fuzz unauthorized callers excluding every granted admin and the current operator; seed former operator, revenue admin, emergency and payout recipient. No dual-role case is required. Configuration guard order: nonReentrant, caller, local enabled, Kernel active, then inputs. Asset states are NeverListed, Active and Retired. BPS uses uint16 inputs and a wide total; the cap is 10,000. There is no explicit recipient-array cap. Positive BPS mathematically bounds recipients by 10,000 minus repurchaseBps, but execution is also limited by transaction gas; do not claim a 10,000-route call fits a supported chain budget.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: compare stored route and hash against independent abi.encode; active membership appears once; existing pending obligations and custody do not change; exactly one AssetDistributionSet with the supplied ordered routes.

## Authorization

Authorization is checked before RD lifecycle and route validation. For SAR-A03, independently fuzz RD Kernel state (active/inactive), RD local state (enabled/disabled), `asset_` (zero/EOA/contract), `repurchaseBps_` (0/10,000/`type(uint16).max`) and `routes_` (empty/valid/invalid). Exclude admin and the current nonzero config operator from the caller generator.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SAR-A01 | Admin | RD active/enabled; changed valid route | Success | Activate and store route | Covered: [evidence][test_givenAdmin], [full result][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute] |
| SAR-A02 | Current config operator | RD active/enabled; changed valid route | Success | Activate and store route | Covered: [evidence][test_updatesActiveSetAndHash], [route matrix][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute], [debt isolation][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt] |
| SAR-A03 | Any caller outside the permitted set, fuzz | Full authorization domain above | RevenueDistributor_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [evidence][test_whenUnauthorizedCallerConfiguresRoute_reverts], [revenue admin][test_givenRevenueDistributorAdmin_whenCallingDistributorDirectly_reverts], [full matrix][test_givenAnyLifecycleAndInputState_whenUnauthorizedCallerSetsRoute_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenRouteSet_reverts] |

## Lifecycle

For lifecycle rows, fuzz the current asset state, pending liabilities and all three function parameters across their valid and invalid domains; none may change the lifecycle error. Exercise admin and the current config operator separately.

| ID | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SAR-L01 | Active | Disabled | NotEnabled() | Unchanged | Covered: [evidence][test_givenDisabled_reverts], [full matrix][test_givenDisabled_whenPermittedCallerSetsAnyRoute_reverts] |
| SAR-L02 | Inactive | Enabled | RevenueDistributor_PolicyInactive() | Unchanged | Covered: [evidence][test_givenPolicyInactive_reverts], [full matrix][test_givenPolicyInactive_whenPermittedCallerSetsAnyRoute_reverts] |
| SAR-L03 | Inactive | Disabled | NotEnabled() before activity error | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenRouteSet_revertsNotEnabledFirst] |

## Valid routes

Exercise admin and the current config operator separately. The selected `asset_` is the asset whose RD route is created, replaced or reactivated; other supported or listed assets are unrelated and remain unchanged.

| ID | Prior asset state | `repurchaseBps_` | `routes_` and pending state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SAR-P01 | NeverListed | 0 | Empty | Success; Treasury receives future receipts | Active state; empty route; correct hash | Covered: [evidence][test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute] |
| SAR-P02 | NeverListed | 0 | Fuzz valid nonempty length 1..8; seed 1, 2, 5 and 8; fuzz positive total BPS 1..10,000 with seeds 1, 9,999 and 10,000. Eight is a representative bounded test length, not a protocol maximum | Success | Exact ordered route stored; one active membership; exact independent hash/event | Covered: [single route][test_updatesActiveSetAndHash], [five routes][test_givenFiveRecipients_distributesEachShare], [fuzz matrix][test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute], [boundary seeds][test_givenNeverListedAsset_whenBoundaryRecipientSetsConfigured_storesExactRoutes] |
| SAR-P03 | Active | Fuzz valid 0..10,000 | Empty or valid nonempty route; fuzz identical/changed replacement; pending configured/yield/Treasury debt independently present/absent | Success, including same-value replacement | No duplicate active entry; future route changes; every historical liability retains its assignment | Covered: [configured debt behavior][test_givenConfiguredPayoutPending_whenRouteChanges_thenOldRecipientKeepsAllocation], [debt and route matrix][test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt], [same route][test_givenActiveAsset_whenSameRouteSet_rewritesWithoutDuplicateMembership] |
| SAR-P04 | Retired | Fuzz valid 0..10,000 | Empty or valid nonempty route; old configured/yield/Treasury debt independently present/absent | Success | Retired becomes Active exactly once; old debts retained | Covered: [empty route][test_givenRetiredAssetWithPendingDebt_whenRouteSet_reactivatesAndPreservesDebt], [nonempty matrix][test_givenRetiredAssetWithAnyPendingBuckets_whenNonemptyRouteSet_reactivatesAndPreservesDebt] |
| SAR-P05 | NeverListed, Active or Retired | Fuzz 1..10,000; seed 1 and 10,000 | Selected yield recipient supports `asset_` as a direct vault share or enabled-vault underlying; configured routes keep total at or below 10,000 | Success | Store exact repurchase share and ordered routes; pending liabilities unchanged | Covered: [underlying seed][test_givenYieldRecipientUnderlyingSupported_whenRepurchaseRouteSet], [full matrix][test_givenCompatibleYieldRecipient_whenPositiveRepurchaseRouteSet_succeeds] |
| SAR-V01 | After any successful row, then optionally Retired | Any stored value | Empty/single/multiple active set; fuzz `getActiveAssetAt` over valid indexes and invalid 0 for empty, count, count+1 and MAX | Valid indexes return expected members; out-of-range Panic(0x32) | Getters do not mutate routes, debt, balances or events; remain available disabled/inactive | Covered: [single active seed][test_givenActiveAssets_whenIndexOutsideSet_reverts], [full matrix][test_givenEmptyOrMultipleAssets_whenGettersReadAcrossLifecycle_preservesState] |

## Invalid inputs

For these rows RD is active/enabled and every unspecified input is valid. Prior asset state and liabilities are independently fuzzed as NeverListed/Active/Retired and absent/present to prove rollback.

| ID | Caller | `asset_` kind | Repurchase BPS | Route recipient state | Route BPS state | Yield policy state | Asset/vault support | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SAR-I01 | Admin; current config operator separately | Fuzz zero/nonzero EOA | Valid | Valid, distinct | Valid total | Valid or unused | Compatible or unused | RevenueDistributor_InvalidAsset(asset) | Unchanged | Covered: [zero][test_whenZeroAssetConfigured_reverts], [EOA][test_whenEOAAssetConfigured_reverts], [full matrix][test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState] |
| SAR-I02 | Admin; current config operator separately | Contract | Valid | One is zero, RD, Kernel, current Treasury or current yield recipient | Valid total | Valid or unused | Compatible or unused | RevenueDistributor_InvalidRecipient(recipient) | Unchanged | Covered: [zero][test_whenZeroRecipientConfigured_reverts], [self][test_givenSelfRecipient_reverts], [Kernel][test_givenKernelRecipient_reverts], [Treasury][test_whenNamedRecipientIsTreasury_reverts], [yield recipient][test_whenNamedRecipientIsYieldRecipient_reverts], [full matrix][test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack] |
| SAR-I03 | Admin; operator separately | Contract | Valid | Valid, distinct | One route is zero | Valid or unused | Compatible or unused | RevenueDistributor_ZeroRecipientBasisPoints(recipient) | Unchanged | Covered: [zero BPS][test_whenRecipientBasisPointsAreZero_reverts], [full matrix][test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack] |
| SAR-I06 | Admin; operator separately | Contract | Valid | Duplicate at adjacent/non-adjacent indexes | Positive, valid total | Valid or unused | Compatible or unused | RevenueDistributor_DuplicateRecipient(recipient) | Unchanged | Covered: [adjacent seed][test_givenDuplicateConfiguredRecipients_reverts], [full matrix][test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack] |
| SAR-I04 | Admin; operator separately | Contract | 0 | Valid, distinct | Total 10,001 | Unused | Unused | RevenueDistributor_InvalidBasisPoints(10_001) | Unchanged | Covered: [seed][test_whenAssetRouteBasisPointsExceedMaximum_reverts], [full matrix][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack] |
| SAR-I13 | Admin; operator separately | Contract | 0 | Valid, distinct | One route uint16.max | Unused | Unused | RevenueDistributor_InvalidBasisPoints(uint16.max) | Unchanged; no narrow-integer wrap | Covered: [seed][test_whenMaximumUint16BasisPointsConfigured_reverts], [full matrix][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack] |
| SAR-I14 | Admin; operator separately | Contract | 10,001 | Valid or empty | Valid independently | Valid | Compatible | RevenueDistributor_InvalidBasisPoints(10_001) | Unchanged | Covered: [seed][test_whenRepurchaseBasisPointsExceedMaximum_reverts], [full matrix][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack] |
| SAR-I15 | Admin; operator separately | Contract | Individually valid | Valid, distinct | Individually valid; combined total 10,001 | Valid | Compatible | RevenueDistributor_InvalidBasisPoints(10_001) | Unchanged | Covered: [seed][test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts], [full matrix][test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack] |
| SAR-I16 | Admin; operator separately | Contract | 0 | Two valid, distinct recipients | Two uint16.max values | Unused | Unused | RevenueDistributor_InvalidBasisPoints(actual wide sum) | Unchanged; no uint16 wrap | Covered: [evidence][test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal] |
| SAR-I05 | Admin; operator separately | Contract | Positive | Valid or empty | Valid total | Pointer zero | None | RevenueDistributor_YieldRecipientUnavailable(address(0), asset) | Unchanged; checked before route BPS | Covered: [evidence][test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts] |
| SAR-I17 | Admin; current config operator separately | Contract | Positive | Valid or empty | Valid total | Active/enabled, interface-compatible | Fuzz no match, disabled direct vault, disabled underlying vault, reverting lookup without alternate match | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Unchanged | Covered: [disabled direct][test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts], [disabled underlying][test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts], [full matrix][test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack] |
| SAR-I07 | Admin; current config operator separately | Contract | Positive | Valid or empty | Valid total | Fuzz locally disabled/Kernel-inactive after selection | Any | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged; checked before route BPS or vault lookup | Covered: [locally disabled seed][test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts], [full matrix][test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs] |

[test_givenAdmin]: ./setAssetRoutes.t.sol#L120
[test_updatesActiveSetAndHash]: ./setAssetRoutes.t.sol#L308
[test_whenUnauthorizedCallerConfiguresRoute_reverts]: ./setAssetRoutes.t.sol#L98
[test_givenRevenueDistributorAdmin_whenCallingDistributorDirectly_reverts]: ./setAssetRoutes.t.sol#L420
[test_givenDisabled_reverts]: ./setAssetRoutes.t.sol#L166
[test_givenPolicyInactive_reverts]: ./setAssetRoutes.t.sol#L227
[test_givenFiveRecipients_distributesEachShare]: ./setAssetRoutes.t.sol#L438
[test_givenConfiguredPayoutPending_whenRouteChanges_thenOldRecipientKeepsAllocation]: ./setAssetRoutes.t.sol#L598
[test_givenYieldRecipientUnderlyingSupported_whenRepurchaseRouteSet]: ./setAssetRoutes.t.sol#L510
[test_whenZeroAssetConfigured_reverts]: ./setAssetRoutes.t.sol#L135
[test_whenEOAAssetConfigured_reverts]: ./setAssetRoutes.t.sol#L151
[test_whenZeroRecipientConfigured_reverts]: ./setAssetRoutes.t.sol#L387
[test_givenSelfRecipient_reverts]: ./setAssetRoutes.t.sol#L560
[test_givenKernelRecipient_reverts]: ./setAssetRoutes.t.sol#L576
[test_whenNamedRecipientIsTreasury_reverts]: ./setAssetRoutes.t.sol#L677
[test_whenNamedRecipientIsYieldRecipient_reverts]: ./setAssetRoutes.t.sol#L694
[test_whenRecipientBasisPointsAreZero_reverts]: ./setAssetRoutes.t.sol#L355
[test_givenDuplicateConfiguredRecipients_reverts]: ./setAssetRoutes.t.sol#L461
[test_whenAssetRouteBasisPointsExceedMaximum_reverts]: ./setAssetRoutes.t.sol#L338
[test_whenMaximumUint16BasisPointsConfigured_reverts]: ./setAssetRoutes.t.sol#L371
[test_whenRepurchaseBasisPointsExceedMaximum_reverts]: ./setAssetRoutes.t.sol#L631
[test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts]: ./setAssetRoutes.t.sol#L654
[test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L481
[test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L532
[test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute]: ./setAssetRoutes.t.sol#L715
[test_givenRetiredAssetWithPendingDebt_whenRouteSet_reactivatesAndPreservesDebt]: ./setAssetRoutes.t.sol#L739
[test_givenActiveAssets_whenIndexOutsideSet_reverts]: ./setAssetRoutes.t.sol#L822
[test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal]: ./setAssetRoutes.t.sol#L806
[test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts]: ./setAssetRoutes.t.sol#L764
[test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts]: ./setAssetRoutes.t.sol#L785
[test_givenPolicyInactiveAndDisabled_whenRouteSet_revertsNotEnabledFirst]: ./setAssetRoutes.t.sol#L267
[test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt]: ./setAssetRoutes.t.sol#L855
[test_givenActiveAsset_whenSameRouteSet_rewritesWithoutDuplicateMembership]: ./setAssetRoutes.t.sol#L912
[test_givenAnyLifecycleAndInputState_whenUnauthorizedCallerSetsRoute_reverts]: ./setAssetRoutes.t.sol#L24
[test_givenCompatibleYieldRecipient_whenPositiveRepurchaseRouteSet_succeeds]: ./setAssetRoutes.t.sol#L970
[test_givenDisabled_whenPermittedCallerSetsAnyRoute_reverts]: ./setAssetRoutes.t.sol#L176
[test_givenEmptyOrMultipleAssets_whenGettersReadAcrossLifecycle_preservesState]: ./setAssetRoutes.t.sol#L1004
[test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState]: ./setAssetRoutes.t.sol#L1065
[test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1161
[test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1188
[test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1093
[test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1134
[test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack]: ./setAssetRoutes.t.sol#L1233
[test_givenNeverListedAsset_whenBoundaryRecipientSetsConfigured_storesExactRoutes]: ./setAssetRoutes.t.sol#L845
[test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute]: ./setAssetRoutes.t.sol#L834
[test_givenPolicyInactive_whenPermittedCallerSetsAnyRoute_reverts]: ./setAssetRoutes.t.sol#L237
[test_givenRetiredAssetWithAnyPendingBuckets_whenNonemptyRouteSet_reactivatesAndPreservesDebt]: ./setAssetRoutes.t.sol#L925
[test_givenSeededUnauthorizedIdentities_whenRouteSet_reverts]: ./setAssetRoutes.t.sol#L74
[test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs]: ./setAssetRoutes.t.sol#L1265
