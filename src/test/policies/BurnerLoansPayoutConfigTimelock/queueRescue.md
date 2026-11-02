# BurnerLoansPayoutConfigTimelock.queueRescue coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Coverage records implemented domains and assertions independently of pass/fail status.

Implemented responsibility change: this command queues a delayed call directly to the timelock's immutable Payout. The entry point is `queueRescue`. Tests below are linked only where their exercised domain is known; remaining rows are Unmapped.

## Domains and notation

Permitted proposers: ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE holders. Fuzz both exclusive classes and overlap; unauthorized callers exclude both classes. Execution is permissionless after the notice delay and through the inclusive expiry boundary. `Local` means this timelock. Payout stores this timelock as its configuration authority, without granting it ADMIN_ROLE. Authority is limited to the routing and recovery selectors; distributor replacement is a direct ADMIN-only call on Payout, outside this queue. Config and Core's selected Config are not in this forwarding path.

The queue binds to one concrete Payout. Core replacing its selected Payout does not retarget this queue: the old instance and its obligations remain independently recoverable. Payout enablement gates new credits, not recovery. Core activity/enablement and Payout activity are independent of routing/recovery admission; Core must be idle when the Payout write executes. Queue validation is read-only and does not reserve tokens or debit entitlements. `Unchanged` includes queue IDs, keys, payloads, target state, balances and committed logs on rejection.

Required queue infrastructure behavior: preserve the existing delay, expiry, scoped-key conflicts, pre-state commitments and whole-transaction rollback. Queue admission requires local activity/enablement and selected Payout authority; execution validates its recorded commitments; authority and inactivity errors are defined in IBurnerLoansPayoutConfigTimelock. Payout admits its local controller by address, without reverse lifecycle checks.

## Proposal authorization

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTR-A01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Return queued action ID | No token movement or target setter event | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-A02 | Fuzz callers excluding every ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holder | true | true | NotAuthorised() | Unchanged; invalid payload cannot bypass role check | Covered: [test][test_givenUnauthorizedCaller_whenQueued_reverts] |

## Local lifecycle

Valid queue inputs and selected authority; fuzz the two permitted proposer roles independently and seed overlap. Execution lifecycle/time checks belong to [executeQueuedAction](executeQueuedAction.md).

| ID | Caller | Local active | Local enabled | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTR-L01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Admitted | Queue metadata/key acquisition only; target unchanged | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-L02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabled_whenQueued_reverts] |
| BLCTR-L03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Unchanged | Covered: [test][test_givenInactiveEnabled_whenQueued_reverts] |
| BLCTR-L04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabled_whenQueued_reverts] |

## Payout authority and recovery availability

Local active/enabled; otherwise valid command. Core and Payout lifecycle do not gate read-only queue validation. The Payout flags are explicit independent inputs; no target state changes.

| ID | Caller | Core active | Core enabled | Payout active | Payout enabled | Payout controller | Result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTR-D01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-D02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-D03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-D04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | true | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-D05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz true/false | Fuzz true/false | Fuzz true/false | Fuzz false/true | Another address | NotAuthorised(); no implicit ADMIN grant on the timelock | Covered: [test][test_givenControllerReplaced_whenQueued_reverts] |

## Queue commitments and conflicts

The queued sub-action targets the immutable Payout with selector `rescue` and canonical ABI encoding of `token,destination`. Assert getQueuedAction, getQueuedActionLength=1, getQueuedSubAction, getQueuedConfigDestination, getQueuedConfigStateCount=1, getQueuedConfigState and pendingActionId against the exact input/committed state. Queueing consumes one ID and emits queue/config events only. Validation errors leave the next ID, all keys, metadata and payloads unchanged.

Expected local key: `keccak256(abi.encode(selector,token))`, with `selector=IBurnerLoansPayout.rescue.selector`. getQueuedConfigState returns the scoped key `keccak256(abi.encode(Payout,localKey))` and expected hash `keccak256(abi.encode(configOperator))`. Balances and recipient entitlement are not committed.

Execution timing, commitment drift, target dispatch, bounded revert handling and terminal getter cleanup are covered in [executeQueuedAction](executeQueuedAction.md) and [cancelQueuedAction](cancelQueuedAction.md).

