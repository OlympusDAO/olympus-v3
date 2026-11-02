# disableAssetRoutes scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: retirement of RD routes. Pending debt remains available to [transferPendingPayout](./transferPendingPayout.md).

Co-located getters: before/after success or rejection, independently assert assetState, getAssetDistribution, assetDistributionHash and the full active set/count/indexes. Compare membership as a set because removal may reorder entries. Hash = keccak256(abi.encode(assetState, repurchaseBps, ordered routes, global yieldRecipient)). Fuzz getter callers without exclusions; getters remain readable while RD disabled/inactive. Route creation, replacement and retirement assertions include NeverListed defaults and empty/single/multiple membership.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin and the current nonzero config operator are separate permitted caller classes; revenue_distributor_admin alone grants no direct RD configuration authority. Fuzz unauthorized callers excluding every granted admin and the current operator; seed former operator, revenue admin, emergency and payout recipient. No dual-role case is required. Configuration guard order: nonReentrant, own Kernel activity, local enabled, caller authority, then inputs.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: Retired, route deleted, asset removed from active set, exact AssetDistributionDisabled event; all fixed and role debts/custody retained.

## Authorization

Own Kernel activity and local enablement precede caller authorization and `asset_` activity. For DAR-A03, use active/enabled RD and independently fuzz `asset_` state (zero, EOA, NeverListed, Active and Retired). Exclude admin and the current nonzero config operator from the caller generator.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| DAR-A01 | ADMIN_ROLE holder | RD active/enabled; Active `asset_` | Success | Retire a nonempty route | Covered: [evidence][test_givenActiveAsset_whenAdminDisables_succeeds] |
| DAR-A02 | Current config operator | RD active/enabled; Active `asset_` | Success | Retire and clear route | Covered: [evidence][test_givenActiveAsset_whenDisabled_clearsRoute] |
| DAR-A03 | Any caller outside the permitted set, fuzz | Active/enabled RD; full input domain above | RevenueDistributor_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [full matrix][test_givenPolicyActiveEnabledAndAssetState_whenUnauthorizedCallerDisables_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenAssetDisabled_reverts], [active seed][test_givenActiveAsset_whenUnauthorizedCallerDisables_reverts] |

## Lifecycle

For lifecycle rows, fuzz `asset_` across zero, EOA, NeverListed, Active and Retired; asset state must not change the lifecycle error. Exercise admin and the current config operator separately.

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DAR-L01 | Fuzz permitted callers and unauthorized callers | true | false | NotEnabled() | Unchanged | Covered: [full matrix][test_givenDisabled_whenPermittedCallerDisablesAnyAsset_reverts], [operator seed][test_givenDisabled_whenOperatorDisablesAsset_reverts], [activity precedence][test_givenPolicyActiveDisabledAndAssetState_whenUnauthorizedCallerDisables_reverts] |
| DAR-L02 | Fuzz permitted callers and unauthorized callers | false | true | RevenueDistributor_PolicyNotActive(RD) | Unchanged | Covered: [full matrix][test_givenPolicyInactive_whenPermittedCallerDisablesAnyAsset_reverts], [operator seed][test_givenPolicyInactive_whenOperatorDisablesAsset_reverts], [activity precedence][test_givenPolicyInactiveAndAssetState_whenUnauthorizedCallerDisables_reverts] |
| DAR-L03 | Fuzz permitted callers and unauthorized callers | false | false | RevenueDistributor_PolicyNotActive(RD) before local enablement and caller checks | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenAssetDisabled_revertsActivityFirst], [activity precedence][test_givenPolicyInactiveAndAssetState_whenUnauthorizedCallerDisables_reverts] |

## Behavior

| ID | Caller | Target asset state | Active-set state | Pending bucket mask | Pending amounts | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DAR-P01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Active | Any valid membership | Fuzz nonempty configured/yield/Treasury subset | Independent positive amounts | Success | Route clears and asset becomes Retired; every pending amount, recipient/token index and aggregate reserve is preserved; one disable event | Covered: [test][test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability], [test][test_givenPendingConfiguredPayout_whenDisabled_preservesLiability], [test][test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability_AdminOnlySeed], [test][test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability_OperatorOnlySeed], [test][test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability_RolesOverlapSeed], [test][test_givenPendingConfiguredPayout_whenDisabled_preservesLiability_AdminOnlySeed], [test][test_givenPendingConfiguredPayout_whenDisabled_preservesLiability_OperatorOnlySeed], [test][test_givenPendingConfiguredPayout_whenDisabled_preservesLiability_RolesOverlapSeed] |
| DAR-P04 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Active | At least two assets; target first/interior/last | Fuzz none/nonempty | Valid independent amounts | Success | Remove only `asset_`; remaining membership is correct as a set; target route clears and becomes Retired | Covered: [test][test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets], [test][test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership], [test][test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets_AdminOnlySeed], [test][test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets_OperatorOnlySeed], [test][test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets_RolesOverlapSeed], [test][test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership_AdminOnlySeed], [test][test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership_OperatorOnlySeed], [test][test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership_RolesOverlapSeed] |

## Invalid inputs

