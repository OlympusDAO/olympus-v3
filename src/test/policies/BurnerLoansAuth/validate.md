# BurnerLoansAuth.validate

Sources: `src/policies/burnerloans/BurnerLoansAuth.sol` and inherited `OperatorAuth`.

A nonzero account A has accepted a current reusable grant for distinct nonzero O; Core is active/enabled and Auth selected unless varied. Permissions are 320 canonical bytes. Collateral/floor use raw collateral units, maxDebt raw 9-decimal OHM, maturity absolute seconds. Views change no state. Core, not this view, compares the returned bound to actual post-settlement FLOAN.

| ID | Caller / domain | Execution and effects | Test |
| --- | --- | --- | --- |
| BLAUTH-VALIDATE-I01 | Selected operator; fuzz actions 1/2/4/8; actual asset differs | AssetMismatch(expected,actual); all grant/counter state unchanged | Covered: [test][test_whenDifferentAssetChecked_reverts] |
| BLAUTH-VALIDATE-I02 | Selected operator; borrow/withdraw; actual recipient differs | RecipientMismatch(expected,actual); unchanged | Covered: [test][test_whenDifferentRecipientChecked_reverts] |
| BLAUTH-VALIDATE-A01 | Fuzz unrelated nonzero operator excluding account and designated operator | InvalidContext; no unrelated authority | Covered: [test][test_whenUnrelatedOperatorChecked_reverts] |
| BLAUTH-VALIDATE-A02 | Fuzz permissionless viewer including zero | Exact same authorized bound; viewer does not become operator; counters unchanged | Covered: [test][test_whenPermissionlessViewerChecksAuthorizedOperator] |
| BLAUTH-VALIDATE-A03 | Intrinsic owner; fuzz unsupported/composite/zero actions | InvalidAction(action) before owner bypass | Covered: [test][test_whenOwnerChecksUnsupportedAction_reverts] |
| BLAUTH-VALIDATE-P01 | Operator; all four independently constrained records | Returns exact selected raw bound using independent assets and recipients | Covered: [test][test_whenIndependentActionRecordsUsed] |
| BLAUTH-VALIDATE-P02 | Operator; borrow and withdraw wildcard recipient; fuzz address | Recipient restriction omitted, other selected constraints remain | Covered: [test][test_whenRecipientWildcardUsed] |
| BLAUTH-VALIDATE-N01 | All four limits zero | Returns literal zero, including no positive withdrawal floor | Covered: [test][test_whenNumericLimitsAreZero] |
| BLAUTH-VALIDATE-N02 | uint128/uint48 maxima | Returns exact numeric type maximum without narrowing loss | Covered: [test][test_whenNumericLimitsAreMaximum] |
| BLAUTH-VALIDATE-N03 | Fuzz complete uint128/uint48 numeric and recipient address domains; seed zero/one/MAX-1/MAX independently of grant expiry | Exact accepted grant bytes and returned bounds for all actions; one pair epoch consumed, account epoch unchanged | Covered: [fuzz][test_whenNumericLimitsVary], [boundary seeds][test_whenConstraintBoundarySeeds] |
| BLAUTH-VALIDATE-P03 | Intrinsic owner; no grant | Maximum upper bounds / zero withdrawal floor, after required checks | Covered: [test][test_whenOwnerUsesIntrinsicAuthority] |
| BLAUTH-VALIDATE-L01 | Core active true, enabled false; owner | PolicyDependency_NotActive(Core); owner does not bypass service admission | Covered: [test][test_givenDisabledCore_whenOwnerChecks_reverts] |
| BLAUTH-VALIDATE-D01 | Owner/operator; Core reports foreign Kernel with active/enabled foreign registry | PolicyDependency_KernelMismatch(Core, trusted, foreign) during capture and validation; no caller bypass or state change | Covered: [capture][test_givenForeignKernelReportsActive_whenAuthorityCaptured_reverts], [validate][test_givenForeignKernelReportsActive_whenAuthorityValidated_reverts] |

[test_givenDisabledCore_whenOwnerChecks_reverts]: ./validate.t.sol#L300
[test_whenDifferentAssetChecked_reverts]: ./validate.t.sol#L68
[test_whenDifferentRecipientChecked_reverts]: ./validate.t.sol#L85
[test_whenIndependentActionRecordsUsed]: ./validate.t.sol#L131
[test_whenNumericLimitsAreMaximum]: ./validate.t.sol#L203
[test_whenNumericLimitsAreZero]: ./validate.t.sol#L183
[test_whenNumericLimitsVary]: ./validate.t.sol#L224
[test_whenConstraintBoundarySeeds]: ./validate.t.sol#L264
[test_whenOwnerChecksUnsupportedAction_reverts]: ./validate.t.sol#L122
[test_whenOwnerUsesIntrinsicAuthority]: ./validate.t.sol#L286
[test_whenPermissionlessViewerChecksAuthorizedOperator]: ./validate.t.sol#L108
[test_whenRecipientWildcardUsed]: ./validate.t.sol#L163
[test_whenUnrelatedOperatorChecked_reverts]: ./validate.t.sol#L100

[test_givenForeignKernelReportsActive_whenAuthorityCaptured_reverts]: ./validate.t.sol#L20

[test_givenForeignKernelReportsActive_whenAuthorityValidated_reverts]: ./validate.t.sol#L42
