# BurnerLoansComposites.enable scenarios

[EnablerV2.enable](../../../bases/EnablerV2.sol#L52) checks that Composites is disabled, then calls
[the Composites authorization hook](../../../periphery/BurnerLoansComposites.sol#L187). The hook
checks the current owner, the execution guard and the payload, in that order. The only valid
payload is empty bytes. Composites starts disabled. The owner calls `enable("")` both for first
enablement and to resume after a pause. Lending readiness is checked when a batch runs.

Unchanged means `isEnabled` and `lastTransitionAt` retain their previous values and no lifecycle
event commits. A successful transition emits `Enabled()` followed by
`Transition(owner, true, 0x, block.timestamp)` and records that timestamp.

| ID | Caller | Enabled | Data | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCEN-P01 | Owner | No, newly deployed | Empty | First enable succeeds and records the transition | Covered: [test][test_whenDeployed] |
| BLCEN-P02 | Owner | No, previously paused | Empty | Enable succeeds and records the transition. A reusable grant and an unused signed grant remain usable in their respective entry points | Covered: [direct][test_givenReusableGrant_whenOwnerPausesAndResumes], [signed][test_givenSignedGrant_whenOwnerPausesAndResumes] |
| BLREX-L02 | Fuzz caller excluding the owner | No | Empty | `OwnableUnauthorizedAccount(caller)`. Unchanged | Covered: [fuzz][test_givenDisabled_whenNotOwnerEnables_reverts] |
| BLREX-L03 | Owner | Yes | Empty | `NotDisabled()`. Unchanged | Covered: [test][test_givenEnabled_whenOwnerEnablesAgain_reverts] |
| BLREX-L04 | Owner | No | One byte | `BurnerLoansComposites_InvalidEnablerData()`. Unchanged | Covered: [test][test_givenDisabled_whenEnableDataIsNonempty_reverts] |

[test_whenDeployed]: ./executeLifecycle.t.sol#L208
[test_givenReusableGrant_whenOwnerPausesAndResumes]: ./executeLifecycle.t.sol#L87
[test_givenSignedGrant_whenOwnerPausesAndResumes]: ./executeLifecycle.t.sol#L125
[test_givenDisabled_whenNotOwnerEnables_reverts]: ./executeLifecycle.t.sol#L30
[test_givenEnabled_whenOwnerEnablesAgain_reverts]: ./executeLifecycle.t.sol#L43
[test_givenDisabled_whenEnableDataIsNonempty_reverts]: ./executeLifecycle.t.sol#L68
