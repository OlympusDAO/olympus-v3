# OperatorAuth `acceptGrant` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant. By default A and designated operator O are distinct nonzero addresses;
the self-grant case explicitly sets O=A. Unauthorized signed-acceptance callers exclude only O,
so A is also an unauthorized submitter when A≠O. Actions are uint8 single bits; supported harness
mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time
is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data,
capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine.
Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OASIGN-A01 | when Unrelated Submitter reverts | OperatorAuth_InvalidIdentity | Unchanged after revert | Covered: [test][test_whenUnrelatedSubmitter_reverts] |
| OASIGN-P01 | Designated O submits A's valid signature; then repeats the same request | First call succeeds and emits the exact GrantAccepted event; replay rejects InvalidEpoch | First call installs one grant and consumes one pair epoch; replay preserves it | Covered: [test][test_whenDesignatedOperatorAccepts] |
| OASIGN-A02 | Owner A submits a signed replacement naming a different operator O; an A→O grant is already live | OperatorAuth_InvalidIdentity: only O may submit acceptGrant; A can approve directly instead | Both epochs, original grant bytes and stamp remain unchanged | Covered: [test][test_givenReusableGrant_whenAccountSubmitsSignature_reverts] |
| OASIGN-I24 | A submits a validly signed grant with account=operator=A; an existing A→O reusable grant is live | OperatorAuth_SelfGrant before signature installation | Both original epochs, grant bytes and stamp stay unchanged; no self-pair epoch or record created | Covered: [test][test_givenReusableGrant_whenSignedSelfGrantAccepted_reverts] |
| OASIGN-I01 | when Malformed Signature reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenMalformedSignature_reverts] |
| OASIGN-I02 | when Permissions Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenPermissionsTampered_reverts] |
| OASIGN-I03 | when Operator Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenOperatorTampered_reverts] |
| OASIGN-I04 | when Context Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenContextTampered_reverts] |
| OASIGN-I05 | when Deadline Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenDeadlineTampered_reverts] |
| OASIGN-I06 | when Mode Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenModeTampered_reverts] |
| OASIGN-I07 | when Actions Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenActionsTampered_reverts] |
| OASIGN-I08 | when Account Epoch Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenAccountEpochTampered_reverts] |
| OASIGN-I09 | when Pair Epoch Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenPairEpochTampered_reverts] |
| OASIGN-I10 | when Unknown Signature Data reverts | OperatorAuth_UnsupportedSignatureData | Unchanged after revert | Covered: [test][test_whenUnknownSignatureData_reverts] |
| OASIGN-P06 | Operator; genuine signature over an enabled consumer's opaque 32-byte zero payload | Success; data has no timestamp interpretation | Exact grant retained, one pair epoch consumed and authority live | Covered: [test][test_whenOpaqueSignatureDataAccepted] |
| OASIGN-I11 | when Signature Data Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenSignatureDataTampered_reverts] |
| OASIGN-P04 | Wallet accepts while pair epoch is 0; its signature policy later rejects | Success at acceptance; existing grant remains usable | Pair advances once; use retains the original stamp without another wallet check | Covered: [test][test_whenERC1271Accepted_policyChangesKeepGrant] |
| OASIGN-C01 | when ERC1271Mutates reverts Before Installation | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenERC1271Mutates_revertsBeforeInstallation] |
| OASIGN-I13 | when Signature Replayed To Other Auth reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenSignatureReplayedToOtherAuth_reverts] |
| OASIGN-I14 | when Chain Changes rejects Old Signature | OperatorAuth_InvalidSignature | Asserted epochs, authority or returned data | Covered: [test][test_whenChainChanges_rejectsOldSignature] |
| OASIGN-I15 | when Account Tampered reverts | OperatorAuth_InvalidSignature | Unchanged after revert | Covered: [test][test_whenAccountTampered_reverts] |
| OASIGN-I16 | when Signature Data Oversized reverts | InvalidSignatureData | Unchanged after revert | Covered: [test][test_whenSignatureDataOversized_reverts] |
| OADEFAULT-P02 | when Default Consumer Accepts Signature no Core Required | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenDefaultConsumerAcceptsSignature_noCoreRequired] |

## Signature rejection preserves existing authority

A current reusable grant exists before each attempted replacement. The replacement names the current
pair epoch. Every rejection must preserve both epochs, all original grant bytes and its captured
stamp. These tests exercise the authorization engine's installation boundary through its actual
signature library; they do not introduce another verifier. ERC-1271 permits trailing returndata
when the first complete ABI word is the canonical magic value.

