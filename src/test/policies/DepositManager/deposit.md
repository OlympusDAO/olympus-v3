# DepositManager.deposit guard and solvency scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the retained own-activity regression and the implemented final deposit-solvency check.
This document does not replace existing deposit input, authorization or custody tests.
The approved acceptance rows are mapped to their implementation tests below.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-DEPOSIT-L01 | Fixed `ADMIN`, holding `admin` and lacking `deposit_operator` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Fixture asset/period/depositor; amount=`1e18`, unwrapped receipts | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst] |

## Solvency

Use the real DepositManager, ReceiptTokenManager and configured custody route.
O is the calling deposit operator; D is the depositor. X is an independent registered operator.
DM and its route are active/enabled. O is authorized; D has funds and allowance.
Keep the existing reentrancy, own activity, local enablement, role, period, minimum and cap checks.
Add no pre-deposit solvency check. After recording actual custody and liabilities, require:

```text
value of O's recorded custody shares + O's borrowed principal >= O's receipt liabilities
```

Notation:

- A is the requested deposit amount in raw underlying units.
- Q is the actual receipt credit in raw underlying units.
- S is the number of newly received shares in the configured share token's raw units.
- L is the operator's total receipt liabilities in raw underlying units.
- B is the operator's outstanding borrowed principal in raw underlying units.
- U is aggregate principal-cap utilization for the asset in raw underlying units.
- `MAX256` is `type(uint256).max`. The cap applies to Q, not A.

Fixed ratio examples use equal underlying and share decimals. They compare the value of existing
shares with liabilities. A share price above or below one does not determine that comparison.
Use subtraction or equivalent overflow-safe ordering for the mathematical solvency comparison.

Unchanged includes donor balances/allowances, idle/vault custody, vault assets and share supply,
operator shares, liabilities, borrowed balances, aggregate cap utilization, receipts/wrappers and
period metadata. Rejection commits no events. Success preserves every unrelated namespace's ledger;
vault-wide rounding can still alter valuations of unchanged shares.

`previewDeposit(asset,A)` remains conversion/cap estimation without operator context.
Post-settlement solvency is an execution-only check. A quote does not predict a mutating vault call.

Rows use fee-free proportional vaults unless specified. Repeat rejection rows for wrapped and
unwrapped receipts, including an empty existing wrapper and a wrapper with nonzero wrapped supply.
ReceiptTokenManager creates the wrapper during route creation, before the first deposit.
Guarantee ordinary enabled, locally re-enabled and Kernel-reactivated states across success cases.

