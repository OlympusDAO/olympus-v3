# BurnerLoansAuth.cancelGrant

Source: inherited `OperatorAuth.cancelGrant`. These integration tests call the selected Auth with
real Core and registered collateral. Borrower A owns grants for distinct operators O and X.
Core is active/enabled unless the row varies enablement. Cancellation bypasses Core readiness.
The generic [cancelGrant scenarios](../utils/OperatorAuth/cancelGrant.md) own zero/self identities
and the complete engine input matrix.

| ID | Caller / input | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLAUTH-CANCEL-P01 | A; existing A→O and A→X grants; cancel O | Success | O pair epoch becomes two; O loses authority; X remains authorized | Covered: [test][test_whenPairCancelled] |
| BLAUTH-CANCEL-L01 | A; Core disabled after approval | Cancellation succeeds; Core can subsequently be enabled | Pair epoch becomes two while paused; O stays unauthorized after enablement | Covered: [test][test_whenCancelledWhileDisabled] |
| BLAUTH-CANCEL-N01 | A; O pair epoch MAX256 | OperatorAuth_EpochExhausted | No wrap or committed change | Covered: [test][test_whenCancellationEpochExhausted_reverts] |
| BLAUTH-CANCEL-N02 | A; O pair epoch MAX256-1 | Success | Pair epoch becomes MAX256 | Covered: [test][test_whenLastPairEpochCancelled] |
| BLAUTH-CANCEL-A01 | Fuzz caller C excluding A, O and zero; existing A→O grant | C cancels its own absent C→O pair | C pair epoch becomes one; A→O remains authorized | Covered: [test][test_whenUnrelatedAccountCancels] |

[test_whenPairCancelled]: ./cancelGrantCoreIntegration.t.sol#L11
[test_whenCancelledWhileDisabled]: ./cancelGrantCoreIntegration.t.sol#L25
[test_whenCancellationEpochExhausted_reverts]: ./cancelGrantCoreIntegration.t.sol#L39
[test_whenLastPairEpochCancelled]: ./cancelGrantCoreIntegration.t.sol#L47
[test_whenUnrelatedAccountCancels]: ./cancelGrantCoreIntegration.t.sol#L59
