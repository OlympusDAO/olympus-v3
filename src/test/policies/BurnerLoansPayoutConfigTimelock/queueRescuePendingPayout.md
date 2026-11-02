# BurnerLoansPayoutConfigTimelock.queueRescuePendingPayout coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Coverage records implemented domains and assertions independently of pass/fail status.

Implemented responsibility change: this command queues a delayed call directly to the timelock's immutable Payout. The entry point is `queueRescuePendingPayout`. Tests below are linked only where their exercised domain is known; remaining rows are Unmapped.

## Domains and notation

Permitted proposers: ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE holders. Fuzz both exclusive classes and overlap; unauthorized callers exclude both classes. Execution is permissionless after the notice delay and through the inclusive expiry boundary. `Local` means this timelock. Payout stores this timelock as its configuration authority, without granting it ADMIN_ROLE. Authority is limited to the routing and recovery selectors; distributor replacement is a direct ADMIN-only call on Payout, outside this queue. Config and Core's selected Config are not in this forwarding path.

The queue binds to one concrete Payout. Core replacing its selected Payout does not retarget this queue: the old instance and its obligations remain independently recoverable. Payout enablement gates new credits, not recovery. Core activity/enablement and Payout activity are independent of routing/recovery admission; Core must be idle when the Payout write executes. Queue validation is read-only and does not reserve tokens or debit entitlements. `Unchanged` includes queue IDs, keys, payloads, target state, balances and committed logs on rejection.

Required queue infrastructure behavior: preserve the existing delay, expiry, scoped-key conflicts, pre-state commitments and whole-transaction rollback. Queue admission requires local activity/enablement and selected Payout authority; execution validates its recorded commitments; authority and inactivity errors are defined in IBurnerLoansPayoutConfigTimelock. Payout admits its local controller by address, without reverse lifecycle checks.

## Proposal authorization

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTRP-A01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Return queued action ID | No token movement or target setter event | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-A02 | Fuzz callers excluding every ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holder | true | true | NotAuthorised() | Unchanged; invalid payload cannot bypass role check | Covered: [test][test_givenUnauthorizedCaller_whenQueued_reverts] |

## Local lifecycle

Valid queue inputs and selected authority; fuzz the two permitted proposer roles independently and seed overlap. Execution lifecycle/time checks belong to [executeQueuedAction](executeQueuedAction.md).

| ID | Caller | Local active | Local enabled | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTRP-L01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Admitted | Queue metadata/key acquisition only; target unchanged | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-L02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabled_whenQueued_reverts] |
| BLCTRP-L03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Unchanged | Covered: [test][test_givenInactiveEnabled_whenQueued_reverts] |
| BLCTRP-L04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabled_whenQueued_reverts] |

## Payout authority and recovery availability

Local active/enabled; otherwise valid command. Core and Payout lifecycle do not gate read-only queue validation. The Payout flags are explicit independent inputs; no target state changes.

| ID | Caller | Core active | Core enabled | Payout active | Payout enabled | Payout controller | Result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTRP-D01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-D02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-D03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-D04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-D05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz true/false | Fuzz true/false | Fuzz true/false | Fuzz false/true | Another address | NotAuthorised(); no implicit ADMIN grant on the timelock | Covered: [test][test_givenControllerReplaced_whenQueued_reverts] |

## Queue commitments and conflicts

The queued sub-action targets the immutable Payout with selector `rescuePendingPayout` and canonical ABI encoding of `token,recipient,destination,amount`. Assert getQueuedAction, getQueuedActionLength=1, getQueuedSubAction, getQueuedConfigDestination, getQueuedConfigStateCount=1, getQueuedConfigState and pendingActionId against the exact input/committed state. Queueing consumes one ID and emits queue/config events only. Validation errors leave the next ID, all keys, metadata and payloads unchanged.