| ID | Caller | Custody / namespace | Amount or transition | Execution and effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-DEPOSIT-P01 | O | First idle-custody deposit; no debt; fresh token starts with zero supply | A fuzz 1..MAX256, seed 1,MAX256; cap=MAX256 | Q=A; shares and liabilities rise by A; solvent equality succeeds; at A=MAX256, `maxClaimYield` returns 0 without liabilities+1 overflow | Same Q and shares in stable state | Covered: [test][test_whenIdleAmountAcrossUint256Domain], [test][test_whenIdleAmountIsOne], [test][test_whenIdleAmountIsUint256Maximum]. |
| DM-DEPOSIT-P02 | O | Existing 100 shares represent 80 underlying units; liabilities L=80 and B=0, so claims are fully backed | A=8 -> S=10,Q=8 | Final assets=L=88; accept although each share represents 0.8 underlying units | Stable quote Q=8,S=10 | Covered: [test][test_givenSolventBelowOneSharePrice_whenDepositing]. |
| DM-DEPOSIT-I01 | O | Existing 100 shares represent 120 underlying units; liabilities L=130 and B=0, so claims lack 10 underlying units | A=12 -> S=10,Q=12 | `DepositManager_Insolvent(asset,142,132,0)`; reject although each share represents 1.2 underlying units; Unchanged | Quote Q=12,S=10 remains an estimate | Covered: [test][test_givenInsolventAboveOneSharePrice_whenDepositing_reverts] |
| DM-DEPOSIT-I02 | O | Vault loss; 100 shares now worth 80, L=100 | A=8 -> S=10,Q=8 | `DepositManager_Insolvent(asset,108,88,0)`; Unchanged | Quote Q=8,S=10; cannot prove final solvency | Covered: [test][test_givenLossAcrossPeriods_whenDepositing_revertsAndRollsBack], [test][test_givenInsolventOperator_whenDepositing_revertsAndPreservesCustody]. |
| DM-DEPOSIT-N01 | O | O owns all L vault shares; L liabilities; backing=L-d; B=0; no fees or callbacks | Fuzz L=3..floor(MAX256/2), d=2..L-1; seed d=2,L-1; A over representable conversion/cap domain with Q>0 | Exact final `DepositManager_Insolvent(asset,Lpost,assetsPost,0)`; Unchanged; no receipt can survive the rejection | Conversion/cap estimate only | Covered: [test][test_givenProportionalDeficit_whenDepositingAcrossRepresentableDomain], [test][test_givenTwoUnitDeficit_whenDepositing_reverts], [test][test_givenMaximumProportionalDeficit_whenDepositing_reverts] |
| DM-DEPOSIT-N02 | O | Final assets+B equals final L | Deterministic zero deficit and nonzero borrowed principal cases | Equality succeeds; do not require excess backing | Stable quote matches actual conversion | Covered: [test][test_whenIdleAmountAcrossUint256Domain], [test][test_whenIdleAmountIsOne], [test][test_whenIdleAmountIsUint256Maximum], [test][test_givenBorrowedPrincipal_whenFinalSolvencyIsEquality], [test][test_givenReEnabled_whenSolventDeposit], [test][test_givenPolicyReactivated_whenSolventDeposit] |
| DM-DEPOSIT-N03 | O | Final assets+B is exactly L-1 | Deterministic one-raw-unit deficit | Exact insolvency error with final values; Unchanged | Estimate only | Covered: [test][test_givenOneUnitRemainingDeficit_whenDepositing_reverts] |
| DM-DEPOSIT-P03 | O | Assets=60,B=40,L=100 | 1:1-valued custody addition A=10 | Final assets=70,B=40,L=110; accept; count borrowed principal | Conversion quote unchanged by B | Covered: [test][test_givenBorrowedPrincipal_whenFinalSolvencyIsEquality] |
| DM-DEPOSIT-P04 | X | O remains insolvent; X has no liabilities or remains solvent | Valid A in X's registered route for same asset | Credit X only; O's deficit does not globally block the asset | Stable quote for conversion | Covered: [test][test_givenOtherOperatorIsInsolvent_whenIndependentOperatorDeposits] |
| DM-DEPOSIT-I03 | O | Existing deficit spans O's two periods | Deposit through the other enabled period | Check combined operator namespace; exact insolvency error; Unchanged across both receipt IDs | Conversion quote has no period context | Covered: [test][test_givenLossAcrossPeriods_whenDepositing_revertsAndRollsBack]. |
| DM-DEPOSIT-T01 | O | Starts solvent with existing shares | Vault deposit realizes a loss in existing shares; final namespace insolvent | Final insolvency error; rollback the loss, shares, transfers, receipts, wrapped supply and U | Quote before callback is not a guarantee | Covered: [test][test_givenSolventOperator_whenVaultRealizesLossDuringDeposit_reverts] |
| DM-DEPOSIT-P05 | O | Starts insolvent | Vault deposit realizes enough genuine yield to fully restore final solvency | Deposit succeeds; proves no new precheck; independently assert final assets,B,L and Q | Snapshot quote need not predict realized yield | Covered: [test][test_givenInsolventOperator_whenVaultRealizesYieldDuringDeposit]. |
| DM-DEPOSIT-P06 | O | Remains insolvent after a partial donation | Subsequent ordinary deposit | Exact final insolvency error; donation from earlier transaction persists; attempted deposit rolls back | Estimate only | Covered: [test][test_givenPartialDonation_whenDepositing_revertsAndRetainsDonation] |
| DM-DEPOSIT-P07 | O | Donation fully repairs existing deficit | Subsequent deposit and existing-holder withdrawal | Deposit and withdrawal succeed; donation created no new claim or cap usage | Stable conversion quote matches deposit | Covered: [test][test_givenFullDonation_whenDepositingAndWithdrawing] |
| DM-DEPOSIT-P08 | O | Self-share, separate ERC-7575 share token, and synchronous-deposit/asynchronous-redemption routes; guarantee each | Solvent baseline, then proportional loss and another deposit | Baseline succeeds; loss case rejects final insolvency; use configured-token balance and correct live valuation path | Preserve existing conversion preview mode | Covered: [test][test_givenLossAcrossPeriods_whenDepositing_revertsAndRollsBack], [test][test_givenInsolventOperator_whenDepositing_revertsAndPreservesCustody], [test][test_givenSynchronousExternalShareVaultLoss_whenDepositing_reverts], [test][test_givenAsyncRedeemSelfShareVaultLoss_whenDepositing_reverts] |
| DM-DEPOSIT-P09 | O | O owns all 100 vault shares; L=100; backing=99 after loss; B=0 | A=2 -> S=2; Q=floor(2*101/102)=1 | Final assets=L=101; accept the rounding-funded full repair; donor spends 2 and receives 1 receipt | Pre-call conversion quote returns Q=1,S=2 | Covered: [test][test_givenOneUnitLoss_whenRoundingFullyRepairsDeficit] |

