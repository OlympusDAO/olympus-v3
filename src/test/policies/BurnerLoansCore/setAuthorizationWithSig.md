# BurnerLoansCore.setAuthorizationWithSig coverage plan

Source: [setAuthorizationWithSig](../../../policies/utils/OperatorAuth.sol#L96). Acceptance plan; coverage and execution results are recorded separately.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-AUTH-SIG` identifies this contract/function.

Relayer permissionless while Core is active and enabled. Action lifecycle is not consulted. Signature encodes account, authorized, uint48 authorizationDeadline, uint256 nonce and uint48 signatureDeadline in Core EIP-712 domain; Core verifies the signature and updates its own registry.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

No role or action binding is required. Core activity precedes local enablement; both precede signature deadlines, grant deadlines, nonce and recovery. Body rows fix Core active/enabled. Cross all four lifecycle states with valid and malformed signatures. Cancellation remains usable while paused or inactive.

## Authorization

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-AUTH-SIG-A01 | Fuzz all relayers | independently fuzz now in 1..MAX48 and signatureDeadline in 0..now-1; seed0,now-1; other fields valid | OperatorAuth_ExpiredSignature(deadline) | Unchanged; no committed logs | Covered: [test][test_givenExpiredSignature_whenRelayed_reverts], [test][test_whenSignatureExpiryBoundarySeeds_reverts] |
| BLCORE-AUTH-SIG-A02 | Fuzz all relayers | signatureDeadline=now; authorizationDeadline>=now; nonce/current signature valid | Success | Consume nonce once; AuthorizationSet(actualRelayer,account,operator,deadline) | Covered: [test][test_givenValidSignature_whenRelayed], [test][test_whenSignatureBoundarySeeds] |
| BLCORE-AUTH-SIG-A03 | Fuzz all relayers | now<MAX48; independently fuzz signatureDeadline in now+1..MAX48; seed now+1,MAX48; other fields valid | Success | Consume nonce once; account/operator-specific grant | Covered: [test][test_givenValidSignature_whenRelayed] |
| BLCORE-AUTH-SIG-A04 | Fuzz all relayers | signatureDeadline=MAX48; other fields valid | Success | Signature deadline inclusive | Covered: [test][test_givenValidSignature_whenRelayed], [test][test_whenSignatureBoundarySeeds] |
| BLCORE-AUTH-SIG-A05 | Fuzz all relayers | Signature deadline valid; independently fuzz now in 1..MAX48 and authorizationDeadline in 0..now-1; seed0,now-1; operator=account | OperatorAuth_ExpiredAuthorization(deadline) | Authorization deadline precedes self check | Covered: [test][test_givenExpiredAuthorizationAndSelf_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-A06 | Fuzz all relayers | Signed nonce differs from current; valid deadlines/operator; fuzz0..MAX256 excluding current | OperatorAuth_InvalidNonce(submitted) | Unchanged; no committed logs | Covered: [test][test_givenWrongNonce_whenRelayed_reverts], [test][test_givenExhaustedNonceAndMismatch_whenRelayed_reverts], [test][test_whenNonceMismatchMaximumSeed_reverts] |
| BLCORE-AUTH-SIG-A07 | Fuzz all relayers | Deadlines/operator/nonce valid; high-s signature | ECDSAInvalidSignatureS(s) | Unchanged; no committed logs | Covered: [test][test_givenHighS_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-A08 | Fuzz all relayers | Deadlines/operator/nonce valid; invalid v or zero recovery; independently seed each malformed field | ECDSAInvalidSignature() | Provisional nonce increment rolls back | Covered: [test][test_givenBadV_whenRelayed_reverts], [test][test_givenZeroRecovery_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-A09 | Fuzz all relayers | Recoverable signature from another signer | OperatorAuth_InvalidSigner(recovered,account) | Grant and provisional nonce roll back | Covered: [test][test_givenDifferentSigner_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-A10 | Fuzz all relayers | Recoverable signature for wrong chain/Core/domain or altered signed field; each field individually | OperatorAuth_InvalidSigner(recovered,account) | No cross-domain grant/replay | Covered: [test][test_givenWrongChain_whenRelayed_reverts], [test][test_givenWrongCore_whenRelayed_reverts], [test][test_givenWrongDomain_whenRelayed_reverts], [test][test_givenAlteredAccount_whenRelayed_reverts], [test][test_givenAlteredOperator_whenRelayed_reverts], [test][test_givenAlteredAuthorizationDeadline_whenRelayed_reverts], [test][test_givenAlteredNonce_whenRelayed_reverts], [test][test_givenAlteredSignatureDeadline_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-A11 | Fuzz all relayers | Valid signature; nonce=MAX256 equals current injected nonce | OperatorAuth_NonceExhausted(account) | Increment overflow rolls back grant and nonce | Covered: [test][test_givenExhaustedNonce_whenMatchingSignatureRelayed_reverts] |
| BLCORE-AUTH-SIG-A12 | Fuzz all relayers | Valid unused signature; public action replaced | Success | Core-domain signature remains valid; exactly one grant/nonce | Covered: [test][test_givenActionReplacement_whenRelayed] |
| BLCORE-AUTH-SIG-A13 | Fuzz all relayers | Previously consumed signature submitted again | OperatorAuth_InvalidNonce(submitted) | No duplicate grant/nonce increment | Covered: [test][test_givenValidSignature_whenReplayed_reverts] |
| BLCORE-AUTH-SIG-A14 | Fuzz all relayers | Account cancels grant before submitting an older valid signed nonce | OperatorAuth_InvalidNonce(submitted) | Cancelled deadline0 retained | Covered: [test][test_givenCancellation_whenOldSignatureRelayed_reverts] |

## Successful execution

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-AUTH-SIG-P01 | Fuzz all relayers | Deadlines valid; operator=account | OperatorAuth_SelfAuthorization() | Covered: [test][test_givenSelfGrant_whenRelayed_reverts] |

## Own policy activity

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-AUTH-SIG-P02 | Fuzz all relayers | true | true | Success with valid request | Grant/nonce effects only; no role or settlement admission | Covered: [test][test_givenValidSignature_whenRelayed] |
| BLCORE-AUTH-SIG-L01 | Fuzz all relayers | true | false | NotEnabled() | Grant/nonce unchanged; no logs for valid or malformed signatures | Covered: [test][test_givenUnavailableCore_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-L02 | Fuzz all relayers | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Grant/nonce unchanged; no logs for valid or malformed signatures | Covered: [test][test_givenUnavailableCore_whenRelayed_reverts] |
| BLCORE-AUTH-SIG-L03 | Fuzz all relayers | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Activity precedes enablement and signature validation | Covered: [test][test_givenUnavailableCore_whenRelayed_reverts] |

Retired IDs BLCORE-AUTH-SIG-P03/P04/P05 described the superseded inactive/disabled-success requirement. After restoration, retry the same still-time-valid signature; the failed call consumes no nonce. A signature that expired during the pause must still reject after restoration.

## Shared assertions

No ERC-1271 support is implemented: include a contract account as an explicit unsupported signing path, not an invented success requirement. Exercise nonce uint256.max through a focused storage-boundary fixture and require a typed OperatorAuth_NonceExhausted(account) failure without grant update.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Signature and grant deadline read consistency

Otherwise well-formed signature, current nonce and distinct account/operator; any relayer. Independently vary authorization deadline and signature deadline; do not derive both from one selector. Keep a fixed representative signature-deadline interval when fuzzing grant deadline and vice versa.

| ID | Caller | Now | Authorization deadline | Signature deadline | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-AUTH-SIG-V01 | Fuzz all relayers | Independently fuzz1..MAX48 | Fuzz now..MAX48; seed now,MAX48 | now | Success | Store exact grant; increment nonce once; equality authorized | Covered: [test][test_givenValidSignature_whenRelayed], [test][test_whenSignatureBoundarySeeds] |
| BLCORE-AUTH-SIG-V02 | Fuzz all relayers | Independently fuzz1..MAX48 | Fuzz0..now-1; seed0,now-1 | Fuzz0..now-1; seed0,now-1 | `OperatorAuth_ExpiredSignature(signatureDeadline)` | Unchanged; signature expiry precedes grant expiry | Covered: [test][test_givenExpiredSignature_whenRelayed_reverts], [test][test_whenSignatureExpiryBoundarySeeds_reverts] |

## Existing tests informing this plan

- [setAuthorizationWithSig.t.sol](../utils/OperatorAuth/setAuthorizationWithSig.t.sol) — 16 legacy tests; retain relevant input/interaction families and compare expected behavior against the source above.
    - [test_setAuthorizationWithSig_givenValidSignature_setsAuthorizationAndConsumesNonce](../utils/OperatorAuth/setAuthorizationWithSig.t.sol#L20).
    - [test_setAuthorizationWithSig_givenCallerSignsForDifferentAccount_reverts](../utils/OperatorAuth/setAuthorizationWithSig.t.sol#L226).
    - [test_setAuthorizationWithSig_givenHighS_reverts](../utils/OperatorAuth/setAuthorizationWithSig.t.sol#L394).

These links are regression evidence and migration inputs. They are not `Covered` mappings for the rewritten API; inherited legacy fixture assumptions, mock authority, fuzz bounds and callback routes must be adapted before coverage is claimed.

Shared OperatorAuth validation order: signature deadline → authorization deadline → self-authorization → nonce → ECDSA recovery/signer. Seed competing faults to prove this order; failed recovery rolls back the provisional nonce increment.

## Nonce exhaustion

Implemented shared OperatorAuth behavior: reject incrementing MAX256 with OperatorAuth_NonceExhausted(account). Preserve grants/nonces and commit no events. MAX256-1 remains usable once, resulting in MAX256; all subsequent increments fail without wraparound. Direct set, cancellation and signed authorization use the same typed exhaustion behavior. Signed nonce mismatch is checked before exhaustion; both precede recovery/signer checks. Nonce mismatch is checked before the checked increment; no panic or wraparound replaces either typed error.

| ID | Caller | Nonce / request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-AUTH-SIG-P06 | Fuzz relayer | Current nonce=MAX256-1; otherwise valid request | Success | Nonce becomes MAX256 once; exact grant/event | Covered: [test][test_givenValidSignature_whenRelayed], [test][test_whenSignatureBoundarySeeds] |

## Restoration and signature expiry

Start from active/enabled Core with a valid, unused Core-domain signature. Failed admission must leave its nonce usable, without extending its signed deadline.

| ID | Caller | Sequence | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-AUTH-SIG-P07 | Fuzz relayer | Reject while inactive/disabled; restore both lifecycle requirements; retry before signature deadline | Success exactly once | One nonce consumed and exact grant; another replay rejects | Covered: [test][test_givenRestoredCore_whenSignatureRetried] |
| BLCORE-AUTH-SIG-P08 | Fuzz relayer | Pause while signature valid; fuzz resume time after signed deadline; seed deadline+1/MAX48 | OperatorAuth_ExpiredSignature(deadline) | No grant/nonce consumption; pause does not extend validity | Covered: [test][test_givenExpiryDuringPause_whenRetried_reverts] |

[test_givenActionReplacement_whenRelayed]: setAuthorizationWithSig.t.sol#L666
[test_givenAlteredAccount_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L357
[test_givenAlteredAuthorizationDeadline_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L435
[test_givenAlteredNonce_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L474
[test_givenAlteredOperator_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L396
[test_givenAlteredSignatureDeadline_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L513
[test_givenBadV_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L187
[test_givenCancellation_whenOldSignatureRelayed_reverts]: setAuthorizationWithSig.t.sol#L563
[test_givenDifferentSigner_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L213
[test_givenExhaustedNonceAndMismatch_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L161
[test_givenExhaustedNonce_whenMatchingSignatureRelayed_reverts]: setAuthorizationWithSig.t.sol#L144
[test_givenExpiredAuthorizationAndSelf_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L99
[test_givenExpiredSignature_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L66
[test_givenExpiryDuringPause_whenRetried_reverts]: setAuthorizationWithSig.t.sol#L642
[test_givenHighS_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L171
[test_givenRestoredCore_whenSignatureRetried]: setAuthorizationWithSig.t.sol#L610
[test_givenSelfGrant_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L119
[test_givenUnavailableCore_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L579
[test_givenValidSignature_whenRelayed]: setAuthorizationWithSig.t.sol#L19
[test_givenValidSignature_whenReplayed_reverts]: setAuthorizationWithSig.t.sol#L552
[test_givenWrongChain_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L228
[test_givenWrongCore_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L273
[test_givenWrongDomain_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L318
[test_givenWrongNonce_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L128
[test_givenZeroRecovery_whenRelayed_reverts]: setAuthorizationWithSig.t.sol#L200
[test_whenNonceMismatchMaximumSeed_reverts]: setAuthorizationWithSig.t.sol#L680
[test_whenSignatureBoundarySeeds]: setAuthorizationWithSig.t.sol#L53
[test_whenSignatureExpiryBoundarySeeds_reverts]: setAuthorizationWithSig.t.sol#L89
