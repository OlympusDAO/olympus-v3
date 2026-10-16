# disableAssetRoutes scenario plan

Scope: retirement of RD routes. Pending debt remains available to [transferPendingPayout](./transferPendingPayout.md).

Co-located getters: before/after success or rejection, independently assert assetState, getAssetDistribution, assetDistributionHash and the full active set/count/indexes. Compare membership as a set because removal may reorder entries. Hash = keccak256(abi.encode(assetState, repurchaseBps, ordered routes, global yieldRecipient)). Fuzz getter callers without exclusions; getters remain readable while RD disabled/inactive. Route creation, replacement and retirement assertions include NeverListed defaults and empty/single/multiple membership.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin and the current nonzero config operator are separate permitted caller classes; revenue_distributor_admin alone grants no direct RD configuration authority. Fuzz unauthorized callers excluding every granted admin and the current operator; seed former operator, revenue admin, emergency and payout recipient. No dual-role case is required. Configuration guard order: nonReentrant, caller, local enabled, Kernel active, then inputs.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: Retired, route deleted, asset removed from active set, exact AssetDistributionDisabled event; all fixed and role debts/custody retained.

## Authorization

Authorization is checked before RD lifecycle and `asset_` activity. For DAR-A03, independently fuzz RD Kernel state (active/inactive), RD local state (enabled/disabled) and `asset_` state (zero, EOA, NeverListed, Active and Retired). Exclude admin and the current nonzero config operator from the caller generator.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| DAR-A01 | Admin | RD active/enabled; Active `asset_` | Success | Retire a nonempty route | Covered: [evidence][test_givenActiveAsset_whenAdminDisables_succeeds] |
| DAR-A02 | Current config operator | RD active/enabled; Active `asset_` | Success | Retire and clear route | Covered: [evidence][test_givenActiveAsset_whenDisabled_clearsRoute] |
| DAR-A03 | Any caller outside the permitted set, fuzz | Full authorization domain above | RevenueDistributor_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [full matrix][test_givenAnyLifecycleAndAssetState_whenUnauthorizedCallerDisables_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenAssetDisabled_reverts], [active seed][test_givenActiveAsset_whenUnauthorizedCallerDisables_reverts] |

## Lifecycle

For lifecycle rows, fuzz `asset_` across zero, EOA, NeverListed, Active and Retired; asset state must not change the lifecycle error. Exercise admin and the current config operator separately.

| ID | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| DAR-L01 | Active | Disabled | NotEnabled() | Unchanged | Covered: [full matrix][test_givenDisabled_whenPermittedCallerDisablesAnyAsset_reverts], [operator seed][test_givenDisabled_whenOperatorDisablesAsset_reverts] |
| DAR-L02 | Inactive | Enabled | RevenueDistributor_PolicyInactive() | Unchanged | Covered: [full matrix][test_givenPolicyInactive_whenPermittedCallerDisablesAnyAsset_reverts], [operator seed][test_givenPolicyInactive_whenOperatorDisablesAsset_reverts] |
| DAR-L03 | Inactive | Disabled | NotEnabled() before activity error | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenAssetDisabled_revertsNotEnabledFirst] |

## Behavior

| ID | Caller | Target asset state | Active-set state | Pending bucket mask | Pending amounts | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DAR-P01 | Admin; current config operator separately | Active | Any valid membership | Fuzz nonempty configured/yield/Treasury subset | Independent positive amounts | Success | Route clears and asset becomes Retired; every pending amount, recipient/token index and aggregate reserve is preserved; one disable event | Covered: [all bucket masks and callers][test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability], [integration seed][test_givenPendingConfiguredPayout_whenDisabled_preservesLiability] |
| DAR-P04 | Admin; current config operator separately | Active | At least two assets; target first/interior/last | Fuzz none/nonempty | Valid independent amounts | Success | Remove only `asset_`; remaining membership is correct as a set; target route clears and becomes Retired | Covered: [three positions and debt masks][test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets], [two-asset seed][test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership] |

## Invalid inputs

| ID | Caller | `asset_` kind | Asset state | Existing route/debt | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DAR-I01 | Admin; current config operator separately | Fuzz zero, EOA, never-listed token contract | NeverListed | None | RevenueDistributor_AssetNotActive(asset) | Unchanged | Covered: [token contract][test_givenNeverListedAsset_whenDisabled_reverts], [zero and EOA with caller parity][test_givenNeverListedAddress_whenPermittedCallerDisables_reverts] |
| DAR-I02 | Admin; current config operator separately | Listed token contract | Retired | Fuzz absent/present configured, yield and Treasury buckets | RevenueDistributor_AssetNotActive(asset) | Route remains deleted; retirement, debt, custody and indexes unchanged | Covered: [no debt][test_givenRetiredAsset_whenDisabledAgain_reverts], [all buckets and caller parity][test_givenRetiredAssetWithPendingBuckets_whenPermittedCallerDisablesAgain_reverts] |

[test_givenActiveAsset_whenAdminDisables_succeeds]: ./disableAssetRoutes.t.sol#L20
[test_givenActiveAsset_whenDisabled_clearsRoute]: ./disableAssetRoutes.t.sol#L53
[test_givenActiveAsset_whenUnauthorizedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L171
[test_givenDisabled_whenOperatorDisablesAsset_reverts]: ./disableAssetRoutes.t.sol#L191
[test_givenPolicyInactive_whenOperatorDisablesAsset_reverts]: ./disableAssetRoutes.t.sol#L263
[test_givenPendingConfiguredPayout_whenDisabled_preservesLiability]: ./disableAssetRoutes.t.sol#L519
[test_givenNeverListedAsset_whenDisabled_reverts]: ./disableAssetRoutes.t.sol#L350
[test_givenRetiredAsset_whenDisabledAgain_reverts]: ./disableAssetRoutes.t.sol#L395
[test_givenNeverListedAddress_whenPermittedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L367
[test_givenRetiredAssetWithPendingBuckets_whenPermittedCallerDisablesAgain_reverts]: ./disableAssetRoutes.t.sol#L418
[test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership]: ./disableAssetRoutes.t.sol#L450
[test_givenPolicyInactiveAndDisabled_whenAssetDisabled_revertsNotEnabledFirst]: ./disableAssetRoutes.t.sol#L310
[test_givenAnyLifecycleAndAssetState_whenUnauthorizedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L96
[test_givenSeededUnauthorizedIdentities_whenAssetDisabled_reverts]: ./disableAssetRoutes.t.sol#L145
[test_givenDisabled_whenPermittedCallerDisablesAnyAsset_reverts]: ./disableAssetRoutes.t.sol#L203
[test_givenPolicyInactive_whenPermittedCallerDisablesAnyAsset_reverts]: ./disableAssetRoutes.t.sol#L275
[test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets]: ./disableAssetRoutes.t.sol#L474
[test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability]: ./disableAssetRoutes.t.sol#L547