| ID | Signature / wallet response | Expected result | Test |
| --- | --- | --- | --- |
| OASIGN-I17 | EOA signature length fuzzed across 0..MAX16 except 65; seeds 0, 1, 64, 66, MAX16 | InvalidSignature; existing authority unchanged | [range][test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts], [seeds][test_givenReusableGrant_whenSignatureLengthBoundarySeeds_reverts] |
| OASIGN-I18 | Correct EOA signature except recovery ID fuzzed across uint8 excluding 27/28 | InvalidSignature; existing authority unchanged | [test][test_givenReusableGrant_whenRecoveryIdIsInvalid_reverts] |
| OASIGN-I19 | Equivalent high-s EOA signature with flipped recovery ID | InvalidSignature; malleable signature cannot replace authority | [test][test_givenReusableGrant_whenSignatureIsMalleable_reverts] |
| OASIGN-I20 | r=s=0 and v=27 | InvalidSignature; zero recovery cannot replace authority | [test][test_givenReusableGrant_whenSignatureRecoversZero_reverts] |
| OASIGN-I21 | ERC-1271 magic prefix truncated to fuzzed length 0..31 | InvalidSignature; incomplete ABI word cannot replace authority | [test][test_givenReusableGrant_whenERC1271ReturnIsShort_reverts] |
| OASIGN-I22 | Fuzz any noncanonical first bytes32 word; seeds zero, right-aligned magic, dirty padding and MAX256 | InvalidSignature; existing authority unchanged | [range][test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts], [seeds][test_givenReusableGrant_whenERC1271WordBoundarySeeds_reverts] |
| OASIGN-I23 | ERC-1271 wallet reverts | InvalidSignature; wallet failure cannot erase or replace existing authority | [test][test_givenReusableGrant_whenERC1271Reverts_reverts] |
| OASIGN-P05 | Canonical magic word followed by 0..MAX8 trailing bytes | Success; wallet receives the complete expected digest/signature; one new pair epoch and exact replacement grant | [test][test_givenReusableGrant_whenERC1271HasCanonicalWordAndTrailingData] |

[test_whenOpaqueSignatureDataAccepted]: ./acceptGrant.t.sol#L396
[test_givenReusableGrant_whenSignedSelfGrantAccepted_reverts]: ./acceptGrant.t.sol#L266
[test_whenAccountEpochTampered_reverts]: ./acceptGrant.t.sol#L362
[test_givenReusableGrant_whenAccountSubmitsSignature_reverts]: ./acceptGrant.t.sol#L243
[test_whenAccountTampered_reverts]: ./acceptGrant.t.sol#L477
[test_whenActionsTampered_reverts]: ./acceptGrant.t.sol#L352
[test_whenChainChanges_rejectsOldSignature]: ./acceptGrant.t.sol#L467
[test_whenContextTampered_reverts]: ./acceptGrant.t.sol#L321
[test_whenDeadlineTampered_reverts]: ./acceptGrant.t.sol#L332
[test_whenDefaultConsumerAcceptsSignature_noCoreRequired]: ./acceptGrant.t.sol#L498
[test_whenDesignatedOperatorAccepts]: ./acceptGrant.t.sol#L230
[test_whenERC1271Accepted_policyChangesKeepGrant]: ./acceptGrant.t.sol#L427
[test_whenERC1271Mutates_revertsBeforeInstallation]: ./acceptGrant.t.sol#L445
[test_whenMalformedSignature_reverts]: ./acceptGrant.t.sol#L293
[test_whenModeTampered_reverts]: ./acceptGrant.t.sol#L342
[test_whenOperatorTampered_reverts]: ./acceptGrant.t.sol#L311
[test_whenPairEpochTampered_reverts]: ./acceptGrant.t.sol#L374
[test_whenPermissionsTampered_reverts]: ./acceptGrant.t.sol#L301
[test_whenSignatureDataOversized_reverts]: ./acceptGrant.t.sol#L487
[test_whenSignatureDataTampered_reverts]: ./acceptGrant.t.sol#L417
[test_whenSignatureReplayedToOtherAuth_reverts]: ./acceptGrant.t.sol#L457
[test_whenUnknownSignatureData_reverts]: ./acceptGrant.t.sol#L386
[test_whenUnrelatedSubmitter_reverts]: ./acceptGrant.t.sol#L215

[test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts]: ./acceptGrant.t.sol#L16

[test_givenReusableGrant_whenSignatureLengthBoundarySeeds_reverts]: ./acceptGrant.t.sol#L23

[test_givenReusableGrant_whenRecoveryIdIsInvalid_reverts]: ./acceptGrant.t.sol#L32

[test_givenReusableGrant_whenSignatureIsMalleable_reverts]: ./acceptGrant.t.sol#L41

[test_givenReusableGrant_whenSignatureRecoversZero_reverts]: ./acceptGrant.t.sol#L57

[test_givenReusableGrant_whenERC1271ReturnIsShort_reverts]: ./acceptGrant.t.sol#L63

[test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts]: ./acceptGrant.t.sol#L78

[test_givenReusableGrant_whenERC1271WordBoundarySeeds_reverts]: ./acceptGrant.t.sol#L93

[test_givenReusableGrant_whenERC1271Reverts_reverts]: ./acceptGrant.t.sol#L103

[test_givenReusableGrant_whenERC1271HasCanonicalWordAndTrailingData]: ./acceptGrant.t.sol#L115
