# RevenueDistributor.rescuePendingPayout scenario plan

RD = RevenueDistributor. This plan covers pending rescue, its preview and corresponding getters. Existing suite: [rescuePendingPayout.t.sol](./rescuePendingPayout.t.sol). Grouped tests and their deterministic boundary drivers are mapped below.

Pending-rescue preview requires Kernel activity, remains permissionless and works while RD is locally disabled. It does not predict token delivery failures.

Local disablement retains admin/current operator recovery. A disabled timelock blocks its queues and execution; admin can call RD directly. Kernel inactivity still rejects execution.

## Domains and notation

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

## Authorization and lifecycle

Cross the named current lifecycle states with valid and invalid requests, including competing errors.

| ID | Caller | RD local state | Kernel state | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-L01 | Admin; current operator | Enabled | Active | Input checks / success or exact input/transfer error | Shared assertions or Unchanged | Covered: [admin success][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls], [admin input errors][test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts], [operator success][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls], [operator input errors][test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts] |
| RD-L06 | Admin; current operator | Disabled | Active | Same as enabled; pending rescue is permitted | Shared assertions or Unchanged | Covered: [admin success][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls], [admin input errors][test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts], [operator success][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls], [operator input errors][test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts] |
| RD-L03 | Admin; current operator | Enabled | Inactive | Preview and execution: `RevenueDistributor_PolicyInactive()` before input checks | Unchanged | Covered: [admin rejection][test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts], [operator rejection][test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts] |
| RD-L07 | Admin; current operator | Disabled | Inactive | Same inactive-policy rejection as L03 | Unchanged | Covered: [admin rejection][test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts], [operator rejection][test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts] |
| RD-L02 | Any unauthorized caller | Enabled/disabled | Active/inactive | Execution: `RevenueDistributor_UnauthorizedConfigOperator(caller)` before activity/input checks; preview remains permissionless subject to required activity/input checks | Unchanged | Covered: [fuzzed callers][test_authorization_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| RD-L04 | Former operator; new operator; admin | Enabled/disabled | Active | Rotation/revocation removes old operator authority unless admin; new nonzero operator/admin may rescue | Current authority applies | Covered: [former operator rescues][test_givenOperatorRotated_whenFormerOperatorRescues_reverts], [current authority rescues][test_givenOperatorRotated_whenCurrentAuthorityRescues], [former operator rescues][test_givenOperatorRevoked_whenFormerOperatorRescues_reverts], [admin rescues][test_givenOperatorRevoked_whenAdminRescues] |
| RD-A01 | Admin | Enabled/disabled | Active; timelock disabled or Kernel-inactive | Preview 10; direct execution pays route debt 4 | Shared assertions; no queued action; timelock unchanged | Covered: [admin rescues pending payout][test_givenTimelockUnavailable_whenAdminRescuesPendingPayout] |

Execution order: guard → authority → Kernel activity → asset code → zero destination → forbidden destination → zero originalRecipient → zero amount → excess amount → transfer. Preview starts at Kernel activity and then follows the same input checks; it omits authority, guard and transfer.

## Invalid inputs

Use every compatible identity/global-presence combination on Active and Retired assets. Other inputs are valid except in explicit competing-fault cases. Every rejection is Unchanged.

| ID | Caller | Invalid input / numeric domain | Preview and execution error | Test |
| --- | --- | --- | --- | --- |
| RD-I01 | Admin; current operator | asset=0 or nonzero no-code address | `RevenueDistributor_InvalidAsset(asset)` | Covered: [fuzz][test_invalidInputs_whenAssetIsZero_reverts], [fuzz][test_invalidInputs_whenAssetHasNoCode_reverts], [boundaries][test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded], [boundaries][test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded] |
| RD-I02 | Admin; current operator | destination=0; fuzz amount 0..MAX, seed 0,1,MAX | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [fuzz][test_invalidInputs_whenDestinationIsZero_reverts], [boundaries][test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded] |
| RD-I03 | Admin; current operator | originalRecipient=0; fuzz amount 0..MAX, seed 0,1,MAX | `RevenueDistributor_InvalidRecipient(originalRecipient)` before amount checks | Covered: [fuzz][test_invalidInputs_whenRecipientIsZero_reverts], [boundaries][test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded] |
| RD-I04 | Admin; current operator | amount=0; entitlement empty/populated | `RevenueDistributor_InvalidRescueAmount()` | Covered: [fuzz][test_invalidInputs_whenAmountIsZero_reverts], [boundaries][test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded] |
| RD-I05 | Admin; current operator | entitlement<MAX; fuzz amount entitlement+1..MAX; seed entitlement+1,MAX; entitlement=0 includes unrelated obligations/surplus | `RevenueDistributor_InsufficientPendingDistribution(asset,amount,entitlement)` | Covered: [fuzz][test_invalidInputs_whenAmountExceedsEntitlement_reverts], [boundaries][test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded] |
| RD-I06 | Admin; current operator | destination=Kernel, RD or asset contract; fuzz amount 0..MAX, seed 0,1,MAX; valid asset/originalRecipient | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [fuzz][test_invalidInputs_whenDestinationIsForbidden_reverts], [boundaries][test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded], [rescued][test_givenTokenOwnsDebt_whenRescued], [rescued][test_givenAdminOwnsDebt_whenRescued], [rescued][test_givenOperatorOwnsDebt_whenRescued] |
| RD-I07 | Admin; current operator | NeverListed token; no entitlement, surplus absent/present; enabled/disabled; fuzz amount 1..MAX, seed 1,MAX | `RevenueDistributor_InsufficientPendingDistribution(asset,amount,0)`; custody is not pending entitlement | Covered: [fuzz][test_givenNeverListedAsset_whenPendingPayoutRequested_reverts] |
| RD-I08 | Admin; current operator | All roles overlap; Active/Retired; enabled/disabled; valid asset, destination=0/Kernel/RD/asset, originalRecipient=0; amount=0,1,MAX | `RevenueDistributor_InvalidRescueDestination(destination)` before recipient/amount checks | Covered: [invalid destination and zero recipient][test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts] |

Cross unauthorized callers/activity failures with invalid inputs to prove execution precedence. Include simultaneous invalid asset/destination/recipient/amount, including inactive preview calls with invalid inputs to establish activity precedence.

## Payout allocation

Use eligible bucket amounts derived from the fixed 10/20/30 global debts. For every row, test compatible identity layouts and optional globally populated buckets, local enabled/disabled state, Active/Retired asset and admin/operator separately. Fuzz amount in the row's inclusive interval; seed its first/last values and adjacent interior values when distinct. Surplus and unrelated debts do not alter allocation. Preview=entitlement and execution succeeds.

| ID | Caller | Eligible bucket condition | Amount interval | Bucket effects | Events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-P01 | Admin; current operator | assetRoute>0; repurchase/treasury arbitrary | 1..assetRoute | Asset route −amount | Asset route(amount) | Covered: [fuzz][test_allocation_givenRoute_whenAmountIsWithinInterval], [boundaries][test_allocation_givenRoute_whenBoundariesAreSeeded] |
| RD-P06 | Admin; current operator | assetRoute=0; repurchase>0; treasury arbitrary | 1..repurchase | Repurchase −amount | Repurchase(amount) | Covered: [fuzz][test_allocation_givenRepurchase_whenAmountIsWithinInterval], [boundaries][test_allocation_givenRepurchase_whenBoundariesAreSeeded] |
| RD-P07 | Admin; current operator | assetRoute=repurchase=0; treasury>0 | 1..treasury | Treasury −amount | Treasury(amount) | Covered: [fuzz][test_allocation_givenTreasury_whenAmountIsWithinInterval], [boundaries][test_allocation_givenTreasury_whenBoundariesAreSeeded] |
| RD-P08 | Admin; current operator | assetRoute>0; repurchase>0; treasury arbitrary | assetRoute+1..assetRoute+repurchase | Asset route cleared; repurchase −(amount−assetRoute) | Asset route(assetRoute) → Repurchase(amount−assetRoute) | Covered: [fuzz][test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth], [boundaries][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded] |
| RD-P09 | Admin; current operator | assetRoute>0; repurchase=0; treasury>0 | assetRoute+1..assetRoute+treasury | Asset route cleared; Treasury −(amount−assetRoute) | Asset route(assetRoute) → Treasury(amount−assetRoute) | Covered: [fuzz][test_allocation_givenRouteAndTreasury_whenAmountSpansBoth], [boundaries][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded] |
| RD-P10 | Admin; current operator | assetRoute=0; repurchase>0; treasury>0 | repurchase+1..repurchase+treasury | Repurchase cleared; Treasury −(amount−repurchase) | Repurchase(repurchase) → Treasury(amount−repurchase) | Covered: [fuzz][test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth], [boundaries][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded] |
| RD-P11 | Admin; current operator | All three eligible buckets positive | assetRoute+repurchase+1..entitlement | Asset route/repurchase cleared; Treasury −(amount−assetRoute−repurchase) | Asset route(assetRoute) → Repurchase(repurchase) → Treasury(amount−assetRoute−repurchase) | Covered: [fuzz][test_allocation_givenAllBuckets_whenAmountSpansAll], [boundaries][test_allocation_givenAllBuckets_whenBoundariesAreSeeded] |

Event shorthand above refers to the exact events in Shared assertions. Boundary drivers guarantee amount=1, each eligible cumulative cap, cap−1/cap+1 when valid, and exact entitlement. Example: eligible buckets 10/20/30 and amount=35 debits 10/20/5, leaving 0/0/25.

## Numeric extremes

Construct solvent, non-overflowing funded state directly; aggregate liabilities and custody must fit uint256. Do not discard MAX cases through arbitrary fixture caps.

| ID | Caller | State / amount | Preview / execution effects | Test |
| --- | --- | --- | --- | --- |
| RD-P03 | Admin; current operator | Active/Retired; enabled/disabled; entitlement=MAX, amount=MAX; eligible splits across compatible bucket layouts | Preview MAX; exact full allocation, custody payment and membership removal without overflow | Covered: [maximum is rescued][test_numericExtremes_whenMaximumIsRescued] |
| RD-N02 | Admin; current operator | All identities overlap; variable positive bucket quantities with sum≤MAX; fuzz amount 1..entitlement; seed 1/1/1 and MAX−2/1/1 | Independent numerical allocation; seeds 1, each cumulative boundary and adjacent values, full entitlement | Covered: [fuzz][test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary], [boundaries][test_numericExtremes_whenQuantityBoundariesAreSeeded] |
| RD-N03 | Admin; current operator | entitlement=0,1,MAX−1,MAX; requests 0,1,entitlement and MAX where distinct | Zero request rejects; positive request succeeds iff ≤entitlement; exact excess error otherwise | Covered: [boundaries][test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts], [boundaries][test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued], [boundaries][test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts] |

Do not construct an entitlement+1 rejection interval when entitlement=MAX. Destination prebalances and unrelated obligations must respect the same funded total-supply budget.

## Transfers, destinations and isolation

Each row covers Active and Retired assets and local enabled/disabled states where compatible.

| ID | Caller | Condition | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| RD-P02 | Admin; current operator | Partial/exact bucket/recipient/aggregate drain; other recipient/asset debt and surplus absent/present | Correct independent membership removal/retention; unrelated debt unchanged; second positive rescue after full recipient drain rejects | Covered: [boundaries][test_allocation_givenRoute_whenBoundariesAreSeeded], [boundaries][test_allocation_givenRepurchase_whenBoundariesAreSeeded], [boundaries][test_allocation_givenTreasury_whenBoundariesAreSeeded], [boundaries][test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded], [boundaries][test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded], [boundaries][test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded], [boundaries][test_allocation_givenAllBuckets_whenBoundariesAreSeeded] |
| RD-P04 | Admin; current operator | Former configured recipient after route removal/retirement; old/current yield recipient after rotation/unset; old/new Treasury after upgrade | Fixed debt remains at original address; role debt follows current destination; preview matches independent current entitlement | Covered: [historical and current entitlements are][test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued], [former role recipient rescues][test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts], [historical route recipient rescues][test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues], [current role recipient rescues][test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues], [former role recipient rescues][test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts], [historical route recipient rescues][test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues], [current role recipient rescues][test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues], [former role recipient rescues][test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts], [historical route recipient rescues][test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues], [current role recipient rescues][test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues] |
| RD-P05 | Admin; current operator | destination=originalRecipient, another owed recipient, admin, operator, yield recipient, Treasury, unrelated EOA/contract; destination differs from zero, asset, Kernel and RD; token accepts delivery | Only selected entitlement is debited; exact balance deltas | Covered: [fixed fixtures][test_whenPermittedDestinationsAreSeeded], [rescued][test_givenTokenOwnsDebt_whenRescued], [rescued][test_givenAdminOwnsDebt_whenRescued], [rescued][test_givenOperatorOwnsDebt_whenRescued] |
| RD-X01 | Admin; current operator | Representative reverting token or custody below valid requested amount | Exact token error; full rollback. A valid preview does not guarantee delivery | Covered: [token rejects transfer][test_givenValidPreview_whenTokenRejectsTransfer_reverts], [custody is insufficient][test_givenValidPreview_whenCustodyIsInsufficient_reverts] |

The ERC-20 testing guidance assigns false/no-return and missing-transfer handling to the safe-transfer library. This action suite uses representative transfer rejection to prove accounting rollback.

Zero destination is covered in RD-I02; Kernel, RD and asset destinations are covered in RD-I06. The current configOperator remains a permitted destination, unlike BL's bound Configurator restriction.

## Token callbacks

Authorize the callback token as RD's operator so nested authorized writes reach the guard. Guarantee same/different outer/nested recipient and asset identities independently, Active/Retired assets, enabled/disabled state and partial/full outer rescue. Use fixed callback identities and meaningful outer amount ranges.

Nested guarded actions: pending rescue, surplus `rescue`, distribute and transferPendingPayout. Verify each fails with `ReentrancyGuardReentrantCall()` before access/input checks.

| ID | Caller | Callback behavior | Outer execution / effects | Test |
| --- | --- | --- | --- | --- |
| RD-X02 | Admin; current operator | Token catches nested guard error; separately propagates a deterministic callback error | Caught: one outer payment, no nested/configuration change. Propagated: exact error and full rollback | Covered: [pending rescue: caught][test_givenPendingRescueCallback_whenFailureIsCaught], [pending rescue: propagated][test_givenPendingRescueCallback_whenFailureIsPropagated], [surplus rescue: caught][test_givenSurplusRescueCallback_whenFailureIsCaught], [surplus rescue: propagated][test_givenSurplusRescueCallback_whenFailureIsPropagated], [distribute: caught][test_givenDistributeCallback_whenFailureIsCaught], [distribute: propagated][test_givenDistributeCallback_whenFailureIsPropagated], [pending retry: caught][test_givenPendingRetryCallback_whenFailureIsCaught], [pending retry: propagated][test_givenPendingRetryCallback_whenFailureIsPropagated], [caught fuzz][test_givenWriteCallback_whenFailureIsCaught], [propagated fuzz][test_givenWriteCallback_whenFailureIsPropagated] |
| RD-X03 | Admin; current operator | Callback reads preview, raw/combined entitlement, pending membership and configuration after partial rescue | Reads see entitlement−amount, updated indexes and unchanged configuration; no duplicate payment | Covered: [partial reads fuzz][test_givenReadCallback_whenPartialPayoutStateIsRead], [fixtures][test_givenReadCallback_whenOneUnitPayoutStateIsRead] |
| RD-CB04 | Admin; current operator | Same reads after full recipient drain; callback catches preview error for amount=1 | pendingPayout=0; preview gives `RevenueDistributor_InsufficientPendingDistribution(asset,1,0)`; outer rescue succeeds once | Covered: [full reads fixtures][test_givenReadCallback_whenFullPayoutStateIsRead] |

[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls]: ./rescuePendingPayout.t.sol#L589
[test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L603
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls]: ./rescuePendingPayout.t.sol#L693
[test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L707
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls]: ./rescuePendingPayout.t.sol#L641
[test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L655
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls]: ./rescuePendingPayout.t.sol#L747
[test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L761
[test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts]: ./rescuePendingPayout.t.sol#L619
[test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts]: ./rescuePendingPayout.t.sol#L723
[test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts]: ./rescuePendingPayout.t.sol#L671
[test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts]: ./rescuePendingPayout.t.sol#L777
[test_authorization_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L802
[test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L809
[test_givenOperatorRotated_whenFormerOperatorRescues_reverts]: ./rescuePendingPayout.t.sol#L1173
[test_givenOperatorRotated_whenCurrentAuthorityRescues]: ./rescuePendingPayout.t.sol#L1198
[test_givenOperatorRevoked_whenFormerOperatorRescues_reverts]: ./rescuePendingPayout.t.sol#L1223
[test_givenOperatorRevoked_whenAdminRescues]: ./rescuePendingPayout.t.sol#L1259
[test_givenTimelockUnavailable_whenAdminRescuesPendingPayout]: ./rescuePendingPayout.t.sol#L62
[test_invalidInputs_whenAssetIsZero_reverts]: ./rescuePendingPayout.t.sol#L206
[test_invalidInputs_whenAssetHasNoCode_reverts]: ./rescuePendingPayout.t.sol#L240
[test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L445
[test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L457
[test_invalidInputs_whenDestinationIsZero_reverts]: ./rescuePendingPayout.t.sol#L275
[test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L469
[test_invalidInputs_whenRecipientIsZero_reverts]: ./rescuePendingPayout.t.sol#L347
[test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L501
[test_invalidInputs_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L381
[test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L513
[test_invalidInputs_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L410
[test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L522
[test_invalidInputs_whenDestinationIsForbidden_reverts]: ./rescuePendingPayout.t.sol#L309
[test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L485
[test_givenTokenOwnsDebt_whenRescued]: ./rescuePendingPayout.t.sol#L1083
[test_givenAdminOwnsDebt_whenRescued]: ./rescuePendingPayout.t.sol#L1095
[test_givenOperatorOwnsDebt_whenRescued]: ./rescuePendingPayout.t.sol#L1107
[test_givenNeverListedAsset_whenPendingPayoutRequested_reverts]: ./rescuePendingPayout.t.sol#L823
[test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts]: ./rescuePendingPayout.t.sol#L547
[test_allocation_givenRoute_whenAmountIsWithinInterval]: ./rescuePendingPayout.t.sol#L88
[test_allocation_givenRoute_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L164
[test_allocation_givenRepurchase_whenAmountIsWithinInterval]: ./rescuePendingPayout.t.sol#L99
[test_allocation_givenRepurchase_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L170
[test_allocation_givenTreasury_whenAmountIsWithinInterval]: ./rescuePendingPayout.t.sol#L110
[test_allocation_givenTreasury_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L176
[test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth]: ./rescuePendingPayout.t.sol#L121
[test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L182
[test_allocation_givenRouteAndTreasury_whenAmountSpansBoth]: ./rescuePendingPayout.t.sol#L132
[test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L188
[test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth]: ./rescuePendingPayout.t.sol#L143
[test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L194
[test_allocation_givenAllBuckets_whenAmountSpansAll]: ./rescuePendingPayout.t.sol#L154
[test_allocation_givenAllBuckets_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L200
[test_numericExtremes_whenMaximumIsRescued]: ./rescuePendingPayout.t.sol#L875
[test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary]: ./rescuePendingPayout.t.sol#L922
[test_numericExtremes_whenQuantityBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L937
[test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L956
[test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued]: ./rescuePendingPayout.t.sol#L977
[test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L1005
[test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued]: ./rescuePendingPayout.t.sol#L1280
[test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts]: ./rescuePendingPayout.t.sol#L1309
[test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues]: ./rescuePendingPayout.t.sol#L1336
[test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues]: ./rescuePendingPayout.t.sol#L1360
[test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts]: ./rescuePendingPayout.t.sol#L1384
[test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues]: ./rescuePendingPayout.t.sol#L1411
[test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues]: ./rescuePendingPayout.t.sol#L1435
[test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts]: ./rescuePendingPayout.t.sol#L1459
[test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues]: ./rescuePendingPayout.t.sol#L1487
[test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues]: ./rescuePendingPayout.t.sol#L1512
[test_whenPermittedDestinationsAreSeeded]: ./rescuePendingPayout.t.sol#L1044
[test_givenValidPreview_whenTokenRejectsTransfer_reverts]: ./rescuePendingPayout.t.sol#L1120
[test_givenValidPreview_whenCustodyIsInsufficient_reverts]: ./rescuePendingPayout.t.sol#L1145
[test_givenPendingRescueCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L1538
[test_givenPendingRescueCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L1547
[test_givenSurplusRescueCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L1556
[test_givenSurplusRescueCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L1565
[test_givenDistributeCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L1574
[test_givenDistributeCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L1583
[test_givenPendingRetryCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L1592
[test_givenPendingRetryCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L1601
[test_givenWriteCallback_whenFailureIsCaught]: ./rescuePendingPayout.t.sol#L1611
[test_givenWriteCallback_whenFailureIsPropagated]: ./rescuePendingPayout.t.sol#L1626
[test_givenReadCallback_whenPartialPayoutStateIsRead]: ./rescuePendingPayout.t.sol#L1642
[test_givenReadCallback_whenOneUnitPayoutStateIsRead]: ./rescuePendingPayout.t.sol#L1686
[test_givenReadCallback_whenFullPayoutStateIsRead]: ./rescuePendingPayout.t.sol#L1730