| ID | Caller | Queue condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTR-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Valid payload; free scoped key | Return next ID | Exact metadata, payload, commitment and key owner returned by queue getters; no target mutation; exact queue events | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards], [test][test_whenProposerAndLifecycleSeedsUsed_thenExactQueue] |
| BLCTR-I01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Same selector/key already pending | ConfigKeyPending(key,owner) | No ID consumed; old action retained | Covered: [test][test_givenKeyAlreadyOwned_whenQueued_reverts] |

## Invalid inputs

Queue admission passes; vary one forbidden identity per case. Read-only queue validation rejects these fixed invalid inputs, so they are not executable queued actions.

| ID | Caller | Input | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTR-I02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | token=0 | BurnerLoans_InvalidAsset(0) | Unchanged | Covered: [test][test_whenTokenHasNoCode_reverts], [test][test_whenTokenZero_reverts] |
| BLCTR-I03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Nonzero token without code | BurnerLoans_InvalidAsset(token) | Unchanged | Covered: [test][test_whenTokenHasNoCode_reverts] |
| BLCTR-I04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=zero | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationZero_reverts] |
| BLCTR-I05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=Core | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationCore_reverts] |
| BLCTR-I06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=bound Payout | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationPayout_reverts] |
| BLCTR-I07 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=token | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationToken_reverts] |
| BLCTR-I08 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=this timelock | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationTimelock_reverts] |
| BLCTR-I09 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | destination=Kernel | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationKernel_reverts] |

Payout's [rescue plan](../BurnerLoansPayout/rescue.md) owns surplus arithmetic, transfers and token callbacks. Queue tests assert that previewRescue receives the exact token/destination and that the rescue setter is never called. They do not reproduce zero/nonzero surplus or token-transfer cases.

## Regression evidence and completion

Use [existing Config rescue tests](../BurnerLoansConfig/rescue.t.sol) for invalid-address and forwarding examples; token balances and rollback remain target-owned proofs.

- [ ] Implement queue admission, exact preview/payload and getter assertions.
- [ ] Map focused queue tests without duplicating target recovery cases.

## Inactive recovery target

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTR-D06 | Fuzz ADMIN-only, BL-admin-only, overlap; seed all | true | true | Payout inactive; fuzz Core active/enabled and Payout enabled independently | BurnerLoans_PolicyNotActive(Payout) | No action/key, target-state or custody changes | Covered: [test][test_givenInactivePayout_whenPermittedProposerQueues_reverts] |

[test_givenControllerReplaced_whenQueued_reverts]: ./queueRescue.t.sol#L129
[test_givenActiveDisabled_whenQueued_reverts]: ./queueRescue.t.sol#L78
[test_givenInactiveEnabled_whenQueued_reverts]: ./queueRescue.t.sol#L111
[test_givenKeyAlreadyOwned_whenQueued_reverts]: ./queueRescue.t.sol#L150
[test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards]: ./queueRescue.t.sol#L16
[test_givenUnauthorizedCaller_whenQueued_reverts]: ./queueRescue.t.sol#L62
[test_whenDestinationCore_reverts]: ./queueRescue.t.sol#L206
[test_whenDestinationKernel_reverts]: ./queueRescue.t.sol#L230
[test_whenDestinationPayout_reverts]: ./queueRescue.t.sol#L212
[test_whenDestinationTimelock_reverts]: ./queueRescue.t.sol#L224
[test_whenDestinationToken_reverts]: ./queueRescue.t.sol#L218
[test_whenDestinationZero_reverts]: ./queueRescue.t.sol#L200
[test_whenProposerAndLifecycleSeedsUsed_thenExactQueue]: ./queueRescue.t.sol#L236
[test_whenTokenHasNoCode_reverts]: ./queueRescue.t.sol#L179
[test_whenTokenZero_reverts]: ./queueRescue.t.sol#L195
[test_givenInactiveDisabled_whenQueued_reverts]: ./queueRescue.t.sol#L93
[test_givenInactivePayout_whenPermittedProposerQueues_reverts]: ./queueRescue.t.sol#L40
