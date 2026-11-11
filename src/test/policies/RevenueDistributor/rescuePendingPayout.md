# RevenueDistributor.rescuePendingPayout scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

RD = RevenueDistributor. This plan covers pending rescue, its preview and corresponding getters. Existing suite: [rescuePendingPayout.t.sol](./rescuePendingPayout.t.sol). Grouped tests and their deterministic boundary drivers are mapped below.

Pending-rescue preview requires Kernel activity, remains permissionless and works while RD is locally disabled. It does not predict token delivery failures.

Local disablement retains admin/current operator recovery. A disabled timelock blocks its queues and execution; admin can call RD directly. Kernel inactivity still rejects execution.

## Domains and notation

Normalized scenario scope: `RD-PENDING-RESCUE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

- Caller classes: admin and current nonzero configOperator, tested separately. Fuzz unauthorized callers excluding every actual admin and current nonzero operator; seed revenue_distributor_admin-only, emergency-only, former operator and payout recipient.
- RD lifecycle: Kernel-active/inactive independently of locally enabled/disabled. Pending rescue is allowed while disabled, but preview and execution require Kernel activity.
- Asset listing state: Active and Retired are both required for every compatible allocation, invalid-input, numeric, transfer and callback case. NeverListed normally has no pending entitlement; its positive-request rejection is covered separately.
- Fixed identities: configuredRecipient = original owner of fixed route debt; yieldRecipient = current repurchase destination, falling back to Treasury when unset; Treasury = cached TRSRY. Select originalRecipient from each distinct role identity and an unrelated identity.
- Use fixed addresses, construct overlaps explicitly, and vary identity/presence independently of amount. Fuzz unauthorized callers and meaningful numeric inputs; co-locate permissionless preview checks with those action cases. A caller role or destination classification must not incorrectly exclude an originalRecipient holding reachable debt.

| Layout | Identity relationship |
| --- | --- |
| Distinct | configuredRecipient, yieldRecipient and Treasury distinct |
| Route/Yield | configuredRecipient=yieldRecipient, distinct from Treasury |
| Route/Treasury | configuredRecipient=Treasury, distinct from yieldRecipient |
| Yield/Treasury | yieldRecipient=Treasury, distinct from configuredRecipient |
| All overlap | configuredRecipient=yieldRecipient=Treasury |

Construct overlap through supported role/routing/Treasury changes where initial route validation forbids that configuration.

| Bucket | Raw recorded liability | Eligibility for selected originalRecipient |
| --- | --- | --- |
| Asset route | Fixed-address configured distribution | Only the liability stored at originalRecipient, including former route recipients |
| Repurchase | Global pending yield-recipient liability | Only when originalRecipient is current yieldRecipient, including Treasury fallback |
| Treasury | Global pending Treasury liability | Only when originalRecipient is current Treasury |

In formulas, `assetRoute`, `repurchase`, `treasury` mean eligible amounts for the selected originalRecipient; `entitlement=assetRoute+repurchase+treasury`. Globally populated but ineligible buckets never enlarge entitlement. Enumerate all eight global bucket-presence combinations, all compatible identity layouts, and unrelated recipient/asset debt absent/present.

Amounts are token base units; MAX=`type(uint256).max`; ranges include endpoints. Ordinary populated global liabilities are asset route=10, repurchase=20, Treasury=30; absent liabilities are zero. Variable quantities through MAX belong to Numeric extremes.

Default request: authorized caller, Kernel-active RD, Active or Retired code-bearing exact-transfer asset, valid nonzero originalRecipient/destination. Unchanged = every raw liability, aggregate reserve, pending recipient/asset membership, balances and configuration unchanged; no committed rescue events.

## Shared assertions

Preview returns current entitlement, not requested amount. Compare it and pendingPayout with independent bucket expectations in every action case. In unauthorized-caller cases, preview as the fuzzed caller without excluding any identity for preview authority; use fixed callers elsewhere. Invalid inputs give exact matching preview/execution errors when authorization/activity permit.

Execution debits asset route → repurchase → Treasury, transfers amount once, reduces each authoritative raw component by its explicit expected debit and aggregate reserve by amount, and leaves entitlement−amount. Destination balance increases by amount and RD custody decreases by amount. No decimal scaling or rounding occurs.

Asset-route membership is removed when its raw debt drains, even if role debt keeps that address in the combined recipient getter. Recipient enumeration contains no duplicates. Asset membership disappears only when all debt, including unrelated recipients, is zero. Check underlying membership when a filtered getter would hide stale entries. Surplus, ineligible buckets, other recipients/assets and configuration remain unchanged.

RD emits one event per nonzero debit, in order: `PendingAssetRouteRescued(asset,originalRecipient,destination,routeDebit)` → `PendingRepurchaseRescued(asset,destination,repurchaseDebit)` → `PendingTreasuryRescued(asset,destination,treasuryDebit)`. Assert emitter, exact fields/order/count and zero-debit omission; no `Distributed` event. Failed execution fully rolls back liabilities, indexes, token/callback state and committed logs.

## Scenario setup

Cross the named current lifecycle states with valid and invalid requests, including competing errors.

## Authorization

| ID | Caller | Local enabled | Kernel state | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-L01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | true | Active | Input checks / success or exact input/transfer error | Shared assertions or Unchanged | Covered: [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_AdminOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_OperatorOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_RolesOverlapSeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_AdminOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_OperatorOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_RolesOverlapSeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_AdminOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_OperatorOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_RolesOverlapSeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_AdminOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_OperatorOnlySeed], [test][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_RolesOverlapSeed] |
| RD-L02 | Any unauthorized caller | true | Active | Execution: `RevenueDistributor_UnauthorizedConfigOperator(caller)` before input checks; preview remains permissionless subject to required activity/input checks | Unchanged | Covered: [fuzzed callers][test_authorization_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| RD-PENDING-RESCUE-A01 | Any unauthorized caller | false | Active | Execution: `RevenueDistributor_UnauthorizedConfigOperator(caller)` before input checks; preview remains permissionless subject to required activity/input checks | Unchanged | Covered: [fuzzed callers][test_authorization_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| RD-PENDING-RESCUE-A04 | Any unauthorized caller, fuzz; seed former operator, emergency, revenue admin and payout recipient | Fuzz true/false | Inactive | Preview and execution: `RevenueDistributor_PolicyNotActive(RD)` before caller or input checks | Unchanged | Covered: [fuzzed callers][test_authorization_whenCallerIsUnauthorized_reverts_givenInactive], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts_givenInactive] |
| RD-L04 | Former operator; new operator; admin | true | Active | Rotation/revocation removes old operator authority unless admin; new nonzero operator/admin may rescue | Current authority applies | Covered: [former operator rescues][test_givenOperatorRotated_whenFormerOperatorRescues_reverts], [current authority rescues][test_givenOperatorRotated_whenCurrentAuthorityRescues], [former operator rescues][test_givenOperatorRevoked_whenFormerOperatorRescues_reverts], [admin rescues][test_givenOperatorRevoked_whenAdminRescues] |
| RD-PENDING-RESCUE-A02 | Former operator; new operator; admin | false | Active | Rotation/revocation removes old operator authority unless admin; new nonzero operator/admin may rescue | Current authority applies | Covered: [former operator rescues][test_givenOperatorRotated_whenFormerOperatorRescues_reverts], [current authority rescues][test_givenOperatorRotated_whenCurrentAuthorityRescues], [former operator rescues][test_givenOperatorRevoked_whenFormerOperatorRescues_reverts], [admin rescues][test_givenOperatorRevoked_whenAdminRescues] |
| RD-A01 | ADMIN_ROLE holder | true | Active; timelock disabled or Kernel-inactive | Preview 10; direct execution pays route debt 4 | Shared assertions; no queued action; timelock unchanged | Covered: [admin rescues pending payout][test_givenTimelockUnavailable_whenAdminRescuesPendingPayout] |
| RD-PENDING-RESCUE-A03 | ADMIN_ROLE holder | false | Active; timelock disabled or Kernel-inactive | Preview 10; direct execution pays route debt 4 | Shared assertions; no queued action; timelock unchanged | Covered: [admin rescues pending payout][test_givenTimelockUnavailable_whenAdminRescuesPendingPayout] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-L06 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | true | false | Same as enabled; pending rescue is permitted | Shared assertions or Unchanged | Covered: [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_AdminOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_OperatorOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_RolesOverlapSeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_AdminOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_OperatorOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_RolesOverlapSeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_AdminOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_OperatorOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_RolesOverlapSeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_AdminOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_OperatorOnlySeed], [test][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_RolesOverlapSeed] |
| RD-L03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | false | true | Preview and execution: `RevenueDistributor_PolicyNotActive(RD)` before input checks | Unchanged | Covered: [test][test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts], [test][test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts], [test][test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts_AdminOnlySeed], [test][test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts_OperatorOnlySeed], [test][test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts_RolesOverlapSeed], [test][test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts_AdminOnlySeed], [test][test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts_OperatorOnlySeed], [test][test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts_RolesOverlapSeed] |
| RD-L07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | false | false | Same inactive-policy rejection as L03 | Unchanged | Covered: [test][test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts], [test][test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts], [test][test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts_AdminOnlySeed], [test][test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts_OperatorOnlySeed], [test][test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts_RolesOverlapSeed], [test][test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts_AdminOnlySeed], [test][test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts_OperatorOnlySeed], [test][test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts_RolesOverlapSeed] |

Execution order: guard → authority → Kernel activity → asset code → zero destination → forbidden destination → zero originalRecipient → zero amount → excess amount → transfer. Preview starts at Kernel activity and then follows the same input checks; it omits authority, guard and transfer.

## Invalid inputs

Use every compatible identity/global-presence combination on Active and Retired assets. Other inputs are valid except in explicit competing-fault cases. Every rejection is Unchanged.

| ID | Caller | Invalid input / numeric domain | Preview and execution error | Test |
| --- | --- | --- | --- | --- |
| RD-I01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | asset=0 | `RevenueDistributor_InvalidAsset(asset)` | Covered: [test][test_invalidInputs_whenAssetIsZero_reverts], [test][test_invalidInputs_whenAssetHasNoCode_reverts], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded], [test][test_invalidInputs_whenAssetIsZero_reverts_AdminOnlySeed], [test][test_invalidInputs_whenAssetIsZero_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenAssetIsZero_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenAssetHasNoCode_reverts_AdminOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-PENDING-RESCUE-I01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | asset is a nonzero EOA | `RevenueDistributor_InvalidAsset(asset)` | Covered: [test][test_invalidInputs_whenAssetIsZero_reverts], [test][test_invalidInputs_whenAssetHasNoCode_reverts], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded], [test][test_invalidInputs_whenAssetIsZero_reverts_AdminOnlySeed], [test][test_invalidInputs_whenAssetIsZero_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenAssetIsZero_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenAssetHasNoCode_reverts_AdminOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-I02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=0; fuzz amount 0..MAX, seed 0,1,MAX | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [test][test_invalidInputs_whenDestinationIsZero_reverts], [test][test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded], [test][test_invalidInputs_whenDestinationIsZero_reverts_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsZero_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsZero_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-I03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | originalRecipient=0; fuzz amount 0..MAX, seed 0,1,MAX | `RevenueDistributor_InvalidRecipient(originalRecipient)` before amount checks | Covered: [test][test_invalidInputs_whenRecipientIsZero_reverts], [test][test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded], [test][test_invalidInputs_whenRecipientIsZero_reverts_AdminOnlySeed], [test][test_invalidInputs_whenRecipientIsZero_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenRecipientIsZero_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-I04 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | amount=0; entitlement empty/populated | `RevenueDistributor_InvalidRescueAmount()` | Covered: [test][test_invalidInputs_whenAmountIsZero_reverts], [test][test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded], [test][test_invalidInputs_whenAmountIsZero_reverts_AdminOnlySeed], [test][test_invalidInputs_whenAmountIsZero_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenAmountIsZero_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-I05 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | entitlement<MAX; fuzz amount entitlement+1..MAX; seed entitlement+1,MAX; entitlement=0 includes unrelated obligations/surplus | `RevenueDistributor_InsufficientPendingDistribution(asset,amount,entitlement)` | Covered: [test][test_invalidInputs_whenAmountExceedsEntitlement_reverts], [test][test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded], [test][test_invalidInputs_whenAmountExceedsEntitlement_reverts_AdminOnlySeed], [test][test_invalidInputs_whenAmountExceedsEntitlement_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenAmountExceedsEntitlement_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-I06 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=Kernel; fuzz amount 0..MAX, seed 0,1,MAX; valid asset/originalRecipient | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [test][test_invalidInputs_whenDestinationIsForbidden_reverts], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded], [test][test_givenTokenOwnsDebt_whenRescued], [test][test_givenAdminOwnsDebt_whenRescued], [test][test_givenOperatorOwnsDebt_whenRescued], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_givenTokenOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenAdminOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenOperatorOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_RolesOverlapSeed] |
| RD-PENDING-RESCUE-I02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=RD; fuzz amount 0..MAX, seed 0,1,MAX; valid asset/originalRecipient | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [test][test_invalidInputs_whenDestinationIsForbidden_reverts], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded], [test][test_givenTokenOwnsDebt_whenRescued], [test][test_givenAdminOwnsDebt_whenRescued], [test][test_givenOperatorOwnsDebt_whenRescued], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_givenTokenOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenAdminOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenOperatorOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_RolesOverlapSeed] |
| RD-PENDING-RESCUE-I03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=asset contract; fuzz amount 0..MAX, seed 0,1,MAX; valid asset/originalRecipient | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [test][test_invalidInputs_whenDestinationIsForbidden_reverts], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded], [test][test_givenTokenOwnsDebt_whenRescued], [test][test_givenAdminOwnsDebt_whenRescued], [test][test_givenOperatorOwnsDebt_whenRescued], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_reverts_RolesOverlapSeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_givenTokenOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenAdminOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenOperatorOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_RolesOverlapSeed] |
| RD-I07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | NeverListed token; no entitlement, surplus absent/present; enabled/disabled; fuzz amount 1..MAX, seed 1,MAX | `RevenueDistributor_InsufficientPendingDistribution(asset,amount,0)`; custody is not pending entitlement | Covered: [test][test_givenNeverListedAsset_whenPendingPayoutRequested_reverts], [test][test_givenNeverListedAsset_whenPendingPayoutRequested_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenPendingPayoutRequested_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenPendingPayoutRequested_reverts_RolesOverlapSeed] |
| RD-I08 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | All roles overlap; Active/Retired; enabled/disabled; valid asset, destination=0/Kernel/RD/asset, originalRecipient=0; amount=0,1,MAX | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [test][test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts], [test][test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts_AdminOnlySeed], [test][test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts_OperatorOnlySeed], [test][test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts_RolesOverlapSeed] |

Cross unauthorized callers/activity failures with invalid inputs to prove execution precedence. Include simultaneous invalid asset/destination/recipient/amount, including inactive preview calls with invalid inputs to establish activity precedence.

## Payout allocation

Use eligible bucket amounts derived from the fixed 10/20/30 global debts. For every row, test compatible identity layouts and optional globally populated buckets, local enabled/disabled state, Active/Retired asset and admin/operator separately. Fuzz amount in the row's inclusive interval; seed its first/last values and adjacent interior values when distinct. Surplus and unrelated debts do not alter allocation. Preview=entitlement and execution succeeds.

| ID | Caller | Eligible bucket condition | Amount interval | Bucket effects | Events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-P01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | assetRoute>0; repurchase/treasury arbitrary | 1..assetRoute | Asset route −amount | Asset route(amount) | Covered: [test][test_allocation_givenRoute_whenAmountIsWithinInterval], [test][test_allocation_givenRoute_whenBoundariesAreSeeded], [test][test_allocation_givenRoute_whenAmountIsWithinInterval_AdminOnlySeed], [test][test_allocation_givenRoute_whenAmountIsWithinInterval_OperatorOnlySeed], [test][test_allocation_givenRoute_whenAmountIsWithinInterval_RolesOverlapSeed], [test][test_allocation_givenRoute_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRoute_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRoute_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P06 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | assetRoute=0; repurchase>0; treasury arbitrary | 1..repurchase | Repurchase −amount | Repurchase(amount) | Covered: [test][test_allocation_givenRepurchase_whenAmountIsWithinInterval], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded], [test][test_allocation_givenRepurchase_whenAmountIsWithinInterval_AdminOnlySeed], [test][test_allocation_givenRepurchase_whenAmountIsWithinInterval_OperatorOnlySeed], [test][test_allocation_givenRepurchase_whenAmountIsWithinInterval_RolesOverlapSeed], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | assetRoute=repurchase=0; treasury>0 | 1..treasury | Treasury −amount | Treasury(amount) | Covered: [test][test_allocation_givenTreasury_whenAmountIsWithinInterval], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded], [test][test_allocation_givenTreasury_whenAmountIsWithinInterval_AdminOnlySeed], [test][test_allocation_givenTreasury_whenAmountIsWithinInterval_OperatorOnlySeed], [test][test_allocation_givenTreasury_whenAmountIsWithinInterval_RolesOverlapSeed], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P08 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | assetRoute>0; repurchase>0; treasury arbitrary | assetRoute+1..assetRoute+repurchase | Asset route cleared; repurchase −(amount−assetRoute) | Asset route(assetRoute) → Repurchase(amount−assetRoute) | Covered: [test][test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded], [test][test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth_AdminOnlySeed], [test][test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth_OperatorOnlySeed], [test][test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth_RolesOverlapSeed], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P09 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | assetRoute>0; repurchase=0; treasury>0 | assetRoute+1..assetRoute+treasury | Asset route cleared; Treasury −(amount−assetRoute) | Asset route(assetRoute) → Treasury(amount−assetRoute) | Covered: [test][test_allocation_givenRouteAndTreasury_whenAmountSpansBoth], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded], [test][test_allocation_givenRouteAndTreasury_whenAmountSpansBoth_AdminOnlySeed], [test][test_allocation_givenRouteAndTreasury_whenAmountSpansBoth_OperatorOnlySeed], [test][test_allocation_givenRouteAndTreasury_whenAmountSpansBoth_RolesOverlapSeed], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P10 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | assetRoute=0; repurchase>0; treasury>0 | repurchase+1..repurchase+treasury | Repurchase cleared; Treasury −(amount−repurchase) | Repurchase(repurchase) → Treasury(amount−repurchase) | Covered: [test][test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded], [test][test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth_AdminOnlySeed], [test][test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth_OperatorOnlySeed], [test][test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth_RolesOverlapSeed], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P11 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | All three eligible buckets positive | assetRoute+repurchase+1..entitlement | Asset route/repurchase cleared; Treasury −(amount−assetRoute−repurchase) | Asset route(assetRoute) → Repurchase(repurchase) → Treasury(amount−assetRoute−repurchase) | Covered: [test][test_allocation_givenAllBuckets_whenAmountSpansAll], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded], [test][test_allocation_givenAllBuckets_whenAmountSpansAll_AdminOnlySeed], [test][test_allocation_givenAllBuckets_whenAmountSpansAll_OperatorOnlySeed], [test][test_allocation_givenAllBuckets_whenAmountSpansAll_RolesOverlapSeed], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded_RolesOverlapSeed] |

Event shorthand above refers to the exact events in Shared assertions. Boundary drivers guarantee amount=1, each eligible cumulative cap, cap−1/cap+1 when valid, and exact entitlement. Example: eligible buckets 10/20/30 and amount=35 debits 10/20/5, leaving 0/0/25.

## Numeric extremes

Construct solvent, non-overflowing funded state directly; aggregate liabilities and custody must fit uint256. Do not discard MAX cases through arbitrary fixture caps.

| ID | Caller | State / amount | Preview / execution effects | Test |
| --- | --- | --- | --- | --- |
| RD-P03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Active/Retired; enabled/disabled; entitlement=MAX, amount=MAX; eligible splits across compatible bucket layouts | Preview MAX; exact full allocation, custody payment and membership removal without overflow | Covered: [test][test_numericExtremes_whenMaximumIsRescued], [test][test_numericExtremes_whenMaximumIsRescued_AdminOnlySeed], [test][test_numericExtremes_whenMaximumIsRescued_OperatorOnlySeed], [test][test_numericExtremes_whenMaximumIsRescued_RolesOverlapSeed] |
| RD-N02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | All identities overlap; variable positive bucket quantities with sum≤MAX; fuzz amount 1..entitlement; seed 1/1/1 and MAX−2/1/1 | Independent numerical allocation; seeds 1, each cumulative boundary and adjacent values, full entitlement | Covered: [test][test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary], [test][test_numericExtremes_whenQuantityBoundariesAreSeeded], [test][test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary_AdminOnlySeed], [test][test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary_OperatorOnlySeed], [test][test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary_RolesOverlapSeed], [test][test_numericExtremes_whenQuantityBoundariesAreSeeded_AdminOnlySeed], [test][test_numericExtremes_whenQuantityBoundariesAreSeeded_OperatorOnlySeed], [test][test_numericExtremes_whenQuantityBoundariesAreSeeded_RolesOverlapSeed] |
| RD-N03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | entitlement=0,1,MAX−1,MAX; requests 0,1,entitlement and MAX where distinct | Zero request rejects; positive request succeeds iff ≤entitlement; exact excess error otherwise | Covered: [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts], [test][test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts_AdminOnlySeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts_OperatorOnlySeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts_RolesOverlapSeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued_AdminOnlySeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued_OperatorOnlySeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued_RolesOverlapSeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts_AdminOnlySeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts_OperatorOnlySeed], [test][test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts_RolesOverlapSeed] |

Do not construct an entitlement+1 rejection interval when entitlement=MAX. Destination prebalances and unrelated obligations must respect the same funded total-supply budget.

## Transfers, destinations and isolation

Each row covers Active and Retired assets and local enabled/disabled states where compatible.

| ID | Caller | Condition | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| RD-P02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Partial/exact bucket/recipient/aggregate drain; other recipient/asset debt and surplus absent/present | Correct independent membership removal/retention; unrelated debt unchanged; second positive rescue after full recipient drain rejects | Covered: [test][test_allocation_givenRoute_whenBoundariesAreSeeded], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded], [test][test_allocation_givenRoute_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRoute_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRoute_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRepurchase_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenTreasury_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_RolesOverlapSeed], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded_AdminOnlySeed], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded_OperatorOnlySeed], [test][test_allocation_givenAllBuckets_whenBoundariesAreSeeded_RolesOverlapSeed] |
| RD-P04 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Former configured recipient after route removal/retirement; old/current yield recipient after rotation/unset; old/new Treasury after upgrade | Fixed debt remains at original address; role debt follows current destination; preview matches independent current entitlement | Covered: [test][test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued], [test][test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts], [test][test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues], [test][test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues], [test][test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts], [test][test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues], [test][test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues], [test][test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts], [test][test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues], [test][test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues], [test][test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued_AdminOnlySeed], [test][test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued_OperatorOnlySeed], [test][test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued_RolesOverlapSeed], [test][test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts_AdminOnlySeed], [test][test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts_OperatorOnlySeed], [test][test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts_RolesOverlapSeed], [test][test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues_AdminOnlySeed], [test][test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues_OperatorOnlySeed], [test][test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues_RolesOverlapSeed], [test][test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues_AdminOnlySeed], [test][test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues_OperatorOnlySeed], [test][test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues_RolesOverlapSeed], [test][test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts_AdminOnlySeed], [test][test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts_OperatorOnlySeed], [test][test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts_RolesOverlapSeed], [test][test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues_AdminOnlySeed], [test][test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues_OperatorOnlySeed], [test][test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues_RolesOverlapSeed], [test][test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues_AdminOnlySeed], [test][test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues_OperatorOnlySeed], [test][test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues_RolesOverlapSeed], [test][test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts_AdminOnlySeed], [test][test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts_OperatorOnlySeed], [test][test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts_RolesOverlapSeed], [test][test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues_AdminOnlySeed], [test][test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues_OperatorOnlySeed], [test][test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues_RolesOverlapSeed], [test][test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues_AdminOnlySeed], [test][test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues_OperatorOnlySeed], [test][test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues_RolesOverlapSeed] |
| RD-P05 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=originalRecipient, another owed recipient, admin, operator, yield recipient, Treasury, unrelated EOA/contract; destination differs from zero, asset, Kernel and RD; token accepts delivery | Only selected entitlement is debited; exact balance deltas | Covered: [test][test_whenPermittedDestinationsAreSeeded], [test][test_givenTokenOwnsDebt_whenRescued], [test][test_givenAdminOwnsDebt_whenRescued], [test][test_givenOperatorOwnsDebt_whenRescued], [test][test_whenPermittedDestinationsAreSeeded_AdminOnlySeed], [test][test_whenPermittedDestinationsAreSeeded_OperatorOnlySeed], [test][test_whenPermittedDestinationsAreSeeded_RolesOverlapSeed], [test][test_givenTokenOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenTokenOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenAdminOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenAdminOwnsDebt_whenRescued_RolesOverlapSeed], [test][test_givenOperatorOwnsDebt_whenRescued_AdminOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_OperatorOnlySeed], [test][test_givenOperatorOwnsDebt_whenRescued_RolesOverlapSeed] |
| RD-X01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Representative reverting token or custody below valid requested amount | Exact token error; full rollback. A valid preview does not guarantee delivery | Covered: [test][test_givenValidPreview_whenTokenRejectsTransfer_reverts], [test][test_givenValidPreview_whenCustodyIsInsufficient_reverts], [test][test_givenValidPreview_whenTokenRejectsTransfer_reverts_AdminOnlySeed], [test][test_givenValidPreview_whenTokenRejectsTransfer_reverts_OperatorOnlySeed], [test][test_givenValidPreview_whenTokenRejectsTransfer_reverts_RolesOverlapSeed], [test][test_givenValidPreview_whenCustodyIsInsufficient_reverts_AdminOnlySeed], [test][test_givenValidPreview_whenCustodyIsInsufficient_reverts_OperatorOnlySeed], [test][test_givenValidPreview_whenCustodyIsInsufficient_reverts_RolesOverlapSeed] |

The ERC-20 testing guidance assigns false/no-return and missing-transfer handling to the safe-transfer library. This action suite uses representative transfer rejection to prove accounting rollback.

Zero destination is covered in RD-I02; Kernel, RD and asset destinations are covered in RD-I06. The current configOperator remains a permitted destination, unlike BL's bound Configurator restriction.

## Token callbacks

Authorize the callback token as RD's operator so nested authorized writes reach the guard. Guarantee same/different outer/nested recipient and asset identities independently, Active/Retired assets, enabled/disabled state and partial/full outer rescue. Use fixed callback identities and meaningful outer amount ranges.

Nested guarded actions: pending rescue, surplus `rescue`, distribute and transferPendingPayout. Verify each fails with `ReentrancyGuardReentrantCall()` before access/input checks.

| ID | Caller | Callback behavior | Outer execution / effects | Test |
| --- | --- | --- | --- | --- |
| RD-X02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Token catches nested guard error; separately propagates a deterministic callback error | Caught: one outer payment, no nested/configuration change. Propagated: exact error and full rollback | Covered: [test][test_givenPendingRescueCallback_whenFailureIsCaught], [test][test_givenPendingRescueCallback_whenFailureIsPropagated], [test][test_givenSurplusRescueCallback_whenFailureIsCaught], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated], [test][test_givenDistributeCallback_whenFailureIsCaught], [test][test_givenDistributeCallback_whenFailureIsPropagated], [test][test_givenPendingRetryCallback_whenFailureIsCaught], [test][test_givenPendingRetryCallback_whenFailureIsPropagated], [test][test_givenWriteCallback_whenFailureIsCaught], [test][test_givenWriteCallback_whenFailureIsPropagated], [test][test_givenPendingRescueCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenPendingRescueCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenSurplusRescueCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenDistributeCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenDistributeCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenDistributeCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenDistributeCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenDistributeCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenDistributeCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenPendingRetryCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenPendingRetryCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenWriteCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenWriteCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenWriteCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenWriteCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenWriteCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenWriteCallback_whenFailureIsPropagated_RolesOverlapSeed] |
| RD-X03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Callback reads preview, raw/combined entitlement, pending membership and configuration after partial rescue | Reads see entitlement−amount, updated indexes and unchanged configuration; no duplicate payment | Covered: [test][test_givenReadCallback_whenPartialPayoutStateIsRead], [test][test_givenReadCallback_whenOneUnitPayoutStateIsRead], [test][test_givenReadCallback_whenPartialPayoutStateIsRead_AdminOnlySeed], [test][test_givenReadCallback_whenPartialPayoutStateIsRead_OperatorOnlySeed], [test][test_givenReadCallback_whenPartialPayoutStateIsRead_RolesOverlapSeed], [test][test_givenReadCallback_whenOneUnitPayoutStateIsRead_AdminOnlySeed], [test][test_givenReadCallback_whenOneUnitPayoutStateIsRead_OperatorOnlySeed], [test][test_givenReadCallback_whenOneUnitPayoutStateIsRead_RolesOverlapSeed] |
| RD-PENDING-RESCUE-C01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Same reads after full recipient drain; callback catches preview error for amount=1 | pendingPayout=0; preview gives `RevenueDistributor_InsufficientPendingDistribution(asset,1,0)`; outer rescue succeeds once | Covered: [test][test_givenReadCallback_whenFullPayoutStateIsRead], [test][test_givenReadCallback_whenFullPayoutStateIsRead_AdminOnlySeed], [test][test_givenReadCallback_whenFullPayoutStateIsRead_OperatorOnlySeed], [test][test_givenReadCallback_whenFullPayoutStateIsRead_RolesOverlapSeed] |

Retired duplicate caller IDs: RD-L05, RD-L08, RD-L09, RD-L10, RD-I09, RD-I10, RD-I11, RD-I12, RD-I13, RD-I14, RD-I15, RD-I16, RD-I17, RD-I18, RD-I19, RD-P12, RD-P13, RD-P14, RD-P15, RD-P16, RD-P17, RD-P18, RD-P19, RD-N04, RD-N05, RD-P20, RD-P21, RD-P22, RD-X04, RD-X05, RD-X06, RD-PENDING-RESCUE-C02. Retained caller families include explicit exclusive-role and overlapping-role seeds.

[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls]: ./rescuePendingPayout.t.sol#L2385
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L2427
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls]: ./rescuePendingPayout.t.sol#L2471
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L2513
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls]: ./rescuePendingPayout.t.sol#L2127
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L2169
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls]: ./rescuePendingPayout.t.sol#L2213
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L2255
[test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts]: ./rescuePendingPayout.t.sol#L2557
[test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts]: ./rescuePendingPayout.t.sol#L2599
[test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts]: ./rescuePendingPayout.t.sol#L2299
[test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts]: ./rescuePendingPayout.t.sol#L2341
[test_authorization_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L630
[test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L637
[test_givenOperatorRotated_whenFormerOperatorRescues_reverts]: ./rescuePendingPayout.t.sol#L810
[test_givenOperatorRotated_whenCurrentAuthorityRescues]: ./rescuePendingPayout.t.sol#L835
[test_givenOperatorRevoked_whenFormerOperatorRescues_reverts]: ./rescuePendingPayout.t.sol#L860
[test_givenOperatorRevoked_whenAdminRescues]: ./rescuePendingPayout.t.sol#L896
[test_givenTimelockUnavailable_whenAdminRescuesPendingPayout]: ./rescuePendingPayout.t.sol#L65
[test_invalidInputs_whenAssetIsZero_reverts]: ./rescuePendingPayout.t.sol#L315
[test_invalidInputs_whenAssetHasNoCode_reverts]: ./rescuePendingPayout.t.sol#L330
[test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3734
[test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3679
[test_invalidInputs_whenDestinationIsZero_reverts]: ./rescuePendingPayout.t.sol#L345
[test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3856
[test_invalidInputs_whenRecipientIsZero_reverts]: ./rescuePendingPayout.t.sol#L375
[test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3955
[test_invalidInputs_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L390
[test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3628
[test_invalidInputs_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L404
[test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3571
[test_invalidInputs_whenDestinationIsForbidden_reverts]: ./rescuePendingPayout.t.sol#L360
[test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L3799
[test_givenTokenOwnsDebt_whenRescued]: ./rescuePendingPayout.t.sol#L755
[test_givenAdminOwnsDebt_whenRescued]: ./rescuePendingPayout.t.sol#L766
[test_givenOperatorOwnsDebt_whenRescued]: ./rescuePendingPayout.t.sol#L777
[test_givenNeverListedAsset_whenPendingPayoutRequested_reverts]: ./rescuePendingPayout.t.sol#L651
[test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts]: ./rescuePendingPayout.t.sol#L3898
[test_allocation_givenRoute_whenAmountIsWithinInterval]: ./rescuePendingPayout.t.sol#L97
[test_allocation_givenRoute_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5696
[test_allocation_givenRepurchase_whenAmountIsWithinInterval]: ./rescuePendingPayout.t.sol#L118
[test_allocation_givenRepurchase_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5701
[test_allocation_givenTreasury_whenAmountIsWithinInterval]: ./rescuePendingPayout.t.sol#L139
[test_allocation_givenTreasury_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5710
[test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth]: ./rescuePendingPayout.t.sol#L160
[test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5719
[test_allocation_givenRouteAndTreasury_whenAmountSpansBoth]: ./rescuePendingPayout.t.sol#L181
[test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5728
[test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth]: ./rescuePendingPayout.t.sol#L202
[test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5737
[test_allocation_givenAllBuckets_whenAmountSpansAll]: ./rescuePendingPayout.t.sol#L223
[test_allocation_givenAllBuckets_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L5746
[test_numericExtremes_whenMaximumIsRescued]: ./rescuePendingPayout.t.sol#L4169
[test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary]: ./rescuePendingPayout.t.sol#L677
[test_numericExtremes_whenQuantityBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L4189
[test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L4085
[test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued]: ./rescuePendingPayout.t.sol#L4127
[test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L4041
[test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued]: ./rescuePendingPayout.t.sol#L2942
[test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts]: ./rescuePendingPayout.t.sol#L3451
[test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues]: ./rescuePendingPayout.t.sol#L3493
[test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues]: ./rescuePendingPayout.t.sol#L3409
[test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts]: ./rescuePendingPayout.t.sol#L3325
[test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues]: ./rescuePendingPayout.t.sol#L3367
[test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues]: ./rescuePendingPayout.t.sol#L3283
[test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts]: ./rescuePendingPayout.t.sol#L3099
[test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues]: ./rescuePendingPayout.t.sol#L3141
[test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues]: ./rescuePendingPayout.t.sol#L3063
[test_whenPermittedDestinationsAreSeeded]: ./rescuePendingPayout.t.sol#L4221
[test_givenValidPreview_whenTokenRejectsTransfer_reverts]: ./rescuePendingPayout.t.sol#L3217
[test_givenValidPreview_whenCustodyIsInsufficient_reverts]: ./rescuePendingPayout.t.sol#L3181
[test_givenPendingRescueCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L2759
[test_givenPendingRescueCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L2787
[test_givenSurplusRescueCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L2984
[test_givenSurplusRescueCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L3012
[test_givenDistributeCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L2658
[test_givenDistributeCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L2678
[test_givenPendingRetryCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L2823
[test_givenPendingRetryCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L2843
[test_givenWriteCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L1099
[test_givenWriteCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L1114
[test_givenReadCallback_whenPartialPayoutStateIsRead]: ./rescuePendingPayout.t.sol#L1130
[test_givenReadCallback_whenOneUnitPayoutStateIsRead]: ./rescuePendingPayout.t.sol#L2899
[test_givenReadCallback_whenFullPayoutStateIsRead]: ./rescuePendingPayout.t.sol#L2879
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2394
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2405
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2416
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2438
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2449
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2460
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2480
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2491
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2502
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2524
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2535
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2546
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2136
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2147
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2158
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2180
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2191
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2202
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2222
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2233
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2244
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2266
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2277
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2288
[test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2566
[test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2577
[test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2588
[test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2610
[test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2621
[test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2632
[test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2308
[test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2319
[test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2330
[test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2352
[test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2363
[test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2374
[test_invalidInputs_whenAssetIsZero_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3719
[test_invalidInputs_whenAssetIsZero_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3724
[test_invalidInputs_whenAssetIsZero_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3729
[test_invalidInputs_whenAssetHasNoCode_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3664
[test_invalidInputs_whenAssetHasNoCode_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3669
[test_invalidInputs_whenAssetHasNoCode_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3674
[test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3743
[test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3752
[test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3761
[test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3688
[test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3697
[test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3708
[test_invalidInputs_whenDestinationIsZero_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3841
[test_invalidInputs_whenDestinationIsZero_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3846
[test_invalidInputs_whenDestinationIsZero_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3851
[test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3865
[test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3876
[test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3887
[test_invalidInputs_whenRecipientIsZero_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3940
[test_invalidInputs_whenRecipientIsZero_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3945
[test_invalidInputs_whenRecipientIsZero_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3950
[test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3964
[test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3973
[test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3984
[test_invalidInputs_whenAmountIsZero_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3613
[test_invalidInputs_whenAmountIsZero_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3618
[test_invalidInputs_whenAmountIsZero_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3623
[test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3637
[test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3646
[test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3655
[test_invalidInputs_whenAmountExceedsEntitlement_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3535
[test_invalidInputs_whenAmountExceedsEntitlement_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3547
[test_invalidInputs_whenAmountExceedsEntitlement_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3559
[test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3580
[test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3591
[test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3602
[test_invalidInputs_whenDestinationIsForbidden_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3770
[test_invalidInputs_whenDestinationIsForbidden_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3782
[test_invalidInputs_whenDestinationIsForbidden_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3794
[test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3808
[test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3819
[test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3830
[test_givenTokenOwnsDebt_whenRescued_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3048
[test_givenTokenOwnsDebt_whenRescued_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3053
[test_givenTokenOwnsDebt_whenRescued_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3058
[test_givenAdminOwnsDebt_whenRescued_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2643
[test_givenAdminOwnsDebt_whenRescued_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2648
[test_givenAdminOwnsDebt_whenRescued_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2653
[test_givenOperatorOwnsDebt_whenRescued_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2744
[test_givenOperatorOwnsDebt_whenRescued_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2749
[test_givenOperatorOwnsDebt_whenRescued_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2754
[test_givenNeverListedAsset_whenPendingPayoutRequested_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2710
[test_givenNeverListedAsset_whenPendingPayoutRequested_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2720
[test_givenNeverListedAsset_whenPendingPayoutRequested_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2732
[test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3907
[test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3918
[test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3929
[test_allocation_givenRoute_whenAmountIsWithinInterval_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2007
[test_allocation_givenRoute_whenAmountIsWithinInterval_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2020
[test_allocation_givenRoute_whenAmountIsWithinInterval_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2033
[test_allocation_givenRoute_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2046
[test_allocation_givenRoute_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2051
[test_allocation_givenRoute_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2056
[test_allocation_givenRepurchase_whenAmountIsWithinInterval_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1799
[test_allocation_givenRepurchase_whenAmountIsWithinInterval_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1812
[test_allocation_givenRepurchase_whenAmountIsWithinInterval_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1825
[test_allocation_givenRepurchase_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1838
[test_allocation_givenRepurchase_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1847
[test_allocation_givenRepurchase_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1856
[test_allocation_givenTreasury_whenAmountIsWithinInterval_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2061
[test_allocation_givenTreasury_whenAmountIsWithinInterval_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2074
[test_allocation_givenTreasury_whenAmountIsWithinInterval_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2087
[test_allocation_givenTreasury_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2100
[test_allocation_givenTreasury_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2109
[test_allocation_givenTreasury_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2118
[test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1865
[test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1878
[test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1891
[test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1904
[test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1915
[test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1926
[test_allocation_givenRouteAndTreasury_whenAmountSpansBoth_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1937
[test_allocation_givenRouteAndTreasury_whenAmountSpansBoth_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1950
[test_allocation_givenRouteAndTreasury_whenAmountSpansBoth_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1963
[test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1976
[test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1985
[test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1996
[test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1723
[test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1736
[test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1751
[test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1766
[test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1777
[test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1788
[test_allocation_givenAllBuckets_whenAmountSpansAll_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1681
[test_allocation_givenAllBuckets_whenAmountSpansAll_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1686
[test_allocation_givenAllBuckets_whenAmountSpansAll_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1691
[test_allocation_givenAllBuckets_whenBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L1696
[test_allocation_givenAllBuckets_whenBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L1705
[test_allocation_givenAllBuckets_whenBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L1714
[test_numericExtremes_whenMaximumIsRescued_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L4174
[test_numericExtremes_whenMaximumIsRescued_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4179
[test_numericExtremes_whenMaximumIsRescued_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4184
[test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3995
[test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4009
[test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4025
[test_numericExtremes_whenQuantityBoundariesAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L4198
[test_numericExtremes_whenQuantityBoundariesAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4207
[test_numericExtremes_whenQuantityBoundariesAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4216
[test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L4094
[test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4105
[test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4116
[test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L4136
[test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4147
[test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4158
[test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L4052
[test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4063
[test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4074
[test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2951
[test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2962
[test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2973
[test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3460
[test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3471
[test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3482
[test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3502
[test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3513
[test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3524
[test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3418
[test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3429
[test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3440
[test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3334
[test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3345
[test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3356
[test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3376
[test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3387
[test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3398
[test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3292
[test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3303
[test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3314
[test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3108
[test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3119
[test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3130
[test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3150
[test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3159
[test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3170
[test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3072
[test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3081
[test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3090
[test_whenPermittedDestinationsAreSeeded_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L4226
[test_whenPermittedDestinationsAreSeeded_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L4231
[test_whenPermittedDestinationsAreSeeded_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L4236
[test_givenValidPreview_whenTokenRejectsTransfer_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3226
[test_givenValidPreview_whenTokenRejectsTransfer_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3235
[test_givenValidPreview_whenTokenRejectsTransfer_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3244
[test_givenValidPreview_whenCustodyIsInsufficient_reverts_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3190
[test_givenValidPreview_whenCustodyIsInsufficient_reverts_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3199
[test_givenValidPreview_whenCustodyIsInsufficient_reverts_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3208
[test_givenPendingRescueCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2768
[test_givenPendingRescueCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2777
[test_givenPendingRescueCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2782
[test_givenPendingRescueCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2796
[test_givenPendingRescueCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2805
[test_givenPendingRescueCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2814
[test_givenSurplusRescueCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2993
[test_givenSurplusRescueCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3002
[test_givenSurplusRescueCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3007
[test_givenSurplusRescueCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3021
[test_givenSurplusRescueCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3030
[test_givenSurplusRescueCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3039
[test_givenDistributeCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2663
[test_givenDistributeCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2668
[test_givenDistributeCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2673
[test_givenDistributeCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2687
[test_givenDistributeCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2696
[test_givenDistributeCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2705
[test_givenPendingRetryCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2828
[test_givenPendingRetryCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2833
[test_givenPendingRetryCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2838
[test_givenPendingRetryCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2852
[test_givenPendingRetryCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2861
[test_givenPendingRetryCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2870
[test_givenWriteCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3253
[test_givenWriteCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3258
[test_givenWriteCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3263
[test_givenWriteCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L3268
[test_givenWriteCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L3273
[test_givenWriteCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L3278
[test_givenReadCallback_whenPartialPayoutStateIsRead_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2927
[test_givenReadCallback_whenPartialPayoutStateIsRead_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2932
[test_givenReadCallback_whenPartialPayoutStateIsRead_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2937
[test_givenReadCallback_whenOneUnitPayoutStateIsRead_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2908
[test_givenReadCallback_whenOneUnitPayoutStateIsRead_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2917
[test_givenReadCallback_whenOneUnitPayoutStateIsRead_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2922
[test_givenReadCallback_whenFullPayoutStateIsRead_AdminOnlySeed]: ./rescuePendingPayout.t.sol#L2884
[test_givenReadCallback_whenFullPayoutStateIsRead_OperatorOnlySeed]: ./rescuePendingPayout.t.sol#L2889
[test_givenReadCallback_whenFullPayoutStateIsRead_RolesOverlapSeed]: ./rescuePendingPayout.t.sol#L2894
[test_authorization_whenCallerIsUnauthorized_reverts_givenInactive]: ./rescuePendingPayout.t.sol#L5755
[test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts_givenInactive]: ./rescuePendingPayout.t.sol#L5763