N01 spans the fixture's representable interval, not a promise that every arbitrary combination of
256-bit conversions can execute. Require L+S, L+Q and backing+A to be representable and all earlier
guards to pass. In this proportional vault, each share represents less than one underlying unit.
A-Q is at most one. A deficit of at least two
therefore remains positive. Exclude Q=0 from this exact-insolvency family because receipt minting
rejects zero first. N02/N03 provide exact economic boundary seeds independently, and P09 covers the
distinct one-unit rounding repair.

## Shared-callers, precedence and callbacks

| ID | Caller / route | Fixture / competing fault | Execution and effects | Test |
| --- | --- | --- | --- | --- |
| DM-DEPOSIT-T02 | ConvertibleDepositFacility.deposit | Real facility namespace has the I02 loss; valid funded recipient | Exact final DM insolvency error; no new receipt or facility state; complete payer/custody rollback | Covered: [test][test_givenRealDepositManagerNamespaceHasLoss_whenDepositing_revertsAndRollsBack]. |
| DM-DEPOSIT-T03 | ConvertibleDepositFacility.createPosition | Real facility namespace has the I02 loss; permitted auctioneer and valid position terms | Exact final DM insolvency error; no new DEPOS position or index; complete receipt/payer/custody rollback | Covered: [test][test_givenRealDepositManagerNamespaceHasLoss_whenCreatingPosition_revertsAndRollsBack]. |
| DM-DEPOSIT-I04 | Unauthorized fuzzed caller, excluding every granted deposit operator | Existing deficit plus otherwise valid deposit | Existing ROLES error before custody/solvency; Unchanged | Covered: [test][test_givenInsolventOperator_whenCallerIsUnauthorized_revertsRoleFirst] |
| DM-DEPOSIT-I05 | O | Existing deficit plus disabled asset-period | Existing `DepositManager_AssetPeriodDisabled(asset,period,O)` before custody/solvency; Unchanged | Covered: [test][test_givenInsolventOperator_givenDisabledPeriod_whenDepositing_revertsPeriodFirst] |
| DM-DEPOSIT-I06 | O | Existing deficit plus insufficient payer allowance | Exact token allowance error before final solvency; Unchanged | Covered: [test][test_givenInsolventOperator_whenAllowanceIsInsufficient_revertsAllowanceFirst] |
| DM-DEPOSIT-C01 | O | Receipt mint or vault callback attempts otherwise eligible donate; nested failure caught | Nested shared-guard rejection; outer solvent deposit credits once | Covered: [test][test_givenVaultCallback_whenEligibleDonationReenters_rejectsNestedAndCreditsOnce]. |

