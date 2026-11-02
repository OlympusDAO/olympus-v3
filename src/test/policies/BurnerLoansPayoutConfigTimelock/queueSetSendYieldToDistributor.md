# BurnerLoansPayoutConfigTimelock.queueSetSendYieldToDistributor coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Coverage records implemented domains and assertions independently of pass/fail status.

Implemented responsibility change: this command queues a delayed call directly to the timelock's immutable Payout. The entry point is `queueSetSendYieldToDistributor`. Tests below are linked only where their exercised domain is known; remaining rows are Unmapped.

## Domains and notation

Permitted proposers: ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE holders. Fuzz both exclusive classes and overlap; unauthorized callers exclude both classes. Execution is permissionless after the notice delay and through the inclusive expiry boundary. `Local` means this timelock. Payout stores this timelock as its configuration authority, without granting it ADMIN_ROLE. Authority is limited to the routing and recovery selectors; distributor replacement is a direct ADMIN-only call on Payout, outside this queue. Config and Core's selected Config are not in this forwarding path.

The queue binds to one concrete Payout. Core replacing its selected Payout does not retarget this queue: the old instance and its obligations remain independently recoverable. Payout enablement gates new credits, not recovery. Core activity/enablement and Payout activity are independent of routing/recovery admission; Core must be idle when the Payout write executes. Queue validation is read-only and does not reserve tokens or debit entitlements. `Unchanged` includes queue IDs, keys, payloads, target state, balances and committed logs on rejection.

Required queue infrastructure behavior: preserve the existing delay, expiry, scoped-key conflicts, pre-state commitments and whole-transaction rollback. Queue admission requires local activity/enablement and selected Payout authority; execution validates its recorded commitments; authority and inactivity errors are defined in IBurnerLoansPayoutConfigTimelock. Payout admits its local controller by address, without reverse lifecycle checks.

