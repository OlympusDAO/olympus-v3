# BurnerLoansConfigTimelock.queueRescuePendingPayout scenario plan

BLCT = BurnerLoansConfigTimelock; BLC = its controlled BurnerLoansConfig; BL = BLC's bound BurnerLoans facility. This plan tests queueing and rescue-specific changes before execution. [BL's plan](../BurnerLoans/rescuePendingPayout.md) owns payout mechanics; [execute.t.sol](./execute.t.sol) owns execution authorization/lifecycle, timing and generic action state. Queue suite: [queueRescuePendingPayout.t.sol](./queueRescuePendingPayout.t.sol). Grouped tests and their deterministic boundary drivers are mapped below.

## Domains and shared assertions

- Queue callers: admin and burner_loans_admin, tested separately. Unauthorized-caller fuzz excludes all holders of either role; seed operator-only, emergency-only and payout recipient.
- Fixed default: BLCT and BLC enabled/Kernel-active; BLCT selected as BLC's operator; BLC bound as BL's Configurator; BL active; token and destination accept transfer; originalRecipient is owed 10 base units; queued amount=4.
- Use named arguments `token`, `originalRecipient`, `destination`, `amount` and fixed addresses. No numeric or payout-bucket fuzzing in this queue plan.
- Queue success returns the pre-call nextActionId and increments it once. Store one BLC rescue action with exact `abi.encode(token,originalRecipient,destination,4)`, proposer, timestamps, pending flags, Config destination and conflict-key owner. No entitlement or balances move.
- Conflict key is scoped to BLC and the rescue selector/token/originalRecipient; destination and amount do not distinguish keys. Stored state hash is `keccak256(abi.encode(BLC.facility()))`; balances, entitlement and routing are excluded. BLC's facility binding is one-time.
- Unchanged = action counter/storage/key ownership, configuration, entitlement/reserve and balances unchanged; no committed events.

Queue events, emitted by BLCT in order: `ConfigStateQueued` → `TimelockSubActionQueued` → `TimelockActionQueued`. Assert exact action ID, target BLC, selector, payload/batch hashes, scoped key, expected state hash, proposer and timestamps.

## Queue authorization and lifecycle

Use the valid request and amount=0. Each gate has a case with earlier checks satisfied; simultaneous faults establish precedence. Explicitly cover BLCT and BLC enabled/disabled and active/inactive independently. BL may be locally disabled. BLCT and BLC must both be enabled and Kernel-active to queue/execute. Cancellation requires BLCT enabled and Kernel-active. Admin recovery goes directly through BL; see [BL’s plan](../BurnerLoans/rescuePendingPayout.md).