Expected local key: `keccak256(abi.encode(selector,token,recipient))`, with `selector=IBurnerLoansPayout.rescuePendingPayout.selector`. getQueuedConfigState returns the scoped key `keccak256(abi.encode(Payout,localKey))` and expected hash `keccak256(abi.encode(configOperator,sendFeesToDistributor,revenueDistributor,treasury))`. Balances and recipient entitlement are not committed.

Execution timing, commitment drift, target dispatch, bounded revert handling and terminal getter cleanup are covered in [executeQueuedAction](executeQueuedAction.md) and [cancelQueuedAction](cancelQueuedAction.md).

| ID | Caller | Queue condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTRP-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Valid payload; free scoped key | Return next ID | Exact metadata, payload, commitment and key owner returned by queue getters; no target mutation; exact queue events | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTRP-I01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Same selector/key already pending | ConfigKeyPending(key,owner) | No ID consumed; old action retained | Covered: [test][test_givenKeyAlreadyOwned_whenQueued_reverts] |

Payout.previewRescuePendingPayout validates live eligibility at queue time without reserving it. Queue unit tests mock the preview, assert its exact token/recipient/destination/amount arguments and propagate its exact errors. Payout's [rescuePendingPayout plan](../BurnerLoansPayout/rescuePendingPayout.md) owns eligibility, bucket ordering, overlap, transfers and indexes.

## Invalid addresses

Queue defaults: addresses and amounts are valid; all other prerequisites pass. Invalid fixed addresses reject at queue time and acquire no key. Live amounts may become invalid between queue and execution. Token=0 and no-code are distinct cases. Recipient is an entitlement owner; do not exclude destinations merely because they are another legitimate recipient.

| ID | Caller | Fault | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTRP-I02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | token=0 | BurnerLoans_InvalidAsset(0) | Unchanged | Covered: [test][test_whenTokenHasNoCode_reverts], [test][test_whenTokenZero_reverts] |
| BLCTRP-I03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | token nonzero EOA | BurnerLoans_InvalidAsset(token) | Unchanged | Covered: [test][test_whenTokenHasNoCode_reverts] |
| BLCTRP-I04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | recipient=0; valid destination/token | BurnerLoans_ZeroAddress() | Unchanged | Covered: [test][test_whenRecipientZero_reverts] |
| BLCTRP-I05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=zero | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationZero_reverts] |
| BLCTRP-I06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=Core | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationCore_reverts] |
| BLCTRP-I07 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=bound Payout | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationPayout_reverts] |
| BLCTRP-I08 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=token | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationToken_reverts] |
| BLCTRP-I09 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=this timelock | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationTimelock_reverts] |
| BLCTRP-I10 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=Kernel | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationKernel_reverts] |

## Amount bounds and eligibility

Use a preview stand-in to prove delegation, with independent requested amount Q and reported eligible amount A. Bounds, bucket arithmetic and allocation are owned by Payout; no execution or token-transfer fixture is needed here.

| ID | Caller | Entitlement / amount Q | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTRP-N01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Q=0; A independently zero/positive | BurnerLoansCore_ZeroAmount() | Unchanged | Covered: [test][test_whenAmountZero_reverts], [test][test_whenPendingAmountBoundarySeedsUsed_reverts] |
| BLCTRP-N02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | A=0; Q in 1..MAX256; seed 1,MAX256 | BurnerLoans_InsufficientPendingPayout(token,Q,0) | No ID/key consumed; target untouched | Covered: [test][test_givenNoEntitlement_whenPositiveAmountQueued_reverts], [test][test_whenPendingAmountBoundarySeedsUsed_reverts] |
| BLCTRP-N03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | 0<A<MAX256; Q in A+1..MAX256 | BurnerLoans_InsufficientPendingPayout(token,Q,A) | No ID/key consumed; target untouched | Covered: [test][test_givenInsufficientEntitlement_whenAmountQueued_reverts], [test][test_whenPendingAmountBoundarySeedsUsed_reverts] |
| BLCTRP-N06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Q=MAX256; preview accepts the exact arguments | Queue succeeds | Payload stores MAX256 unchanged; no transfer, entitlement debit or reservation | Covered: [test][test_whenMaximumAmountAcceptedByPreview_thenExactPayload] |

