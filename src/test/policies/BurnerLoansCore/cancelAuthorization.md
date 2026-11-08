# BurnerLoansCore.cancelAuthorization coverage plan

Source: [cancelAuthorization](../../../policies/utils/OperatorAuth.sol#L147). Acceptance plan; coverage and execution results are recorded separately.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-CANCEL-AUTH` identifies this contract/function.

Permissionless for msg.sender own grant, callable in every Core lifecycle state. No operator address/self/zero validation. Cancellation also consumes global per-account nonce.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: All grant state unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-CANCEL-AUTH-A01 | Fuzz account | nonce=uint256.max | OperatorAuth_NonceExhausted(account) | Covered: [test][test_givenExhaustedNonce_whenCancelled_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CANCEL-AUTH-P01 | Fuzz account | Absent/existing grant; operator=self/zero/other | Delete selected grant; nonce+1 | AuthorizationSet(account,account,operator,0) even if absent | Covered: [test][test_givenAnyLifecycle_whenCancelled], [test][test_whenCancellationBoundarySeeds] |
| BLCORE-CANCEL-AUTH-P02 | Fuzz account | Multiple operators and previously signed grants | Only selected deadline deleted; all old signed nonces obsolete | Other stored deadlines remain valid until expiry | Covered: [test][test_givenMultipleGrants_whenOneCancelled] |

Co-located API assertions: `authorizationDeadlines`, `authorizationNonces`, `isSenderAuthorized`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Own policy activity

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-CANCEL-AUTH-P03 | Fuzz account | true | true | Success with valid request | Grant/nonce effects only; no role or settlement admission | Covered: [test][test_givenAnyLifecycle_whenCancelled], [invariant_lifecycleAuthorizationAndCustodyStayIndependent][invariant_lifecycleAuthorizationAndCustodyStayIndependent] |
| BLCORE-CANCEL-AUTH-P04 | Fuzz account | true | false | Success with valid request | Grant/nonce effects only; no role or settlement admission | Covered: [test][test_givenAnyLifecycle_whenCancelled], [invariant_lifecycleAuthorizationAndCustodyStayIndependent][invariant_lifecycleAuthorizationAndCustodyStayIndependent] |
| BLCORE-CANCEL-AUTH-P05 | Fuzz account | false | true | Success with valid request | Grant/nonce effects only; no role or settlement admission | Covered: [test][test_givenAnyLifecycle_whenCancelled], [invariant_lifecycleAuthorizationAndCustodyStayIndependent][invariant_lifecycleAuthorizationAndCustodyStayIndependent] |
| BLCORE-CANCEL-AUTH-P06 | Fuzz account | false | false | Success with valid request | Grant/nonce effects only; no role or settlement admission | Covered: [test][test_givenAnyLifecycle_whenCancelled], [invariant_lifecycleAuthorizationAndCustodyStayIndependent][invariant_lifecycleAuthorizationAndCustodyStayIndependent] |

## Existing tests informing this plan

- [cancelAuthorization.t.sol](../utils/OperatorAuth/cancelAuthorization.t.sol) — 6 legacy tests; retain relevant input/interaction families and compare expected behavior against the source above.
    - [test_cancelAuthorization_givenNoAuthorizationExists_clearsWithoutRevert](../utils/OperatorAuth/cancelAuthorization.t.sol#L14).
    - [test_cancelAuthorization_givenExistingNonce](../utils/OperatorAuth/cancelAuthorization.t.sol#L57).
    - [test_cancelAuthorization_givenCallerIsNotOwner_clearsOnlyCallerAuthorization](../utils/OperatorAuth/cancelAuthorization.t.sol#L109).

These links are regression evidence and migration inputs. They are not `Covered` mappings for the rewritten API; inherited legacy fixture assumptions, mock authority, fuzz bounds and callback routes must be adapted before coverage is claimed.

## Nonce exhaustion

Implemented shared OperatorAuth behavior: reject incrementing MAX256 with OperatorAuth_NonceExhausted(account). Preserve grants/nonces and commit no events. MAX256-1 remains usable once, resulting in MAX256; all subsequent increments fail without wraparound. Direct set, cancellation and signed authorization use the same typed exhaustion behavior. Signed nonce mismatch is checked before exhaustion; both precede recovery/signer checks. Nonce mismatch is checked before the checked increment; no panic or wraparound replaces either typed error.

| ID | Caller | Nonce / request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CANCEL-AUTH-P07 | Fuzz account | Current nonce=MAX256-1; otherwise valid request | Success | Nonce becomes MAX256 once; exact grant/event | Covered: [test][test_givenAnyLifecycle_whenCancelled], [test][test_whenCancellationBoundarySeeds] |

[test_givenAnyLifecycle_whenCancelled]: cancelAuthorization.t.sol#L12
[test_givenExhaustedNonce_whenCancelled_reverts]: cancelAuthorization.t.sol#L57
[test_givenMultipleGrants_whenOneCancelled]: cancelAuthorization.t.sol#L72
[test_whenCancellationBoundarySeeds]: cancelAuthorization.t.sol#L44

[invariant_lifecycleAuthorizationAndCustodyStayIndependent]: setAuthorization.t.sol#L193