| ID | Caller | `asset_` kind | Asset state | Existing route/debt | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DAR-I01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Fuzz zero, EOA, never-listed token contract | NeverListed | None | RevenueDistributor_AssetNotActive(asset) | Unchanged | Covered: [test][test_givenNeverListedAsset_whenDisabled_reverts], [test][test_givenNeverListedAddress_whenPermittedCallerDisables_reverts], [test][test_givenNeverListedAsset_whenDisabled_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenDisabled_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenDisabled_reverts_RolesOverlapSeed], [test][test_givenNeverListedAddress_whenPermittedCallerDisables_reverts_AdminOnlySeed], [test][test_givenNeverListedAddress_whenPermittedCallerDisables_reverts_OperatorOnlySeed], [test][test_givenNeverListedAddress_whenPermittedCallerDisables_reverts_RolesOverlapSeed] |
| DAR-I02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Listed token contract | Retired | Fuzz absent/present configured, yield and Treasury buckets | RevenueDistributor_AssetNotActive(asset) | Route remains deleted; retirement, debt, custody and indexes unchanged | Covered: [test][test_givenRetiredAsset_whenPendingBucketMaskVaries_reverts], [test][test_givenRetirementMembershipAndAmountSeeds] |

[test_givenActiveAsset_whenAdminDisables_succeeds]: ./disableAssetRoutes.t.sol#L19
[test_givenActiveAsset_whenDisabled_clearsRoute]: ./disableAssetRoutes.t.sol#L52
[test_givenActiveAsset_whenUnauthorizedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L236
[test_givenDisabled_whenOperatorDisablesAsset_reverts]: ./disableAssetRoutes.t.sol#L256
[test_givenPolicyInactive_whenOperatorDisablesAsset_reverts]: ./disableAssetRoutes.t.sol#L326
[test_givenPendingConfiguredPayout_whenDisabled_preservesLiability]: ./disableAssetRoutes.t.sol#L605
[test_givenNeverListedAsset_whenDisabled_reverts]: ./disableAssetRoutes.t.sol#L411

[test_givenNeverListedAddress_whenPermittedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L434

[test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership]: ./disableAssetRoutes.t.sol#L526
[test_givenPolicyInactiveAndDisabled_whenAssetDisabled_revertsActivityFirst]: ./disableAssetRoutes.t.sol#L371
[test_givenPolicyActiveEnabledAndAssetState_whenUnauthorizedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L95
[test_givenSeededUnauthorizedIdentities_whenAssetDisabled_reverts]: ./disableAssetRoutes.t.sol#L210
[test_givenDisabled_whenPermittedCallerDisablesAnyAsset_reverts]: ./disableAssetRoutes.t.sol#L267
[test_givenPolicyInactive_whenPermittedCallerDisablesAnyAsset_reverts]: ./disableAssetRoutes.t.sol#L337
[test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets]: ./disableAssetRoutes.t.sol#L556
[test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability]: ./disableAssetRoutes.t.sol#L636
Retired duplicate caller IDs: DAR-P02, DAR-P05, DAR-I03, DAR-I04. Retained caller families include explicit exclusive-role and overlapping-role seeds.

[test_givenRetiredAsset_whenPendingBucketMaskVaries_reverts]: ./disableAssetRoutes.t.sol#L962

[test_givenRetirementMembershipAndAmountSeeds]: ./disableAssetRoutes.t.sol#L1008

[test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability_AdminOnlySeed]: ./disableAssetRoutes.t.sol#L719

[test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability_OperatorOnlySeed]: ./disableAssetRoutes.t.sol#L734

[test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability_RolesOverlapSeed]: ./disableAssetRoutes.t.sol#L749

[test_givenPendingConfiguredPayout_whenDisabled_preservesLiability_AdminOnlySeed]: ./disableAssetRoutes.t.sol#L848

[test_givenPendingConfiguredPayout_whenDisabled_preservesLiability_OperatorOnlySeed]: ./disableAssetRoutes.t.sol#L859

[test_givenPendingConfiguredPayout_whenDisabled_preservesLiability_RolesOverlapSeed]: ./disableAssetRoutes.t.sol#L870

[test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets_AdminOnlySeed]: ./disableAssetRoutes.t.sol#L923

[test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets_OperatorOnlySeed]: ./disableAssetRoutes.t.sol#L936

[test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets_RolesOverlapSeed]: ./disableAssetRoutes.t.sol#L949

[test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership_AdminOnlySeed]: ./disableAssetRoutes.t.sol#L764

[test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership_OperatorOnlySeed]: ./disableAssetRoutes.t.sol#L775

[test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership_RolesOverlapSeed]: ./disableAssetRoutes.t.sol#L786

[test_givenNeverListedAsset_whenDisabled_reverts_AdminOnlySeed]: ./disableAssetRoutes.t.sol#L833

[test_givenNeverListedAsset_whenDisabled_reverts_OperatorOnlySeed]: ./disableAssetRoutes.t.sol#L838

[test_givenNeverListedAsset_whenDisabled_reverts_RolesOverlapSeed]: ./disableAssetRoutes.t.sol#L843

[test_givenNeverListedAddress_whenPermittedCallerDisables_reverts_AdminOnlySeed]: ./disableAssetRoutes.t.sol#L797

[test_givenNeverListedAddress_whenPermittedCallerDisables_reverts_OperatorOnlySeed]: ./disableAssetRoutes.t.sol#L809

[test_givenNeverListedAddress_whenPermittedCallerDisables_reverts_RolesOverlapSeed]: ./disableAssetRoutes.t.sol#L821

[test_givenPolicyActiveDisabledAndAssetState_whenUnauthorizedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L134

[test_givenPolicyInactiveAndAssetState_whenUnauthorizedCallerDisables_reverts]: ./disableAssetRoutes.t.sol#L170