## Validation and state assertions

A successful queue stores the requested amount unchanged, including MAX256 after an accepting preview; it does not dispatch rescuePendingPayout, transfer tokens, reserve entitlement or emit a Payout rescue event. Failed previews leave all queue getters/counters/key owners unchanged. Test target arithmetic and token callbacks in [Payout.rescuePendingPayout](../BurnerLoansPayout/rescuePendingPayout.md); test post-queue entitlement drift and dispatch in [executeQueuedAction](executeQueuedAction.md). That plan includes success after an increase, after a decrease that still exceeds the request, and at exact remaining eligibility; only a drop below the request rejects.

- [ ] Implement queue admission, exact preview/payload and getter assertions.
- [ ] Map focused queue tests without duplicating target recovery cases.

## Inactive recovery target

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTRP-D06 | Fuzz ADMIN-only, BL-admin-only, overlap; seed all | true | true | Payout inactive; fuzz Core active/enabled and Payout enabled independently | BurnerLoans_PolicyNotActive(Payout) | No action/key, target-state or custody changes | Covered: [test][test_givenInactivePayout_whenPermittedProposerQueues_reverts] |

[test_givenControllerReplaced_whenQueued_reverts]: ./queueRescuePendingPayout.t.sol#L163
[test_givenActiveDisabled_whenQueued_reverts]: ./queueRescuePendingPayout.t.sol#L100
[test_givenInactiveEnabled_whenQueued_reverts]: ./queueRescuePendingPayout.t.sol#L141
[test_givenInsufficientEntitlement_whenAmountQueued_reverts]: ./queueRescuePendingPayout.t.sol#L343
[test_givenKeyAlreadyOwned_whenQueued_reverts]: ./queueRescuePendingPayout.t.sol#L188
[test_givenNoEntitlement_whenPositiveAmountQueued_reverts]: ./queueRescuePendingPayout.t.sol#L319
[test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards]: ./queueRescuePendingPayout.t.sol#L19
[test_givenUnauthorizedCaller_whenQueued_reverts]: ./queueRescuePendingPayout.t.sol#L78
[test_whenAmountZero_reverts]: ./queueRescuePendingPayout.t.sol#L300
[test_whenDestinationCore_reverts]: ./queueRescuePendingPayout.t.sol#L256
[test_whenDestinationKernel_reverts]: ./queueRescuePendingPayout.t.sol#L280
[test_whenDestinationPayout_reverts]: ./queueRescuePendingPayout.t.sol#L262
[test_whenDestinationTimelock_reverts]: ./queueRescuePendingPayout.t.sol#L274
[test_whenDestinationToken_reverts]: ./queueRescuePendingPayout.t.sol#L268
[test_whenDestinationZero_reverts]: ./queueRescuePendingPayout.t.sol#L250
[test_whenMaximumAmountAcceptedByPreview_thenExactPayload]: ./queueRescuePendingPayout.t.sol#L378
[test_whenPendingAmountBoundarySeedsUsed_reverts]: ./queueRescuePendingPayout.t.sol#L408
[test_whenProposerAndLifecycleSeedsUsed_thenExactQueue]: ./queueRescuePendingPayout.t.sol#L443
[test_whenRecipientZero_reverts]: ./queueRescuePendingPayout.t.sol#L286
[test_whenTokenHasNoCode_reverts]: ./queueRescuePendingPayout.t.sol#L226
[test_whenTokenZero_reverts]: ./queueRescuePendingPayout.t.sol#L245
[test_givenInactiveDisabled_whenQueued_reverts]: ./queueRescuePendingPayout.t.sol#L119
[test_givenInactivePayout_whenPermittedProposerQueues_reverts]: ./queueRescuePendingPayout.t.sol#L52
