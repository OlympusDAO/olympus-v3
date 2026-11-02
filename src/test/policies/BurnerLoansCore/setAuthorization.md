# BurnerLoansCore.setAuthorization coverage plan

Source: [setAuthorization](../../../policies/utils/OperatorAuth.sol#L64). Acceptance plan; coverage and execution results are recorded separately.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-AUTHORIZATION` identifies this contract/function.

Permissionless for msg.sender own grant only while Core is active and enabled. Core activity precedes local enablement; both precede shared OperatorAuth input/nonce validation. Body rows fix both flags true. Cancellation remains available in every lifecycle state. Operator may be zero but must differ from account; deadline is uint48.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: No deadline update.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-AUTHORIZATION-A01 | Fuzz account | nonce=uint256.max focused storage-boundary fixture | OperatorAuth_NonceExhausted(account) | Covered: [test][test_givenExhaustedNonce_whenGranted_reverts] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-AUTHORIZATION-I01 | Fuzz account | operator=account, deadline valid/expired | SelfAuthorization before ExpiredAuthorization when both invalid | Covered: [test][test_givenSelfAndExpiredDeadline_whenGranted_reverts] |

## Grant deadline inputs

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-AUTHORIZATION-I02 | Fuzz account | operator distinct; independently fuzz now in 1..MAX48 and deadline in 0..now-1; seed0,now-1,now=MAX48 | ExpiredAuthorization(deadline) | Unchanged | Covered: [test][test_givenExpiredDeadline_whenGranted_reverts], [test][test_whenExpiredDeadlineBoundarySeeds_reverts] |
| BLCORE-AUTHORIZATION-I03 | Fuzz account | operator distinct; independently fuzz now in 1..MAX48 and deadline in now..MAX48; seed now,MAX48; existing/absent/same grant | Deadline stored; nonce increments; expiry equality authorized | AuthorizationSet caller/account both msg.sender; same grant still consumes nonce | Covered: [test][test_givenValidDeadline_whenGranted], [test][test_whenDeadlineBoundarySeeds], [test][test_givenExistingGrant_whenSameGrantRepeated] |

## Own policy activity

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-AUTHORIZATION-P01 | Fuzz account | true | true | Success with valid request | Grant/nonce effects only; no role or settlement admission | Covered: [test][test_givenValidDeadline_whenGranted] |
| BLCORE-AUTHORIZATION-L01 | Fuzz account | true | false | NotEnabled() | Existing grant/nonce unchanged; no logs, including with invalid inputs | Covered: [test][test_givenUnavailableCore_whenGranted_reverts], [invariant_lifecycleAuthorizationAndCustodyStayIndependent](setAuthorization.t.sol#L193) |
| BLCORE-AUTHORIZATION-L02 | Fuzz account | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Existing grant/nonce unchanged; no logs, including with invalid inputs | Covered: [test][test_givenUnavailableCore_whenGranted_reverts], [invariant_lifecycleAuthorizationAndCustodyStayIndependent](setAuthorization.t.sol#L193) |
| BLCORE-AUTHORIZATION-L03 | Fuzz account | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Activity rejection precedes enablement and input checks | Covered: [test][test_givenUnavailableCore_whenGranted_reverts], [invariant_lifecycleAuthorizationAndCustodyStayIndependent](setAuthorization.t.sol#L193) |

Retired IDs BLCORE-AUTHORIZATION-P02/P03/P04 described the superseded inactive/disabled-success requirement. Restore activity and enablement, then retry; a rejected request must not consume a nonce or replace an existing grant.

## Shared assertions

Co-locate isSenderAuthorized: self always true; other caller false at absent/zero, true through deadline, false after. Cancelled grant invalidates; independent account/operator entries stay unchanged. DOMAIN_SEPARATOR remains Core address, fork chain ID recomputed and initial-chain ID restored.

Co-located API assertions: `authorizationDeadlines`, `authorizationNonces`, `isSenderAuthorized`, `DOMAIN_SEPARATOR`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Existing tests informing this plan

- [setAuthorization.t.sol](../utils/OperatorAuth/setAuthorization.t.sol) — 8 legacy tests; retain relevant input/interaction families and compare expected behavior against the source above.
    - [test_setAuthorization_givenBeforeDeadline_authorizesOperator](../utils/OperatorAuth/setAuthorization.t.sol#L14).
    - [test_setAuthorization_givenSelfAuthorization_reverts](../utils/OperatorAuth/setAuthorization.t.sol#L68).
    - [test_setAuthorization_givenPendingSignature_invalidatesSignature](../utils/OperatorAuth/setAuthorization.t.sol#L105).

These links are regression evidence and migration inputs. They are not `Covered` mappings for the rewritten API; inherited legacy fixture assumptions, mock authority, fuzz bounds and callback routes must be adapted before coverage is claimed.

## Nonce exhaustion

Implemented shared OperatorAuth behavior: reject incrementing MAX256 with OperatorAuth_NonceExhausted(account). Preserve grants/nonces and commit no events. MAX256-1 remains usable once, resulting in MAX256; all subsequent increments fail without wraparound. Direct set, cancellation and signed authorization use the same typed exhaustion behavior. Signed nonce mismatch is checked before exhaustion; both precede recovery/signer checks. Nonce mismatch is checked before the checked increment; no panic or wraparound replaces either typed error.

| ID | Caller | Nonce / request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-AUTHORIZATION-P05 | Fuzz account | Current nonce=MAX256-1; otherwise valid request | Success | Nonce becomes MAX256 once; exact grant/event | Covered: [test][test_givenValidDeadline_whenGranted], [test][test_whenDeadlineBoundarySeeds] |

[test_givenExhaustedNonce_whenGranted_reverts]: setAuthorization.t.sol#L145
[test_givenExistingGrant_whenSameGrantRepeated]: setAuthorization.t.sol#L84
[test_givenExpiredDeadline_whenGranted_reverts]: setAuthorization.t.sol#L99
[test_givenSelfAndExpiredDeadline_whenGranted_reverts]: setAuthorization.t.sol#L132
[test_givenUnavailableCore_whenGranted_reverts]: setAuthorization.t.sol#L161
[test_givenValidDeadline_whenGranted]: setAuthorization.t.sol#L37
[test_whenDeadlineBoundarySeeds]: setAuthorization.t.sol#L71
[test_whenExpiredDeadlineBoundarySeeds_reverts]: setAuthorization.t.sol#L121
