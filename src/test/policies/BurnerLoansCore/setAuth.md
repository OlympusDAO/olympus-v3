# setAuth

Source: `BurnerLoansCore.setAuth`, implementation; existing `setRisk` provides admission precedent.
Caller authority is ADMIN. Local active/enabled are independent. Unchanged means the pointer, global
epoch, positions, balances, allowances and committed events remain unchanged.

| ID | Caller | Local active | Local enabled | Candidate | Execution/effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-AUTH-A01 | Fuzz excluding every ADMIN | true | true | Any | Exact ROLES role error; Unchanged | [unauthorized][test_whenCallerIsNotAdmin_reverts], [Config operator][test_whenCallerIsConfigOperator_reverts] |
| BLCORE-AUTH-P01 | ADMIN | true | true | Compatible ordinary Core-bound Auth | Pointer changes; global epoch +1; accounting unchanged | [replacement][test_whenAuthReplaced] |
| BLCORE-AUTH-L01 | ADMIN | true | false | Compatible Auth | Replace without enabling Core | [disabled recovery][test_givenCoreDisabled_whenAuthReplaced] |
| BLCORE-AUTH-P02 | ADMIN | true | true | A to B to A | Two checked increments; no restoration of old epoch | [return][test_whenOldAuthSelectedAgain] |
| BLCORE-AUTH-L02 | ADMIN | false | Fuzz false/true | Compatible Auth | Own inactivity error; Unchanged | [test_givenCoreInactive_whenAuthReplaced_reverts][test_givenCoreInactive_whenAuthReplaced_reverts] |
| BLCORE-AUTH-I01 | ADMIN | true | true | Zero/EOA/wrong Core/interface | Component InvalidAuth; Unchanged | [zero][test_whenZeroAuthSelected_reverts], [EOA][test_whenEoaSelected_reverts], [wrong Core][test_whenWrongCoreSelected_reverts], [core ABI][test_whenMalformedCoreBinding_reverts], [padding][test_whenNoncanonicalCoreAddress_reverts], [missing interface][test_whenRequiredAuthInterfaceMissing_reverts], [invalid sentinel][test_whenErc165InvalidInterfaceSupported_reverts], [short response][test_whenErc165ResponseTooShort_reverts], [reverting probe][test_whenErc165ProbeReverts_reverts] |
| BLCORE-AUTH-P03 | ADMIN | true | true | ERC165 positive response is a nonzero word | Standard ERC165Checker accepts; pointer changes, epoch +1, accounting unchanged | [nonzero word][test_whenErc165PositiveResponseNonzero] |
| BLCORE-AUTH-P04 | ADMIN | true | true | ERC165 negative sentinel returns zero followed by extra data | Standard ERC165Checker accepts; pointer changes, epoch +1, accounting unchanged | [trailing data][test_whenErc165NegativeResponseHasTrailingData] |
| BLCORE-AUTH-I02 | ADMIN | true | true | Current address | Unchanged-address error before probing | [test_whenUnchangedAuthSelected_reverts][test_whenUnchangedAuthSelected_reverts] |
| BLCORE-AUTH-N01 | ADMIN | true | true | Valid, global epoch uint256.max | Exhaustion, no wrapping, Unchanged | [test_givenExhaustedGlobalEpoch_whenAuthReplaced_reverts][test_givenExhaustedGlobalEpoch_whenAuthReplaced_reverts] |
| BLCORE-AUTH-C01 | ADMIN callback | true | true | Valid, Core settlement executing | Shared guard; caught outer success or propagated rollback | [test_givenSettlementCallback_whenAuthRotationCaught][test_givenSettlementCallback_whenAuthRotationCaught], [test_givenSettlementCallback_whenAuthRotationPropagated_reverts][test_givenSettlementCallback_whenAuthRotationPropagated_reverts] |
| BLCORE-AUTH-C02 | ADMIN during preparation | true | true | A to B to A | Original captured selection rejected at settlement entry | [test_givenCapturedOwner_whenAuthRotatesAndReturns_reverts][test_givenCapturedOwner_whenAuthRotatesAndReturns_reverts] |
| BLCORE-AUTH-P05 | Any viewer | true | true | Existing selected Auth | authConfig returns selected address and epoch together; standalone auth and globalAuthEpoch selectors absent | Covered: [combined getter][test_whenEpochRead_onlyCombinedGetterIsExposed] |
| BLCORE-AUTH-P06 | ADMIN | true | true | Compatible Auth/Core-bound interfaces and binding; version interface missing or VERSION getter reverts/returns oversized data | Pointer changes; epoch +1; accounting unchanged; no version metadata requirement | [unavailable version][test_whenVersionMetadataUnavailable], [oversized version][test_whenVersionGetterReturnsOversizedData] |

## Startup admission

| ID | State | Expected result | Test |
| --- | --- | --- | --- |
| BLCORE-AUTH-L03 | Auth unset; Core disabled; normal enable or recovery reEnable | InvalidAuth(0), remains disabled | [unset][test_givenAuthUnset_whenCoreEnabled_reverts] |

[test_givenAuthUnset_whenCoreEnabled_reverts]: ./setAuth.t.sol#L44
[test_givenCapturedOwner_whenAuthRotatesAndReturns_reverts]: ./authorizationLifecycleDeposit.t.sol#L19
[test_givenCoreDisabled_whenAuthReplaced]: ./setAuth.t.sol#L88
[test_givenCoreInactive_whenAuthReplaced_reverts]: ./setAuth.t.sol#L110
[test_givenExhaustedGlobalEpoch_whenAuthReplaced_reverts]: ./setAuth.t.sol#L353
[test_givenSettlementCallback_whenAuthRotationCaught]: ./authorizationLifecycleDeposit.t.sol#L67
[test_givenSettlementCallback_whenAuthRotationPropagated_reverts]: ./authorizationLifecycleDeposit.t.sol#L105
[test_whenAuthReplaced]: ./setAuth.t.sol#L76
[test_whenCallerIsConfigOperator_reverts]: ./setAuth.t.sol#L39
[test_whenCallerIsNotAdmin_reverts]: ./setAuth.t.sol#L66
[test_whenEoaSelected_reverts]: ./setAuth.t.sol#L136
[test_whenErc165NegativeResponseHasTrailingData]: ./setAuth.t.sol#L274
[test_whenErc165PositiveResponseNonzero]: ./setAuth.t.sol#L257
[test_whenVersionMetadataUnavailable]: ./setAuth.t.sol#L222
[test_whenMalformedCoreBinding_reverts]: ./setAuth.t.sol#L185
[test_whenNoncanonicalCoreAddress_reverts]: ./setAuth.t.sol#L202
[test_whenOldAuthSelectedAgain]: ./setAuth.t.sol#L98
[test_whenUnchangedAuthSelected_reverts]: ./setAuth.t.sol#L166
[test_whenVersionGetterReturnsOversizedData]: ./setAuth.t.sol#L244
[test_whenWrongCoreSelected_reverts]: ./setAuth.t.sol#L148
[test_whenZeroAuthSelected_reverts]: ./setAuth.t.sol#L125

[test_whenRequiredAuthInterfaceMissing_reverts]: ./setAuth.t.sol#L291
[test_whenErc165InvalidInterfaceSupported_reverts]: ./setAuth.t.sol#L308
[test_whenErc165ResponseTooShort_reverts]: ./setAuth.t.sol#L320
[test_whenErc165ProbeReverts_reverts]: ./setAuth.t.sol#L332

[test_whenEpochRead_onlyCombinedGetterIsExposed]: ./setAuth.t.sol#L28