Existing enabled/disabled and role tests remain regression controls. Existing focused custody tests
continue to prove exact receipt, cap enforcement and asynchronous-mode behavior.

[test_givenInsolventOperator_whenDepositing_revertsAndPreservesCustody]: deposit.t.sol#L1014
[test_givenSynchronousExternalShareVaultLoss_whenDepositing_reverts]: deposit.t.sol#L1126
[test_givenAsyncRedeemSelfShareVaultLoss_whenDepositing_reverts]: deposit.t.sol#L1169
[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst]: deposit.t.sol#L1495
[test_whenIdleAmountAcrossUint256Domain]: depositSolvency.t.sol#L201
[test_whenIdleAmountIsOne]: depositSolvency.t.sol#L206
[test_whenIdleAmountIsUint256Maximum]: depositSolvency.t.sol#L211
[test_givenSolventBelowOneSharePrice_whenDepositing]: depositSolvency.t.sol#L216
[test_givenInsolventAboveOneSharePrice_whenDepositing_reverts]: depositSolvency.t.sol#L233
[test_givenLossAcrossPeriods_whenDepositing_revertsAndRollsBack]: depositSolvency.t.sol#L256
[test_givenProportionalDeficit_whenDepositingAcrossRepresentableDomain]: depositSolvency.t.sol#L300
[test_givenTwoUnitDeficit_whenDepositing_reverts]: depositSolvency.t.sol#L327
[test_givenMaximumProportionalDeficit_whenDepositing_reverts]: depositSolvency.t.sol#L335
[test_givenOneUnitRemainingDeficit_whenDepositing_reverts]: depositSolvency.t.sol#L343
[test_givenOneUnitLoss_whenRoundingFullyRepairsDeficit]: depositSolvency.t.sol#L358
[test_givenBorrowedPrincipal_whenFinalSolvencyIsEquality]: depositSolvency.t.sol#L383
[test_givenOtherOperatorIsInsolvent_whenIndependentOperatorDeposits]: depositSolvency.t.sol#L404
[test_givenSolventOperator_whenVaultRealizesLossDuringDeposit_reverts]: depositSolvency.t.sol#L451
[test_givenInsolventOperator_whenVaultRealizesYieldDuringDeposit]: depositSolvency.t.sol#L471
[test_givenPartialDonation_whenDepositing_revertsAndRetainsDonation]: depositSolvency.t.sol#L486
[test_givenFullDonation_whenDepositingAndWithdrawing]: depositSolvency.t.sol#L508
[test_givenInsolventOperator_whenCallerIsUnauthorized_revertsRoleFirst]: depositSolvency.t.sol#L552
[test_givenInsolventOperator_givenDisabledPeriod_whenDepositing_revertsPeriodFirst]: depositSolvency.t.sol#L578
[test_givenInsolventOperator_whenAllowanceIsInsufficient_revertsAllowanceFirst]: depositSolvency.t.sol#L595
[test_givenVaultCallback_whenEligibleDonationReenters_rejectsNestedAndCreditsOnce]: depositSolvency.t.sol#L618
[test_givenReEnabled_whenSolventDeposit]: depositSolvency.t.sol#L644
[test_givenPolicyReactivated_whenSolventDeposit]: depositSolvency.t.sol#L655
[test_givenRealDepositManagerNamespaceHasLoss_whenDepositing_revertsAndRollsBack]: ../ConvertibleDepositFacility/deposit.t.sol#L17
[test_givenRealDepositManagerNamespaceHasLoss_whenCreatingPosition_revertsAndRollsBack]: ../ConvertibleDepositFacility/createPosition.t.sol#L13
