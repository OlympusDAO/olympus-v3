# BurnerLoansAuth authorization under Core rotation

Sources: `src/policies/burnerloans/BurnerLoansAuth.sol` and inherited `OperatorAuth`.

The Core mock models selection, reported Kernel and global epoch; actual guarded setAuth/custody behavior is proved in Core tests. Auth stores local counters. The invariant covers reusable authority and two operators across two Auth instances; it is not a token-accounting or signature invariant.

| ID | Caller / domain | Execution and effects | Test |
| --- | --- | --- | --- |
| BLAUTH-ROTATE-P01 | Reusable grant; A to B to A | Old authority rejected; A-local pair counter retained; reapproval advances it | Covered: [test][test_givenReusableGrant_whenAuthReturns_oldGrantDoesNotRevive] |
| BLAUTH-ROTATE-P02 | Temporary acceptance/use and A to B to A in one nested transaction | Before-rotation authority succeeds; old transient bytes never revive | Covered: [test][test_givenTemporaryGrant_whenSameTransactionAuthReturns_oldGrantDoesNotRevive] |
| BLAUTH-ROTATE-I01 | Unaccepted A signature; A to B to A | InvalidContext; old signature consumes no epoch | Covered: [test][test_givenOldSignature_whenAuthReturns_reverts] |
| BLAUTH-ROTATE-P03 | B-domain future epoch signature; A.cancelAll then B selected | B request succeeds if B-local epochs match; explicit instance-scoped cancellation | Covered: [test][test_givenFutureOtherAuthSignature_whenCurrentAuthCancelled_otherNamespaceUnaffected] |
| BLAUTH-ROTATE-P04 | Retired Auth; Core active false, enabled false; account | Pair/account cancellation succeed locally without readiness | Covered: [test][test_givenRetiredAndInactiveAuth_whenAccountCancels] |
| BLAUTH-ROTATE-P05 | Stateful accept, pair/account cancel, rotate across two Auths/operators | Independent global/local epoch and liveness model always matches | Covered: [test][invariant_authorityMatchesIndependentInstanceAndEpochModel] |
| BLAUTH-ROTATE-P06 | Core reports new Kernel; replacement Auth independently bound to it | Old Auth rejects admission; selected replacement accepts; old pair/account cancellation stays local and available | Covered: [replacement][test_givenCoreReportsNewKernel_whenAuthReplaced_oldCancellationRemainsAvailable] |

[invariant_authorityMatchesIndependentInstanceAndEpochModel]: ./authorization.invariants.t.sol#L30
[test_givenFutureOtherAuthSignature_whenCurrentAuthCancelled_otherNamespaceUnaffected]: ./rotation.t.sol#L136
[test_givenOldSignature_whenAuthReturns_reverts]: ./rotation.t.sol#L120
[test_givenRetiredAndInactiveAuth_whenAccountCancels]: ./rotation.t.sol#L166
[test_givenReusableGrant_whenAuthReturns_oldGrantDoesNotRevive]: ./rotation.t.sol#L74
[test_givenTemporaryGrant_whenSameTransactionAuthReturns_oldGrantDoesNotRevive]: ./rotation.t.sol#L96

[test_givenCoreReportsNewKernel_whenAuthReplaced_oldCancellationRemainsAvailable]: ./rotation.t.sol#L21