| ID | Caller | BLCT local state | BLCT Kernel membership | BLC local state | BLC Kernel membership | Operator / other state | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-L01 | Admin; burner_loans_admin | Enabled | Active | Enabled | Active | BLCT selected; BL Kernel-active | Queue succeeds with BL locally enabled or disabled | Covered: [role queues][test_givenValidRequest_whenEachRoleQueues] |
| BLCT-L02 | Any unauthorized caller | Enabled | Active | Enabled | Active | BLCT selected; BL Kernel-active | `IPolicyAdmin.NotAuthorised()` before preview; Unchanged | Covered: [fuzzed callers][test_whenQueueCallerIsUnauthorized_reverts], [caller identities][test_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| BLCT-L03 | Authorized queue caller | Disabled | Active | Enabled | Active | BLCT selected; BL Kernel-active | `NotEnabled()`; Unchanged | Covered: [pending rescue queued][test_givenTimelockDisabled_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| BLCT-L08 | Authorized queue caller | Enabled | Inactive | Enabled | Active | BLCT selected; BL Kernel-active | `BurnerLoansConfigTimelock_PolicyInactive(BLCT)`; Unchanged | Covered: [pending rescue queued][test_givenTimelockInactive_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| BLCT-L09 | Authorized queue caller | Enabled | Active | Enabled | Inactive | BLCT selected; BL Kernel-active | `BurnerLoansConfigTimelock_PolicyInactive(BLC)`; Unchanged | Covered: [pending rescue queued][test_givenConfigInactive_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| BLCT-L10 | Admin; burner_loans_admin | Enabled | Active | Disabled | Active | BLCT selected; BL Kernel-active | NotEnabled(); no queue/payment with BL enabled or disabled | Covered: [pending rescue queued][test_givenConfigDisabled_whenPendingRescueQueued_reverts] |
| BLCT-L04 | Authorized queue caller | Enabled | Active | Enabled | Active | BLCT no longer selected | `BurnerLoansConfig_UnauthorizedConfigOperator(BLCT)`; Unchanged | Covered: [pending rescue queued][test_givenOperatorChanged_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| BLCT-L06 | Authorized queue caller | Enabled | Active | Enabled | Active | BLCT selected; BL Kernel-inactive | Preview and queue revert `BurnerLoans_PolicyInactive()`; Unchanged | Covered: [pending rescue queued][test_givenFacilityInactive_whenPendingRescueQueued_reverts] |

Current queue check order: BLCT enabled → BLCT active → BLC active → proposer role → selected operator → BLC enabled → BL preview → conflict key. BL preview checks Kernel activity before inputs; its rejection occurs before any queue state commits.

## Queue behavior

| ID | Caller | Fixed request / state | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| BLCT-Q01 | Admin; burner_loans_admin | Valid default request, amount=4 | Store exact action and emit queue events; no payout | Covered: [role queues][test_givenValidRequest_whenEachRoleQueues] |
| BLCT-Q02 | Authorized queue caller | Same token/originalRecipient already queued; change destination or valid amount | `IConfigTimelockBatchQueue_ConfigKeyPending(key,owner)`; prior action unchanged | Covered: [request changes][test_givenSameRecipientQueued_whenRequestChanges_reverts] |
| BLCT-Q03 | Authorized queue caller | Different originalRecipient for same token, or different token for same recipient; both requests valid | Independent keys; both queue successfully without moving entitlement | Covered: [queued][test_givenIndependentRecipientsAndAssets_whenQueued] |

## Invalid inputs

One deterministic preview failure proves the underlying error is passed upward. BL's own suite owns the other invalid-address and amount boundaries.

| ID | Caller | Invalid request | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| BLCT-I01 | Authorized queue caller | amount=0; otherwise valid fixture | Bubble `BurnerLoans_ZeroAmount()`; no ID/key consumed; Unchanged | Covered: [preview rejects before conflict][test_whenPreviewRejectsBeforeConflict_reverts] |
| BLCT-I02 | Admin through raw batch queue | Payload truncated to one word or extended with a trailing word | `ITimelockBatchQueue_ActionInvalid(BLC, selector)` before preview; no ID/key consumed; Unchanged | Covered: [payload size][test_whenPendingRescuePayloadIsTruncatedOrHasTrailingWord_reverts] |

Also use this request when its conflict key is already owned: preview rejection must precede key conflict.

## Rescue-specific changes before execution

Execute the stored amount=4 at a valid ready timestamp. Assert the unchanged request reaches BLC then BL once. Success pays 4, updates entitlement, completes the action and releases its key. Failure leaves the action/key pending and rolls back payment/debt; match exact error data. Generic BLCT/BLC execution lifecycle cases stay in execute.t.sol. Rescue execution requires BLCT and BLC enabled and active; BL may be locally disabled.

| ID | Caller | Change after queue | Execution outcome / effects | Test |
| --- | --- | --- | --- | --- |
| BLCT-E03 | Executor | Entitlement increases to 12, decreases to 6, or equals 4; separately custody/surplus grows with entitlement still 10 | No hash invalidation; pay original 4, leaving entitlement 8,2,0,6 respectively | Covered: [entitlement increases][test_givenQueuedRequest_whenEntitlementIncreases], [entitlement decreases but remains sufficient][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient], [entitlement equals amount][test_givenQueuedRequest_whenEntitlementEqualsAmount], [custody increases][test_givenQueuedRequest_whenCustodyIncreases] |
| BLCT-E04 | Executor | Entitlement falls to 3 or is fully paid | `BurnerLoans_InsufficientPendingPayout(token,4,currentEntitlement)`; action/key retained, no payment | Covered: [entitlement is insufficient][test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts], [entitlement already paid][test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts] |
| BLCT-E05 | Executor | Token/destination rejects delivery or custody becomes insufficient | Bubble exact dependency error; full rollback. Shared empty/capped target-error wrapping is owned by execute.t.sol | Covered: [token rejects transfer][test_givenQueuedRequest_whenTokenRejectsTransfer_reverts], [custody is insufficient][test_givenQueuedRequest_whenCustodyIsInsufficient_reverts] |
| BLCT-E08 | Executor | BL becomes Kernel-inactive after a valid queue | `BurnerLoans_PolicyInactive()`; no payment; action/key retained | Covered: [facility becomes inactive][test_givenQueuedRequest_whenFacilityBecomesInactive_reverts] |
| BLCT-E09 | Executor | Fee routing changes; originalRecipient loses fee entitlement | `BurnerLoans_InsufficientPendingPayout(token,4,0)`; action/key retained, no payment | Covered: [routing changes][test_givenQueuedRoleRecipient_whenRoutingChanges_reverts] |
| BLCT-E11 | Executor | BLC disabled after queue; BL enabled/disabled; all policies active and BLCT enabled/selected | NotEnabled(); retain pending action/key and pay nothing | Covered: [config disabled][test_givenQueuedRequest_whenConfigDisabled_reverts] |
| BLCT-E10 | Executor | Treasury module upgraded; originalRecipient loses fee/seizure entitlement | `BurnerLoans_InsufficientPendingPayout(token,4,0)`; action/key retained, no payment | Covered: [treasury upgraded][test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts] |
| BLCT-E12 | Executor | BLCT disabled after valid queue; other gates pass | NotEnabled(); action/key retained; no payment | Covered: [executed][test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts] |

## Frozen timelock and mixed batches

| ID | Caller | Local state / request | Outcome / effects | Test |
| --- | --- | --- | --- | --- |
| BLCT-B01 | Admin; burner_loans_admin | BLC disabled; BLCT enabled/active/selected; batch contains either rescue and a setter, in both orders | Queue reverts NotEnabled; no ID, guards, keys or payment committed | Covered: [pending rescue and configuration are][test_givenConfigDisabled_whenPendingRescueAndConfigurationAreQueued_reverts], [surplus rescue and configuration are][test_givenConfigDisabled_whenSurplusRescueAndConfigurationAreQueued_reverts] |
| BLCT-B02 | Executor | Same mixed batch queued while BLC enabled, then BLC disabled | Execution reverts NotEnabled before payment; action, both keys and balances retained | Covered: [pending rescue and configuration are][test_givenConfigDisabled_whenPendingRescueAndConfigurationAreExecuted_reverts], [surplus rescue and configuration are][test_givenConfigDisabled_whenSurplusRescueAndConfigurationAreExecuted_reverts] |
| BLCT-B03 | Admin; burner_loans_admin | BLCT enabled/active/selected; BLC and BL disabled/active; rescue-only batch, both orders | Queue reverts NotEnabled; no ID/guards/keys/payment committed | Covered: [only rescues are batched][test_givenConfigAndFacilityDisabled_whenOnlyRescuesAreBatched_reverts] |
| BLCT-C01 | Emergency cancelling queued pending/surplus rescue | BLCT disabled/active or enabled/inactive; BLC active | NotEnabled or BurnerLoansConfigTimelock_PolicyInactive(BLCT); action/guard/key and funds retained | Covered: [frozen cancellation][test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts] |

For the routing-change rejection, use a fixed fee/Treasury recipient fixture with no other entitlement at originalRecipient. Do not reproduce BL bucket combinations.

[test_givenValidRequest_whenEachRoleQueues]: ./queueRescuePendingPayout.t.sol#L37
[test_whenQueueCallerIsUnauthorized_reverts]: ./queueRescuePendingPayout.t.sol#L447
[test_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./queueRescuePendingPayout.t.sol#L454
[test_givenTimelockDisabled_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L289
[test_whenQueueFaultsCompete_reverts]: ./queueRescuePendingPayout.t.sol#L463
[test_givenTimelockInactive_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L312
[test_givenConfigInactive_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L361
[test_givenConfigDisabled_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L338
[test_givenOperatorChanged_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L387
[test_givenFacilityInactive_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L413
[test_givenSameRecipientQueued_whenRequestChanges_reverts]: ./queueRescuePendingPayout.t.sol#L507
[test_givenIndependentRecipientsAndAssets_whenQueued]: ./queueRescuePendingPayout.t.sol#L538
[test_whenPreviewRejectsBeforeConflict_reverts]: ./queueRescuePendingPayout.t.sol#L486
[test_whenPendingRescuePayloadIsTruncatedOrHasTrailingWord_reverts]: ./queueBatch.t.sol#L28
[test_givenQueuedRequest_whenEntitlementIncreases]: ./queueRescuePendingPayout.t.sol#L589
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient]: ./queueRescuePendingPayout.t.sol#L623
[test_givenQueuedRequest_whenEntitlementEqualsAmount]: ./queueRescuePendingPayout.t.sol#L657
[test_givenQueuedRequest_whenCustodyIncreases]: ./queueRescuePendingPayout.t.sol#L691
[test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts]: ./queueRescuePendingPayout.t.sol#L722
[test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts]: ./queueRescuePendingPayout.t.sol#L764
[test_givenQueuedRequest_whenTokenRejectsTransfer_reverts]: ./queueRescuePendingPayout.t.sol#L890
[test_givenQueuedRequest_whenCustodyIsInsufficient_reverts]: ./queueRescuePendingPayout.t.sol#L911
[test_givenQueuedRequest_whenFacilityBecomesInactive_reverts]: ./queueRescuePendingPayout.t.sol#L935
[test_givenQueuedRoleRecipient_whenRoutingChanges_reverts]: ./queueRescuePendingPayout.t.sol#L807
[test_givenQueuedRequest_whenConfigDisabled_reverts]: ./queueRescuePendingPayout.t.sol#L60
[test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts]: ./queueRescuePendingPayout.t.sol#L854
[test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L274
[test_givenConfigDisabled_whenPendingRescueAndConfigurationAreQueued_reverts]: ./queueRescuePendingPayout.t.sol#L137
[test_givenConfigDisabled_whenSurplusRescueAndConfigurationAreQueued_reverts]: ./queueRescuePendingPayout.t.sol#L188
[test_givenConfigDisabled_whenPendingRescueAndConfigurationAreExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L162
[test_givenConfigDisabled_whenSurplusRescueAndConfigurationAreExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L213
[test_givenConfigAndFacilityDisabled_whenOnlyRescuesAreBatched_reverts]: ./queueRescuePendingPayout.t.sol#L89
[test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts]: ./cancel.t.sol#L26
