# BurnerLoansComposites.disable scenarios

[EnablerV2.disable](../../../bases/EnablerV2.sol#L72) checks that Composites is enabled, then calls
[the Composites authorization hook](../../../periphery/BurnerLoansComposites.sol#L198). The hook
checks the current owner, the execution guard and the payload, in that order. The only valid
payload is empty bytes. The owner can pause even if Core is unavailable.

Unchanged means `isEnabled` and `lastTransitionAt` retain their previous values and no lifecycle
event commits. A successful pause emits `Disabled()` followed by
`Transition(owner, false, 0x, block.timestamp)` and records that timestamp. The
[execution scenarios](execute.md#7-dependency-lifecycle) cover the effect on both batch
entry points.

| ID | Caller | Enabled | Data | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCDIS-P01 | Owner | Yes, Core unavailable | Empty | Disable succeeds and records the pause transition | Covered: [test][test_givenEnabled_givenCoreUnavailable_whenOwnerDisables] |
| BLREX-L01 | Fuzz caller excluding the owner | Yes | Empty | `OwnableUnauthorizedAccount(caller)`. Unchanged | Covered: [fuzz][test_givenEnabled_whenNotOwnerDisables_reverts] |
| BLCDIS-L01 | Owner | No | Empty | `NotEnabled()`. Unchanged | Covered: [test][test_givenDisabled_whenOwnerDisablesAgain_reverts] |
| BLCDIS-I01 | Owner | Yes | One byte | `BurnerLoansComposites_InvalidEnablerData()`. Unchanged | Covered: [test][test_givenEnabled_whenDisableDataIsNonempty_reverts] |
| BLREX-L09 | Owner from a refund callback | Yes, execution locked | Empty | `ReentrancyGuardReentrantCall()`. Unchanged. The propagated failure also rolls back batch funding and lending effects | Covered: [test][test_givenReusableGrant_whenOwnerPausesDuringRefund_reverts] |
| BLREX-L10 | Prior and new owner after ownership acceptance | Yes | Empty | Prior owner receives `OwnableUnauthorizedAccount(priorOwner)`. New owner pauses successfully | Covered: [test][test_whenOwnershipIsAccepted] |

[test_givenEnabled_givenCoreUnavailable_whenOwnerDisables]: ./executeLifecycle.t.sol#L77
[test_givenEnabled_whenNotOwnerDisables_reverts]: ./executeLifecycle.t.sol#L18
[test_givenDisabled_whenOwnerDisablesAgain_reverts]: ./executeLifecycle.t.sol#L51
[test_givenEnabled_whenDisableDataIsNonempty_reverts]: ./executeLifecycle.t.sol#L60
[test_givenReusableGrant_whenOwnerPausesDuringRefund_reverts]: ./executeCallbacks.t.sol#L147
[test_whenOwnershipIsAccepted]: ./executeLifecycle.t.sol#L246
