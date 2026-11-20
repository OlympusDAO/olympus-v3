# BurnerLoansAuth.approveGrant

Sources: `src/policies/burnerloans/BurnerLoansAuth.sol`, inherited `OperatorAuth.approveGrant`.

Account A grants operator O authority; A and O are distinct nonzero addresses. The default grant is
reusable, deadline MAX48, all four actions selected and permissions exactly 320 canonical ABI bytes.
Assets use raw collateral units; debt bounds use raw 9-decimal OHM; maturity is absolute seconds.
Unchanged means no grant, pair/account epoch or committed event changes.

## Canonical permissions

| ID | Caller | Permission input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLAUTH-APPROVE-I01 | A | Fuzz length 0..MAX16 except 320 | InvalidPermissions | Unchanged | [length][test_whenPermissionLengthIsNotCanonical_reverts], [boundary seeds][test_whenPermissionLengthBoundarySeeds_reverts] |
| BLAUTH-APPROVE-I02 | A | Selected action asset zero; fuzz action and seed all four actions | InvalidAsset(0) | Unchanged | [zero][test_whenSelectedAssetIsZero_reverts], [action seeds][test_whenSelectedAssetZeroActionSeeds_reverts] |
| BLAUTH-APPROVE-I03 | A | Selected borrow asset not configured | InvalidAsset(asset) | Unchanged | [unconfigured][test_whenSelectedAssetIsUnconfigured_reverts] |
| BLAUTH-APPROVE-I04 | A | Nonzero bits above uint128 maximum in collateral word | InvalidPermissions | Unchanged | [padding][test_whenNarrowIntegerHasDirtyPadding_reverts] |
| BLAUTH-APPROVE-P01 | A | Unselected records contain zero assets/limits | Success | Exact permission bytes retained; pair epoch advances once | [unselected][test_whenUnselectedRecordsContainZeroAssets] |

## Accepted constraint values

Approval records bounds; Core compares them with the later settlement result. An accepted grant need
not permit an operation for the current position or timestamp. These fields are independent, so
approval does not compare the deposit ceiling with the withdrawal floor.

The shared approval/read tests fuzz each numeric field and recipient independently. They assert
exact grant bytes, one consumed pair epoch, an unchanged account epoch and the bound for each action.
Deterministic seeds include zero, one, type maximum minus one and type maximum for every field.

| ID | Field | Accepted domain and units | Meaning | Test |
| --- | --- | --- | --- | --- |
| BLAUTH-APPROVE-N01 | maxCollateral | 0..MAX128 raw collateral units | Literal deposit-result ceiling | Covered: [fuzz][test_whenNumericLimitsVary], [seeds][test_whenConstraintBoundarySeeds] |
| BLAUTH-APPROVE-N02 | maxDebt | 0..MAX128 raw 9-decimal OHM | Literal principal-result ceiling | Covered: [fuzz][test_whenNumericLimitsVary], [seeds][test_whenConstraintBoundarySeeds] |
| BLAUTH-APPROVE-N03 | minCollateral | 0..MAX128 raw collateral units | Withdrawal-result floor; zero imposes no positive floor | Covered: [fuzz][test_whenNumericLimitsVary], [seeds][test_whenConstraintBoundarySeeds] |
| BLAUTH-APPROVE-N04 | maxMaturity | 0..MAX48 absolute seconds | Literal extension-result ceiling; separate from grant expiry | Covered: [fuzz][test_whenNumericLimitsVary], [seeds][test_whenConstraintBoundarySeeds] |
| BLAUTH-APPROVE-P04 | borrowRecipient, withdrawRecipient | Full address domain; zero/one/MAX160-1/MAX160 seeds | Zero is a wildcard; nonzero fixes the recipient for that action | Covered: [fuzz][test_whenNumericLimitsVary], [seeds][test_whenConstraintBoundarySeeds] |

## Integration with real Core