## Proposal authorization

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTY-A01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Return queued action ID | No token movement or target setter event | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-A02 | Fuzz callers excluding every ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holder | true | true | NotAuthorised() | Unchanged; invalid payload cannot bypass role check | Covered: [test_givenUnauthorizedCaller_whenQueued_reverts](queueSetSendYieldToDistributor.t.sol#L47) |

## Local lifecycle

Valid queue inputs and selected authority; fuzz the two permitted proposer roles independently and seed overlap. Execution lifecycle/time checks belong to [executeQueuedAction](executeQueuedAction.md).

| ID | Caller | Local active | Local enabled | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTY-L01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Admitted | Queue metadata/key acquisition only; target unchanged | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-L02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | NotEnabled() | Unchanged | Covered: [test_givenActiveDisabled_whenQueued_reverts](queueSetSendYieldToDistributor.t.sol#L63) |
| BLCTY-L03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Unchanged | Covered: [test_givenInactiveEnabled_whenQueued_reverts](queueSetSendYieldToDistributor.t.sol#L96) |
| BLCTY-L04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test_givenInactiveDisabled_whenQueued_reverts](queueSetSendYieldToDistributor.t.sol#L78) |

## Payout authority and recovery availability

Local active/enabled; otherwise valid command. Core and Payout lifecycle do not gate read-only queue validation. The Payout flags are explicit independent inputs; no target state changes.

| ID | Caller | Core active | Core enabled | Payout active | Payout enabled | Payout controller | Result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTY-D01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Fuzz true/false | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-D02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | Fuzz true/false | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-D03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | Fuzz true/false | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-D04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | Fuzz true/false | Fuzz false/true | This timelock | Queue admitted with immutable Payout target | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-D05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz true/false | Fuzz true/false | Fuzz true/false | Fuzz false/true | Another address | NotAuthorised(); no implicit ADMIN grant on the timelock | Covered: [test_givenControllerReplaced_whenQueued_reverts](queueSetSendYieldToDistributor.t.sol#L114) |

## Queue commitments and conflicts

The queued sub-action targets the immutable Payout with selector `setSendYieldToDistributor` and canonical ABI encoding of `enabled`. Assert getQueuedAction, getQueuedActionLength=1, getQueuedSubAction, getQueuedConfigDestination, getQueuedConfigStateCount=1, getQueuedConfigState and pendingActionId against the exact input/committed state. Queueing consumes one ID and emits queue/config events only. Validation errors leave the next ID, all keys, metadata and payloads unchanged.

Expected local key: `keccak256(abi.encode(selector))`, with `selector=IBurnerLoansPayout.setSendYieldToDistributor.selector`. getQueuedConfigState returns the scoped key `keccak256(abi.encode(Payout,localKey))` and expected hash `keccak256(abi.encode(configOperator,sendYieldToDistributor,revenueDistributor))`. Balances and recipient entitlement are not committed. The key is independent of the distributor address: replacing the distributor cannot free an unresolved flag proposal. A changed distributor makes the old action fail its pre-state hash at execution; see [executeQueuedAction](executeQueuedAction.md).

Execution timing, commitment drift, target dispatch, bounded revert handling and terminal getter cleanup are covered in [executeQueuedAction](executeQueuedAction.md) and [cancelQueuedAction](cancelQueuedAction.md).

| ID | Caller | Queue condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTY-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Valid payload; free scoped key | Return next ID | Exact metadata, payload, commitment and key owner returned by queue getters; no target mutation; exact queue events | Covered: [test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards](queueSetSendYieldToDistributor.t.sol#L22), [test_whenProposerAndLifecycleSeedsUsed_thenExactQueue](queueSetSendYieldToDistributor.t.sol#L324) |
| BLCTY-I01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Same selector/key already pending | ConfigKeyPending(key,owner) | No ID consumed; old action retained | Covered: [test_givenKeyAlreadyOwned_whenQueued_reverts](queueSetSendYieldToDistributor.t.sol#L135) |

## Routing model

Old and new flag values vary independently; `sendFeesToDistributor` is crossed independently and remains unchanged. Every requested true validates the selected distributor, including true-to-true, before its required no-op. Requested false skips distributor validation. Payout implements unchanged-flag no-ops, after required validation for true. Queue performs read-only validation. An unchanged requested flag still queues a new action when its key is free; only Payout owns the eventual setter no-op. Distributor drift during the delay belongs to executeQueuedAction.

## Distributor validation

Timelock admission/selection passes. Old flag is independently false or true in each new=true row; guarantee both states. Other flag independently false/true. Mock validation to reject or use a real selected RD; assert validation is actually reached.

| ID | Caller | Old flag | New flag | Selected RD state | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTY-I02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | true | Interface compatible, same Kernel, active, enabled | Queue succeeds | Payout flag unchanged; validator called; canonical true payload stored; no target setter event | Covered: [test_whenTrueQueued_thenDistributorRevalidated](queueSetSendYieldToDistributor.t.sol#L164) |
| BLCTY-I03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Compatible, same Kernel, active, enabled | Queue succeeds after distributor revalidation | Flag unchanged; a new pending action is stored; no target setter event | Covered: [test_whenTrueQueued_thenDistributorRevalidated](queueSetSendYieldToDistributor.t.sol#L164) |
| BLCTY-I04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz false/true | true | RD pointer zero | BurnerLoans_RevenueDistributorRequired() | Unchanged | Covered: [test_givenNoDistributor_whenTrueQueued_reverts](queueSetSendYieldToDistributor.t.sol#L190) |
| BLCTY-I05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz false/true | true | RD Kernel-inactive, locally enabled | PolicyDependency_NotActive(RD) | Unchanged | Covered: [test_givenUnavailableDistributor_whenTrueQueued_reverts](queueSetSendYieldToDistributor.t.sol#L216) |
| BLCTY-I06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz false/true | true | RD Kernel-active, locally disabled | PolicyDependency_NotActive(RD) | Unchanged | Covered: [test_givenUnavailableDistributor_whenTrueQueued_reverts](queueSetSendYieldToDistributor.t.sol#L216) |
| BLCTY-I07 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz false/true | true | RD inactive and disabled | PolicyDependency_NotActive(RD) | Unchanged | Covered: [test_givenUnavailableDistributor_whenTrueQueued_reverts](queueSetSendYieldToDistributor.t.sol#L216) |
| BLCTY-I08 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz false/true | true | Stored RD reports different Kernel after migration | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | Unchanged | Covered: [test_givenDistributorKernelChanged_whenTrueQueued_reverts](queueSetSendYieldToDistributor.t.sol#L240) |
| BLCTY-I09 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz false/true | true | Payout validator raises its typed invalid-distributor error | BurnerLoans_InvalidRevenueDistributor(RD) propagates | No write/event; The timelock does not bypass validation | Covered: [test_givenValidatorRejects_whenTrueQueued_reverts](queueSetSendYieldToDistributor.t.sol#L263) |

## False requests and unchanged flags

| ID | Caller | Old flag | New flag | RD state | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTY-P02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | false | Fuzz zero, valid, inactive or disabled; expect validator not called | Queue succeeds | Canonical false payload stored; current flags/pointer/buckets unchanged; no target setter event | Covered: [test_whenFalseQueued_thenNoDistributorValidation](queueSetSendYieldToDistributor.t.sol#L289) |
| BLCTY-P03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | false | false | Same states; validation must not run | Queue succeeds | New pending action stored; same current flag; no target setter event | Covered: [test_whenFalseQueued_thenNoDistributorValidation](queueSetSendYieldToDistributor.t.sol#L289) |

Queue tests prove validator delegation and stored arguments, without executing the setter. [Payout.setSendYieldToDistributor](../BurnerLoansPayout/setSendYieldToDistributor.md) owns flag updates/no-ops/events and independence from setSendFeesToDistributor; [executeQueuedAction](executeQueuedAction.md) owns dispatch and rollback after delay.

Core replacement does not retarget this immutable queue. The Payout setter plan defines local authorization and exact target errors.