These tests call `BurnerLoansAuth.approveGrant`, using a real active/enabled Core with registered
collateral and an existing loan. Core exposes no grant-management API. Generic engine cases remain
in the OperatorAuth suite; these cases retain the real lending integration proof.

| ID | Caller / input | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLAUTH-APPROVE-P05 | Borrower; fuzz deadline from current time through MAX48 | Success; authority exists at the deadline and expires one second later | Pair epoch becomes one | Covered: [test][test_whenReusableGrantApproved] |
| BLAUTH-APPROVE-P06 | Borrower; two reusable approvals | Both succeed | Pair epoch becomes two | Covered: [test][test_whenRepeatedApprovals] |
| BLAUTH-APPROVE-I07 | Borrower; operator equals borrower | OperatorAuth_SelfGrant | Unchanged | Covered: [test][test_whenSelfGrant_reverts] |
| BLAUTH-APPROVE-I08 | Borrower; deadline 1, current time 2 | OperatorAuth_ExpiredGrant(1) | Pair epoch remains zero | Covered: [test][test_whenExpiredGrant_reverts] |
| BLAUTH-APPROVE-I09 | Borrower; pair epoch MAX256 | OperatorAuth_EpochExhausted | Unchanged | Covered: [test][test_whenPairEpochExhausted_reverts] |
| BLAUTH-APPROVE-N05 | Borrower; pair epoch MAX256-1 | Success; accepted authority remains usable | Pair epoch becomes MAX256 | Covered: [test][test_whenLastPairEpochAccepted] |
| BLAUTH-APPROVE-A01 | Fuzz caller excluding borrower, including the operator | OperatorAuth_InvalidIdentity | Pair epoch remains zero | Covered: [test][test_whenUnauthorizedAccountApproves_reverts] |

Economic result bounds are enforced by Core's settlement methods. Their scenario plans cover exact
inclusive bounds and rejected results outside those bounds: [deposit](../BurnerLoansCore/settleDeposit.md),
[borrow](../BurnerLoansCore/settleBorrow.md), [withdraw](../BurnerLoansCore/settleWithdraw.md) and
[extend](../BurnerLoansCore/settleExtend.md).

## Core admission

Core active means membership in the independently trusted Kernel. The foreign Kernel reports Core
active throughout the mismatch cases; that report cannot establish trusted membership.

| ID | Caller | Reported Kernel | Core active | Core enabled | Auth selected | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLAUTH-APPROVE-L01 | A | Trusted | true | false | true | PolicyDependency_NotActive(Core) | Unchanged | [disabled][test_givenDisabledCore_whenGrantCreated_reverts] |
| BLAUTH-APPROVE-L02 | A | Trusted | false | true | true | PolicyDependency_NotActive(Core) | Unchanged | [inactive][test_givenInactiveCore_whenGrantCreated_reverts] |
| BLAUTH-APPROVE-D01 | A | Trusted | true | true | false | NotSelected | Unchanged | [retired][test_givenRetiredAuth_whenGrantCreated_reverts] |
| BLAUTH-APPROVE-P02 | A | Trusted | true | restored true | true | Success | One new accepted pair epoch | [restored][test_givenCoreReenabled_whenGrantCreated] |
| BLAUTH-APPROVE-D02 | A | Foreign | Fuzz true/false | Fuzz true/false | true | PolicyDependency_KernelMismatch(Core, trusted, foreign) before readiness | Unchanged | Covered: [mismatch][test_givenForeignKernelReportsActive_whenGrantCreated_reverts], [inactive trusted registry][test_givenTrustedKernelInactive_whenForeignKernelReportsActive_reverts] |
| BLAUTH-APPROVE-D03 | A | Trusted or unreadable | true | True or unreadable | true | PolicyDependency_InvalidDependency(Core) for reverting kernel/enabled getter | Unchanged | Covered: [metadata][test_whenCoreReadinessMetadataReverts_reverts] |

The inherited generic scenarios prove caller identity, deadlines, epoch exhaustion, modes and grant
mask validation. Concrete signed acceptance uses the same canonical permission/admission hooks.

Additional seeds cover each narrow ABI word and permission lengths 0,1,319,321,MAX16. Gas samples use exactly 320 bytes and exclude intrinsic transaction/calldata fees.

| ID | Caller / input | Execution | Test |
| --- | --- | --- | --- |
| BLAUTH-APPROVE-I05 | Each narrow field dirty, including unselected records | InvalidPermissions | [test][test_whenAnyRecordHasDirtyPadding_reverts], [test][test_whenEveryPaddingBoundarySeed_reverts] |
| BLAUTH-APPROVE-I06 | Every selected action asset unconfigured | InvalidAsset(asset) | [test][test_whenEachSelectedAssetIsUnconfigured_reverts] |
| BLAUTH-APPROVE-P03 | First temporary/reusable direct approval | Gas and pair consumption recorded | [test][test_whenFirstTemporaryGrantAccepted_reportsGas], [test][test_whenFirstReusableGrantAccepted_reportsGas] |

[test_givenCoreReenabled_whenGrantCreated]: ./approveGrant.t.sol#L230
[test_givenDisabledCore_whenGrantCreated_reverts]: ./approveGrant.t.sol#L176
[test_givenInactiveCore_whenGrantCreated_reverts]: ./approveGrant.t.sol#L189
[test_givenRetiredAuth_whenGrantCreated_reverts]: ./approveGrant.t.sol#L202
[test_whenAnyRecordHasDirtyPadding_reverts]: ./approveGrant.t.sol#L142
[test_whenEachSelectedAssetIsUnconfigured_reverts]: ./approveGrant.t.sol#L164
[test_whenEveryPaddingBoundarySeed_reverts]: ./approveGrant.t.sol#L157
[test_whenFirstReusableGrantAccepted_reportsGas]: ./gas.t.sol#L27
[test_whenFirstTemporaryGrantAccepted_reportsGas]: ./gas.t.sol#L13
[test_whenNarrowIntegerHasDirtyPadding_reverts]: ./approveGrant.t.sol#L127
[test_whenPermissionLengthBoundarySeeds_reverts]: ./approveGrant.t.sol#L81
[test_whenPermissionLengthIsNotCanonical_reverts]: ./approveGrant.t.sol#L72
[test_whenSelectedAssetIsUnconfigured_reverts]: ./approveGrant.t.sol#L117
[test_whenSelectedAssetIsZero_reverts]: ./approveGrant.t.sol#L90
[test_whenSelectedAssetZeroActionSeeds_reverts]: ./approveGrant.t.sol#L109
[test_whenNumericLimitsVary]: ./validate.t.sol#L224
[test_whenConstraintBoundarySeeds]: ./validate.t.sol#L264
[test_whenReusableGrantApproved]: ./approveGrantCoreIntegration.t.sol#L14
[test_whenRepeatedApprovals]: ./approveGrantCoreIntegration.t.sol#L30
[test_whenSelfGrant_reverts]: ./approveGrantCoreIntegration.t.sol#L37
[test_whenExpiredGrant_reverts]: ./approveGrantCoreIntegration.t.sol#L45
[test_whenPairEpochExhausted_reverts]: ./approveGrantCoreIntegration.t.sol#L57
[test_whenLastPairEpochAccepted]: ./approveGrantCoreIntegration.t.sol#L66
[test_whenUnauthorizedAccountApproves_reverts]: ./approveGrantCoreIntegration.t.sol#L78
[test_whenUnselectedRecordsContainZeroAssets]: ./approveGrant.t.sol#L210

[test_givenForeignKernelReportsActive_whenGrantCreated_reverts]: ./approveGrant.t.sol#L45

[test_givenTrustedKernelInactive_whenForeignKernelReportsActive_reverts]: ./approveGrant.t.sol#L18

[test_whenCoreReadinessMetadataReverts_reverts]: ./approveGrant.t.sol#L23
