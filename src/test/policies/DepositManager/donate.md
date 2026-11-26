# DepositManager.donate coverage plan

The approved scenarios are mapped to their unit and stateful invariant tests below.

Sources: [V1.1 interface](../../../policies/interfaces/deposits/IDepositManagerV1_1.sol),
[custody deposit](../../../bases/BaseAssetManager.sol#L80),
[namespace valuation](../../../bases/BaseAssetManager.sol#L218),
[operator registration](../../../policies/deposits/DepositManager.sol), and
[solvency](../../../policies/deposits/DepositManager.sol).

## API and effects

`IDepositManagerV1_1` defines the donation function and event:

```solidity
function donate(
    IERC20 asset_,
    address operator_,
    uint256 amount_
) external returns (uint256 actualAmount, uint256 shares);

event AssetDonated(
    address indexed asset,
    address indexed donor,
    address indexed operator,
    uint256 amount,
    uint256 actualAmount,
    uint256 shares
);
```

`amount_` and `actualAmount` use underlying-asset units. `shares` uses the configured share token's
raw units. Idle custody uses underlying units for both return values.

The caller funds the donation. The target operator receives the recorded custody shares.
The function does not accept a payer, vault, share-token address, period or receipt-wrapping flag.
It does not mint receipts or change liabilities, borrowing, cap utilization or FLOAN positions.

Use the existing exact underlying transfer, configured vault and exact received-share checks.
Keep ordinary deposit and repayment namespace attribution unchanged when sharing this custody path.
Emit `AssetDeposited(asset, donor, operator, actualAmount, shares)` and then `AssetDonated` once each.
The existing custody event already covers incoming custody without necessarily creating receipts.

Full solvency is not required before or after donation. Partial repairs and surplus donations succeed.
Surplus belongs to the target operator under its existing yield-claim rules. Donors receive no claim
or refund right. Donation cannot bypass a vault that refuses synchronous deposits or valuation.

Do not cap nominal input at the currently measured deficit. Vault rounding can consume a requested
overpayment or require more input than that deficit to mint one share. Actual received custody is
authoritative. Partial and exact repairs create no claimable yield; a genuine excess can create
claimable yield, subject to the existing one-unit reserve and withdrawal rounding.
This follows `borrowingRepay`: incoming overpayment is accepted while principal reduction is capped.
Donation has no principal reduction. It never reduces borrowed debt or creates a new receipt claim.

`IDepositManager` remains byte-for-byte unchanged. VERSION remains `(1, 1)`.
The V1 interface ID remains unchanged. The V1.1 ID reflects its added function.
All recompiled V1.1 consumers and mocks must recognize the updated interface ID.
There is no separate donation preview. `previewDeposit` remains a conversion and principal-cap
estimate; its cap restriction does not determine whether a donation can execute.

## Domains and fixed defaults

- Scope: `DM-DONATE`. `MAX` is `type(uint256).max`.
- D is the donor; O is a nonzero operator with an explicitly registered name. X is another operator.
  Registration does not require O to retain `deposit_operator`, have an enabled period or be a Policy.
- D is permissionless. Fuzz realizable nonzero callers without role exclusions. Seed an unrelated
  EOA, contract, ADMIN, config operator, emergency, deposit operator, O and X. Fund and approve each
  caller independently. Exercise a contract donor through a real forwarding call.
  Successful-call fuzzing excludes zero and DM itself because of the token's funding rules and exact
  custody-increase check. A07 and T09 retain those synthetic caller boundaries without adding roles.
- DM is Kernel-active and locally enabled unless a row varies these flags. D has sufficient tokens
  and allowance. The asset is configured; O and X have existing accounting unless varied.
- A is the requested underlying amount. Q is the actual asset-equivalent value of received custody.
  S is the exact received custody-share quantity. A successful call requires A, Q and S to be nonzero.
- L, B, U and H are target liabilities, borrowed principal, aggregate cap utilization and recorded
  custody shares. After success: H increases by S; L, B and U remain unchanged.
- Unchanged means all relevant token balances/allowances, vault assets/supply, recorded shares,
  receipts and wrappers, liabilities, borrowing, cap utilization, periods and FLOAN state match
  their pre-call values. A revert commits no events. Ignore changes caused by fixture setup itself.
- Successful calls change only the donor's funds/allowance, configured custody, O's shares and the
  two incoming-custody events. Other assets and X's recorded shares/liabilities/borrowing remain
  unchanged. Vault-wide rounding can change X's asset-equivalent valuation without changing shares.

Proposed guard order: shared reentrancy guard, own Kernel activity, configured asset, nonzero target,
registered target, nonzero input, mandatory custody transfer, nonzero actual credit, donation event.
Local enablement, target roles and asset periods are not admission gates.

## Caller and target attribution

| ID | Caller | Target / funding | Execution and effects | Test |
| --- | --- | --- | --- | --- |
| DM-DONATE-A01 | Fuzz D, including every role class above | Registered O distinct from D; D funds A | Return Q,S; debit D; credit only O's shares; no role requirement | Covered: [test][test_whenCallerVaries], [test][test_whenCallerRoleBoundarySeeds], [test][test_whenDonatingOwnUnderlying_thenCreditsOnlyTargetCustody] |
| DM-DONATE-A02 | O | Registered O=D | Return Q,S; own-namespace donation; no receipt or debt changes | Covered: [test][test_whenCallerVaries], [test][test_whenCallerRoleBoundarySeeds] |
| DM-DONATE-A03 | X with its own existing namespace | Registered O distinct from X | Credit O only; X's existing shares/accounting remain unchanged | Covered: [test][test_whenCallerVaries], [test][test_whenCallerRoleBoundarySeeds] |
| DM-DONATE-A04 | Unrelated attacker D | Victim has standing DM approval; D has zero balance and its own allowance | Exact fixture ERC20 insufficient-balance error for D; victim funds/allowance unchanged | Covered: [test][test_givenVictimApproval_whenDonorHasNoFunds_reverts] |
| DM-DONATE-A05 | Unrelated D | O's deposit role is revoked after deposits | Donation succeeds; O's role and product lifecycle remain unchanged | Covered: [test][test_givenTargetRoleRevoked_whenDonating] |
| DM-DONATE-A06 | Funded forwarding contract D | Originating EOA has standing allowance; only D approves and supplies A | Debit contract D, not tx.origin; credit O | Covered: [test][test_givenForwardingContract_whenDonating] |
| DM-DONATE-A07 | Synthetic zero caller | Configured standard OZ token, registered O, A=1, no zero-address allowance | `ERC20InsufficientAllowance(DM,0,1)` from token funding, not a donation authority error; Unchanged | Covered: [test][test_whenCallerZero_revertsWithFundingError] |

## Lifecycle and target readiness

All other inputs and funding pass. Re-enable and reactivation use their existing authorized lifecycle
routes; donation itself changes no lifecycle flag. The target is an accounting identity, not a
consumed operational service.

| ID | Caller | Local active | Local enabled | Target / period | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-DONATE-L01 | D | true | true | Registered O; period enabled | Donation succeeds | Covered: [test][test_whenCallerVaries] |
| DM-DONATE-L02 | D | true | false | Registered O; period enabled | Donation succeeds while ordinary deposits remain paused | Covered: [test][test_givenDisabled_whenDonating] |
| DM-DONATE-L03 | D | false | true | Registered O | `DepositManager_PolicyInactive()`; Unchanged | Covered: [test][test_givenPolicyInactive_whenDonating_reverts], [test][test_givenPolicyInactive_whenEnabledBoundarySeeds_reverts] |
| DM-DONATE-L04 | D | false | false | Registered O; also invalid target and amount=0 | `DepositManager_PolicyInactive()` before input checks; Unchanged | Covered: [test][test_givenPolicyInactive_whenDonating_reverts], [test][test_givenPolicyInactiveAndDisabled_whenInvalidInputs_reverts], [test][test_givenPolicyInactive_whenEnabledBoundarySeeds_reverts] |
| DM-DONATE-L05 | D | true, reactivated | true | Existing registered O/accounting | Donation succeeds without replacing accounting or configuration | Covered: [test][test_givenReactivatedAndReEnabled_whenDonating] |
| DM-DONATE-L06 | D | true | true, re-enabled | Existing registered O/accounting | Donation succeeds once; earlier donations persist | Covered: [test][test_givenReactivatedAndReEnabled_whenDonating] |
| DM-DONATE-L07 | D | true | Fuzz false/true; guarantee both | O's periods disabled | Donation succeeds without enabling periods or bypassing their ordinary-deposit gates | Covered: [test][test_givenTargetPeriodsUnavailable_whenDonating], [test][test_givenUnavailablePeriods_whenEnabledBoundarySeeds] |
| DM-DONATE-L08 | D | true | Fuzz false/true; guarantee both | Registered O has no period for this configured asset | Donation succeeds; no period or receipt token is created | Covered: [test][test_givenTargetPeriodsUnavailable_whenDonating], [test][test_givenUnavailablePeriods_whenEnabledBoundarySeeds] |
| DM-DONATE-L09 | D | true | Fuzz false/true; guarantee both | O is a locally disabled or Kernel-inactive product; guarantee both faults independently | Donation succeeds; no target-readiness probe; existing role/flags remain unchanged | Covered: [test][test_givenProductTargetUnavailable_whenDonating], [test][test_givenProductTargetUnavailable_whenLifecycleBoundarySeeds] |

## Invalid inputs and precedence

DM is active; no guarded operation is in progress. All fields not named in a row pass.

| ID | Caller | Asset | Target | Amount | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-DONATE-I01 | D | Zero | Registered O | 1 | `AssetManager_NotConfigured()`; Unchanged | Covered: [test][test_whenAssetUnconfigured_reverts], [test][test_whenUnconfiguredAssetBoundarySeeds_revert], [test][test_whenAssetUnconfigured_whenOtherInputsValid_reverts] |
| DM-DONATE-I02 | D | Nonzero unconfigured asset | Registered O | 1 | `AssetManager_NotConfigured()`; Unchanged | Covered: [test][test_whenAssetUnconfigured_reverts], [test][test_whenUnconfiguredAssetBoundarySeeds_revert], [test][test_whenAssetUnconfigured_whenOtherInputsValid_reverts] |
| DM-DONATE-I03 | D | Configured | Zero | 1 | `DepositManager_ZeroAddress()`; Unchanged | Covered: [test][test_whenTargetZero_reverts] |
| DM-DONATE-I04 | D | Configured | Fuzz nonzero unregistered target; seed DM when unregistered | 1 | `DepositManager_OperatorNameNotSet(target)`; Unchanged | Covered: [test][test_whenTargetUnregistered_reverts], [test][test_whenUnregisteredManagerTargetBoundarySeeds_revert] |
| DM-DONATE-I05 | D | Configured | Registered O | 0 | `AssetManager_ZeroAmount()` before transfers or vault deposit; Unchanged | Covered: [test][test_whenAmountZero_reverts] |
| DM-DONATE-I06 | D | Unconfigured | Zero | 0 | `AssetManager_NotConfigured()` before target and amount checks; Unchanged | Covered: [test][test_whenAssetUnconfigured_reverts], [test][test_whenUnconfiguredAssetBoundarySeeds_revert] |
| DM-DONATE-I07 | D | Configured | Nonzero unregistered | 0 | `DepositManager_OperatorNameNotSet(target)` before amount check; Unchanged | Covered: [test][test_whenTargetUnregistered_reverts], [test][test_whenUnregisteredManagerTargetBoundarySeeds_revert] |

## Amounts, rounding and custody variants

Fuzz supported routes separately. For each route, choose the full representable success interval
from its conversion and existing custody; do not replace it with an arbitrary fixture cap.
Seed each interval's endpoints. Name any conversion-overflow rejection outside that interval.

| ID | Caller | Custody and input domain / guaranteed seeds | Return and authoritative effects | Test |
| --- | --- | --- | --- | --- |
| DM-DONATE-N01 | D | Idle; H=0; A fuzz 1..MAX; seed 1,MAX | Q=S=A; DM underlying and O's shares increase by A; no normalization or new principal | Covered: [test][test_givenIdle_whenAmountVaries], [test][test_whenFullNumericBoundarySeeds] |
| DM-DONATE-N02 | D | Unseeded 1:1 ERC-4626; H=0; A fuzz 1..MAX; seed 1,MAX | Q=S=A; exact vault assets/supply and O's recorded shares agree | Covered: [test][test_givenUnseededVault_whenAmountVaries], [test][test_whenFullNumericBoundarySeeds] |
| DM-DONATE-N03 | D | Seed vault with 2 raw shares and 6 raw asset units; donate A=5 | floor(5*2/6)=1 share; post-deposit Q=floor(1*11/3)=3; S=1, Q=3; donor spends 5 | Covered: [test][test_givenThreeToOneVault_whenRoundingDown] |
| DM-DONATE-N04 | D | Same 3:1 vault; A=1 and A=2, separate deterministic executions | Fixture `MockERC4626.ZeroShares()`; Unchanged | Covered: [test][test_givenThreeToOneVault_whenOneUnit_reverts], [test][test_givenThreeToOneVault_whenTwoUnits_reverts] |
| DM-DONATE-N05 | D | Vault returns positive shares but synchronous valuation returns Q=0 | `AssetManager_ZeroAmount()`; rollback underlying, shares, namespace and logs | Covered: [test][test_givenZeroValuation_whenDonating_reverts] |
| DM-DONATE-N06 | D | Idle; L=B=2 from two borrowed then externally burned underlying units; H=0; D funds A=MAX without exceeding token supply | Q=S=MAX; L=B=2 and cap usage remain 2; `maxClaimYield` returns MAX-1 without overflow; later `claimYield(1)` succeeds although assets+B mathematically equals MAX+1 | Covered: [test][test_givenBorrowedPrincipal_whenMaximumDonation], [test][test_givenReceiptsRedeemedWithDebt_whenQuotingYield], [test][test_givenReceiptsRedeemedWithDebt_whenYieldExceedsUintMaximum_saturates] |
| DM-DONATE-N07 | D | Existing H>0; fuzz A over representable valid interval; seed 1 and maximum admissible A | Add exact S once to existing H; preserve prior liabilities, borrowed principal and receipts | Covered: [test][test_givenExistingCustody_whenAmountVaries], [test][test_givenExistingCustody_whenAmountBoundarySeeds], [test][test_givenExistingVaultCustody_whenAmountVaries], [test][test_givenExistingVaultCustody_whenAmountBoundarySeeds] |
| DM-DONATE-N08 | D | Vault supply=2 raw shares, backing=1 raw asset unit; D owns MAX-1 units and A=MAX-1 | `Panic(0x11)` from overflowing `Math.mulDiv(A,2,1)` before donation credit; Unchanged; no clamping of A | Covered: [test][test_givenTwoSharesPerAsset_whenConversionOverflows_reverts] |
| DM-DONATE-P01 | D | ERC-7575 self-share; 1:1 fixture, A=10e18 | Q=10e18, S=10e18; configured share token is vault | Covered: [test][test_givenERC7575SelfShare_whenDonating] |
| DM-DONATE-P02 | D | External ERC-7575 shares; asset 18 decimals, shares 6 decimals; rate 1e12 raw asset/share; A=10e18 | Q=10e18, S=10e6; share balance delta belongs to configured share token, not vault address | Covered: [test][test_givenERC7575ExternalShares_whenDonating] |
| DM-DONATE-P03 | D | ERC-7540 synchronous deposit and asynchronous redemption; separate shares as P02 | Same Q,S as P02; use `convertToAssets`; no `previewRedeem`, redeem or withdrawal request | Covered: [test][test_givenAsyncRedeemExternalShares_whenDonating] |
| DM-DONATE-P04 | D | ERC-7540 asynchronous redemption with self-share token; supported fixture | Exact received self-shares and independent convertToAssets value; no redemption | Covered: [test][test_givenAsyncRedeemSelfShares_whenDonating] |
| DM-DONATE-P05 | D | Non-standard vault with explicit share-withdrawal requirement; synchronous deposit works | Donation succeeds; do not impose an underlying-withdrawal capability check | Covered: [test][test_givenExplicitShareWithdrawalRequirement_whenDonating] |

N01/N02 use fresh tokens with zero initial supply/balances, so minting the MAX input remains valid.
N08 uses MAX-1 because the vault already holds one underlying unit. Its conversion result cannot
fit uint256. Match encoded `Panic(uint256)` with code 0x11. N06 requires safe
ordering of the existing solvency/yield arithmetic if direct additions overflow. Do not change the
one-unit yield reserve or impose a donation cap to hide this boundary.

## Recovery, namespace isolation and principal caps

Use a fee-free proportional vault with equal decimal scales. Seed O with 100 shares and 100 receipt
liabilities, then realize a vault loss to 80 asset units. Borrowed principal is zero unless named.
All quantities in the following fixed examples are raw units, not floating-point Solidity values.

| ID | Caller | Donation / namespace state | Execution and follow-up | Test |
| --- | --- | --- | --- | --- |
| DM-DONATE-P06 | D | A=8; vault mints 10 shares, Q=8 | S=10; custody=88,L=100; `maxClaimYield`=0; a 4-unit yield claim reverts `DepositManager_Insolvent(asset,100,84,0)` and preserves the earlier donation; ordinary deposit and par exit still reject | Covered: [test][test_givenLoss_whenPartialRepair], [test][test_givenBorrowedPrincipalAndLoss_whenPartialThenCompleteRepair] |
| DM-DONATE-P07 | D | A=20; vault mints 25 shares, Q=20 | Custody=L=100; `maxClaimYield`=0; a 4-unit yield claim reverts `DepositManager_Insolvent(asset,100,96,0)`; subsequent ordinary deposit of 20 succeeds and all 120 receipts withdraw 120 underlying | Covered: [test][test_givenLoss_whenExactRepair_thenNewDepositAndFullExit], [test][test_givenBorrowedPrincipalAndLoss_whenPartialThenCompleteRepair] |
| DM-DONATE-P08 | D | A=24; vault mints 30 shares, Q=24 | O custody value=104, L=100; surplus=4, `maxClaimYield`=3 due to the existing 1-unit reserve; no donor receipt | Covered: [test][test_givenLoss_whenSurplusDonation] |
| DM-DONATE-P09 | D | Positive U from existing deposits; governance lowers cap to 0 with minimum=0; any valid A | Donation succeeds despite zero principal cap and positive utilization; U and cap remain unchanged | Covered: [test][test_givenZeroCapAndPositiveUtilization_whenDonating] |
| DM-DONATE-P10 | D | O and X use the same vault; donate to O | Credit O only; X's recorded shares/liabilities/borrowed balance unchanged; no old debt is repaid | Covered: [test][test_whenCallerVaries], [test][test_givenTwoBorrowingNamespacesShareVault_whenDonating] |
| DM-DONATE-P11 | D | Same operator has two periods and mixed wrapped/unwrapped receipts | Donation backs the combined namespace; both receipt balances/supplies, wrappers and period data unchanged | Covered: [test][test_givenMixedReceiptsAcrossPeriods_whenDonating] |
| DM-DONATE-P12 | D | Registered O has L=B=H=0 | Donation succeeds as voluntary surplus; no receipt, position or period creation | Covered: [test][test_whenDonatingOwnUnderlying_thenCreditsOnlyTargetCustody] |
| DM-DONATE-P13 | D | Donate 8 then 12 in separate calls; independent fresh fixture | First call succeeds while insolvent; second restores custody value to 100; each amount credited once | Covered: [test][test_givenLoss_whenRepeatedPartialDonationsRepair] |
| DM-DONATE-P14 | D | Raw underlying or vault shares were transferred directly to DM before the call | Credit only shares from this call; unsolicited balances do not enter O's ledger; no sweep of other custody | Covered: [test][test_givenUnsolicitedUnderlyingAndShares_whenDonating] |
| DM-DONATE-P20 | D | Reachable configuration with cap>=minimum>A>0 | Donation succeeds below the ordinary minimum; U, cap and minimum remain unchanged | Covered: [test][test_givenPositiveMinimum_whenDonationBelowMinimum] |
| DM-DONATE-N09 | D | Rounding-repair fixture below; deficit=1 raw asset unit; A=2, a requested deficit+1 | `MockERC4626.ZeroShares()`; requested overpayment alone does not guarantee received shares; Unchanged | Covered: [test][test_givenRoundingRepair_whenInputTwo_reverts] |
| DM-DONATE-N10 | D | Same rounding-repair fixture; A=3 | S=1,Q=2; total O shares=34, value=101,L=99; repair succeeds despite input exceeding deficit; `maxClaimYield`=1 is theoretical and need not be deliverable as one underlying unit | Covered: [test][test_givenRoundingRepair_whenInputThree] |
| DM-DONATE-P21 | D | Independent rounding-repair fixture; A=6 | S=2,Q=5; O shares=35,value=104,L=99; `maxClaimYield`=4; `claimYield(asset,recipient,4)` transfers 2 underlying, leaves O value=102 and L=99 | Covered: [test][test_givenRoundingRepair_whenInputSix_thenRoundedYield] |

Rounding-repair fixture for N09/N10/P21: an external holder first deposits one raw asset unit for one
share, then transfers two underlying units directly to the vault. O then deposits 100 units,
receiving floor(100/3)=33 shares. The vault holds 103 assets and
34 shares; O's credited value and liability are floor(33*103/34)=99. A subsequent 2-unit loss leaves
101 vault assets, O value=floor(33*101/34)=98, and a one-unit deficit. No other state changes.
Each row starts independently from this fixture. N09 receives floor(2*34/101)=0 shares.
N10 receives floor(3*34/101)=1 share; post-deposit Q=floor(104/35)=2 and O value=floor(34*104/35)=101.
P21 receives floor(6*34/101)=2 shares; Q=floor(2*107/36)=5 and O value=floor(35*107/36)=104.
Its yield request of 4 converts to floor(4*36/107)=1 share and delivers floor(107/36)=2 assets.
The remaining vault has 105 assets and 35 shares; O owns 34 shares worth 102. These values distinguish
requested input, returned credit, combined custody value and actual yield delivery.

For P07, approve existing receipt burns and keep the period/product operational before checking exits.
Also prove partial and complete repair with a nonzero borrowed balance, using independent A, B and L
values that satisfy the existing borrowed<=liabilities invariant. Donations never reduce B.

## Overpayments and yield

Overpayments are accepted. Use actual received shares and their asset-equivalent value, not nominal
input minus the pre-call deficit, to determine whether a surplus exists. A requested overpayment can
disappear into vault rounding. Any actual surplus belongs to O under the existing yield rules.

Every follow-up below uses O holding `deposit_operator`, an active/enabled DM, and a nonzero yield
recipient distinct from DM. D supplies the donation; D gains no authority to claim O's yield.
Borrowed principal, receipts, liabilities and U remain unchanged through donation and yield claims.
The existing `maxClaimYield` quote retains its one-unit safety adjustment. It is not an additional
hard cap on an explicitly requested `claimYield`; execution instead checks final solvency.

| ID | Caller | Custody / overpayment domain | Donation, yield quote and actual claim | Test |
| --- | --- | --- | --- | --- |
| DM-DONATE-N11 | D, then O for the failed yield claim | Rounded-overpayment fixture below; deficit=2,A=3 | S=1,Q=2; O custody value=L=4; `maxClaimYield`=0; nominal overpayment creates no surplus; O's yield request3 reverts `DepositManager_Insolvent(asset,4,2,0)` with the earlier donation intact | Covered: [test][test_givenNominalOverpaymentConsumedByRounding_whenClaiming_reverts] |
| DM-DONATE-P22 | D, then O | Idle custody already has assets=L=100,B=0; fuzz A=1..MAX-100; seed 1,2,MAX-100; all other token balances start zero | Donation credits Q=S=A and leaves U=100; `maxClaimYield`=A-1; O explicitly claims A and receives exactly A; custody returns to100, L=100,B=0 and no receipts burn | Covered: [test][test_givenIdleAtPar_whenOverpaymentVaries_thenClaimsActualSurplus], [test][test_givenIdleAtPar_whenOverpaymentBoundarySeeds] |
| DM-DONATE-P23 | D, then O | Standard vault; O owns 100 shares and L=100; loss leaves80 assets; A=20+4k; fuzz k=1..floor((MAX-125)/5), seed1 and maximum | Donation S=25+5k,Q=A; O value=100+4k; quote=4k-1; claiming that quote redeems5k-2 shares and delivers4k-2 underlying; O then owns127 shares worth102, L=100,B=0,U=100 | Covered: [test][test_givenLoss_whenProportionalOverpaymentVaries_thenClaimsRoundedQuote], [test][test_givenLoss_whenProportionalOverpaymentBoundarySeeds] |
| DM-DONATE-P24 | D, then O | Idle custody assets=60,B=40,L=100,U=100; donate A=8 | Donation Q=S=8; B remains40; quote=7; O claims7 and receives7; custody=61,B=40,L=100,U=100; no loan principal is reduced by donation or yield claim | Covered: [test][test_givenBorrowedPrincipal_whenDonatingSurplus_thenClaimsYield] |

N11 fixture: the external holder deposits one raw asset unit, then transfers two units directly to
the vault, producing one share backed by three assets. O deposits 5 and receives one share.
The vault has 8 assets and 2 shares; O's receipt credit and L=floor(1*8/2)=4. A loss of 4 leaves
vault assets=4, O custody value=2 and deficit=2. A donation of 3 mints floor(3*2/4)=1 share.
The vault then holds 7 assets and 3 shares; Q=floor(7/3)=2. O's two shares are worth floor(14/3)=4.
A yield request of 3 converts to one share and attempts to redeem 2 assets, leaving O value=2<L=4.
That yield transaction reverts atomically and does not undo the earlier donation.

P22 uses exact idle transfers. At A=1 the quote is 0 because of its safety adjustment.
An explicit one-unit claim still preserves solvency and returns 1. Do not impose a new quote-based claim cap.
P23 keeps all custody shares in O's namespace. Its k bound follows the maximum total share supply,
125+5k<=MAX; it is not an arbitrary test cap. Donation and redemption conversions use independent
closed-form expectations. Rounding leaves two units of actual surplus after the quoted claim.

## Mandatory transfers and reentrancy

Use the existing exact-transfer and vault fixtures. Match exact encoded fixture errors.
The values below are observed inside the reverting call; externally committed state remains unchanged.

| ID | Caller | Fault / callback | Execution and effects | Test |
| --- | --- | --- | --- | --- |
| DM-DONATE-T01 | D | Funded standard OZ token; allowance fuzz 0..A-1, seed 0,A-1; A>=1 | `ERC20InsufficientAllowance(DM,allowance,A)`; Unchanged | Covered: [test][test_whenAllowanceInsufficient_reverts], [test][test_whenFundingFailureBoundarySeeds_revert] |
| DM-DONATE-T02 | D | Standard OZ token; balance fuzz 0..A-1, seed 0,A-1; allowance>=A; A>=1 | `ERC20InsufficientBalance(D,balance,A)`; Unchanged | Covered: [test][test_whenBalanceInsufficient_reverts], [test][test_whenFundingFailureBoundarySeeds_revert] |
| DM-DONATE-T03 | D | Fee-on-transfer underlying receives `R<A` | `SafeERC20Exact_InexactTransferFrom(asset,DM,A,R)`; Unchanged | Covered: [test][test_givenInexactUnderlying_whenDonating_reverts] |
| DM-DONATE-T04 | D | Vault returns S but configured share balance receives R!=S; seed too few, too many and zero received in separate executions | `AssetManager_InexactSharesReceived(asset,shareToken,S,R)`; Unchanged | Covered: [test][test_givenVaultMintsTooFewShares_whenDonating_reverts], [test][test_givenVaultMintsTooManyShares_whenDonating_reverts], [test][test_givenVaultMintsNoShares_whenDonating_reverts] |
| DM-DONATE-T05 | D | Vault reports zero shares after underlying transfer | `AssetManager_ZeroAmount()` if the fixture returns zero; Unchanged | Covered: [test][test_givenVaultReturnsZeroShares_whenDonating_reverts] |
| DM-DONATE-T06 | D | Configured vault later enables asynchronous deposits | Fixture `AsyncDeposit()`; Unchanged; no asynchronous request is recorded | Covered: [test][test_givenVaultSwitchesToAsyncDeposit_whenDonating_reverts] |
| DM-DONATE-T07 | D | Vault deposit deliberately reverts | Exact fixture deposit error; Unchanged | Covered: [test][test_givenVaultDepositFails_whenDonating_reverts] |
| DM-DONATE-T08 | D | Required synchronous or asynchronous-mode valuation call reverts after mint; guarantee each route separately | Exact fixture valuation error; full rollback | Covered: [test][test_givenSyncValuationFails_whenDonating_reverts], [test][test_givenAsyncValuationFails_whenDonating_reverts] |
| DM-DONATE-T09 | Synthetic DM self-caller with its own allowance | `A>0` from DM to itself; no net custody increase | `SafeERC20Exact_InexactTransferFrom(asset,DM,A,0)`; no allocation of existing raw balances | Covered: [test][test_givenManagerSelfCaller_whenDonating_reverts] |
| DM-DONATE-T10 | D | Standard OZ token; both balance and allowance below A; seed both=0 and both=A-1 | `ERC20InsufficientAllowance(DM,allowance,A)` before the balance check; Unchanged | Covered: [test][test_whenBalanceAndAllowanceInsufficient_reverts], [test][test_whenFundingFailureBoundarySeeds_revert] |
| DM-DONATE-C01 | D | Underlying transfer callback attempts a fully funded/otherwise eligible nested donation; catches error | Nested `ReentrancyGuardReentrantCall()`; outer donation succeeds once | Covered: [test][test_givenUnderlyingCallbackCaught_whenDonating] |
| DM-DONATE-C02 | D | Same callback propagates nested guard error | Exact propagated fixture error; outer donation and all custody effects roll back | Covered: [test][test_givenUnderlyingCallbackPropagates_whenDonating_reverts] |
| DM-DONATE-C03 | Authorized ordinary deposit operator | Ordinary-deposit vault callback attempts an otherwise valid donation | Shared guard rejects nested donation; caught outer deposit succeeds once and finishes solvent | Covered: [test][test_givenOrdinaryDepositVaultCallback_whenNestedDonation] |

## Stateful acceptance criteria

Use independent ghost accounting for each configured asset and operator. Handler actions include
ordinary deposit, donation, vault gain/loss, withdrawal, yield, borrow/repay and local pause/resume.
Keep caller funding and target selection independent. Do not assert universal solvency after external
loss or partial donation. Run ordinary-deposit and donation success checks at each action's end.

| ID | Handler domain | Required property | Test |
| --- | --- | --- | --- |
| DM-DONATE-P15 | Arbitrary supported action sequences | Successful donation increases only the selected namespace's custody ledger by actual S; liabilities, receipts, borrowing and U stay unchanged for that donation | Covered: [invariant][invariant_donationsPreserveIndependentPrincipalAndCustodyModels], [test][test_givenAllCustodyRoutes_whenDeterministicActionSequence] |
| DM-DONATE-P16 | Gain/loss, partial repair and ordinary deposits | Every successful ordinary deposit finishes solvent; partial donations can leave a deficit; no donation creates a depositor claim | Covered: [invariant][invariant_donationsPreserveIndependentPrincipalAndCustodyModels], [test][test_givenAllCustodyRoutes_whenDeterministicActionSequence] |
| DM-DONATE-P17 | Idle, self-share and external-share routes; exact-transfer tokens | Sum of recorded shares equals physical managed custody in clean fixtures; with unsolicited transfers, custody is at least the sum and donations never allocate the unsolicited surplus | Covered: [invariant][invariant_donationsPreserveIndependentPrincipalAndCustodyModels], [test][test_givenAllCustodyRoutes_whenDeterministicActionSequence] |

## Interface and implementation acceptance

| ID | Surface | Required result | Test |
| --- | --- | --- | --- |
| DM-DONATE-P18 | Compiled `IDepositManagerV1_1`, DM and V1.1 consumers/mocks | Donate selector callable through V1.1; DM advertises the compiled V1.1 interface; existing V1 and asset-manager interfaces remain supported | Covered: [test][test_whenQueryingInterfacesAndVersion] |
| DM-DONATE-P19 | Legacy V1 interface and selectors | `IDepositManager.sol` unchanged; its pinned pre-change interface ID remains supported; VERSION returns 1,1 | Covered: [test][test_whenQueryingInterfacesAndVersion] |

The initial donation and F-3 deposit regressions were recorded red before production implementation.
Map these rows to focused tests only after their assertions and execution prove the stated domains.
Deployment acceptance requires the unchanged deploy profile and runtime <=24,576 bytes, with the
24,552-byte baseline, delta and remaining margin reported. Final measured runtime is 24,474 bytes:
78 bytes below baseline and 102 bytes below EIP-170. A size overage is not a reason to weaken
these scenarios or change optimizer settings.

[test_whenCallerVaries]: ./donate.t.sol#L33
[test_whenCallerRoleBoundarySeeds]: ./donate.t.sol#L46
[test_givenVictimApproval_whenDonorHasNoFunds_reverts]: ./donate.t.sol#L65
[test_givenTargetRoleRevoked_whenDonating]: ./donate.t.sol#L84
[test_givenForwardingContract_whenDonating]: ./donate.t.sol#L98
[test_whenCallerZero_revertsWithFundingError]: ./donate.t.sol#L123
[test_givenDisabled_whenDonating]: ./donate.t.sol#L137
[test_givenPolicyInactive_whenDonating_reverts]: ./donate.t.sol#L152
[test_givenPolicyInactiveAndDisabled_whenInvalidInputs_reverts]: ./donate.t.sol#L170
[test_givenPolicyInactive_whenEnabledBoundarySeeds_reverts]: ./donate.t.sol#L185
[test_givenReactivatedAndReEnabled_whenDonating]: ./donate.t.sol#L193
[test_givenTargetPeriodsUnavailable_whenDonating]: ./donate.t.sol#L212
[test_givenUnavailablePeriods_whenEnabledBoundarySeeds]: ./donate.t.sol#L232
[test_givenProductTargetUnavailable_whenDonating]: ./donate.t.sol#L240
[test_givenProductTargetUnavailable_whenLifecycleBoundarySeeds]: ./donate.t.sol#L271
[test_whenAssetUnconfigured_reverts]: ./donate.t.sol#L283
[test_whenUnconfiguredAssetBoundarySeeds_revert]: ./donate.t.sol#L294
[test_whenAssetUnconfigured_whenOtherInputsValid_reverts]: ./donate.t.sol#L302
[test_whenTargetZero_reverts]: ./donate.t.sol#L313
[test_whenTargetUnregistered_reverts]: ./donate.t.sol#L320
[test_whenUnregisteredManagerTargetBoundarySeeds_revert]: ./donate.t.sol#L337
[test_whenAmountZero_reverts]: ./donate.t.sol#L345
[test_givenIdle_whenAmountVaries]: ./donate.t.sol#L354
[test_givenUnseededVault_whenAmountVaries]: ./donate.t.sol#L364
[test_whenFullNumericBoundarySeeds]: ./donate.t.sol#L374
[test_givenThreeToOneVault_whenRoundingDown]: ./donate.t.sol#L386
[test_givenThreeToOneVault_whenOneUnit_reverts]: ./donate.t.sol#L397
[test_givenThreeToOneVault_whenTwoUnits_reverts]: ./donate.t.sol#L402
[test_givenZeroValuation_whenDonating_reverts]: ./donate.t.sol#L417
[test_givenBorrowedPrincipal_whenMaximumDonation]: ./donate.t.sol#L428
[test_givenReceiptsRedeemedWithDebt_whenQuotingYield]: ./donate.t.sol#L445
[test_givenReceiptsRedeemedWithDebt_whenYieldExceedsUintMaximum_saturates]: ./donate.t.sol#L466
[test_givenExistingCustody_whenAmountVaries]: ./donate.t.sol#L490
[test_givenExistingCustody_whenAmountBoundarySeeds]: ./donate.t.sol#L500
[test_givenExistingVaultCustody_whenAmountVaries]: ./donate.t.sol#L508
[test_givenExistingVaultCustody_whenAmountBoundarySeeds]: ./donate.t.sol#L519
[test_givenTwoSharesPerAsset_whenConversionOverflows_reverts]: ./donate.t.sol#L527
[test_givenERC7575SelfShare_whenDonating]: ./donate.t.sol#L539
[test_givenERC7575ExternalShares_whenDonating]: ./donate.t.sol#L562
[test_givenAsyncRedeemExternalShares_whenDonating]: ./donate.t.sol#L576
[test_givenAsyncRedeemSelfShares_whenDonating]: ./donate.t.sol#L590
[test_givenExplicitShareWithdrawalRequirement_whenDonating]: ./donate.t.sol#L599
[test_givenLoss_whenPartialRepair]: ./donate.t.sol#L612
[test_givenLoss_whenExactRepair_thenNewDepositAndFullExit]: ./donate.t.sol#L641
[test_givenLoss_whenSurplusDonation]: ./donate.t.sol#L664
[test_givenZeroCapAndPositiveUtilization_whenDonating]: ./donate.t.sol#L677
[test_givenTwoBorrowingNamespacesShareVault_whenDonating]: ./donate.t.sol#L698
[test_givenMixedReceiptsAcrossPeriods_whenDonating]: ./donate.t.sol#L733
[test_givenLoss_whenRepeatedPartialDonationsRepair]: ./donate.t.sol#L759
[test_givenUnsolicitedUnderlyingAndShares_whenDonating]: ./donate.t.sol#L769
[test_givenPositiveMinimum_whenDonationBelowMinimum]: ./donate.t.sol#L786
[test_givenRoundingRepair_whenInputTwo_reverts]: ./donate.t.sol#L800
[test_givenRoundingRepair_whenInputThree]: ./donate.t.sol#L810
[test_givenRoundingRepair_whenInputSix_thenRoundedYield]: ./donate.t.sol#L824
[test_givenNominalOverpaymentConsumedByRounding_whenClaiming_reverts]: ./donate.t.sol#L844
[test_givenIdleAtPar_whenOverpaymentVaries_thenClaimsActualSurplus]: ./donate.t.sol#L865
[test_givenIdleAtPar_whenOverpaymentBoundarySeeds]: ./donate.t.sol#L890
[test_givenLoss_whenProportionalOverpaymentVaries_thenClaimsRoundedQuote]: ./donate.t.sol#L900
[test_givenLoss_whenProportionalOverpaymentBoundarySeeds]: ./donate.t.sol#L926
[test_givenBorrowedPrincipal_whenDonatingSurplus_thenClaimsYield]: ./donate.t.sol#L936
[test_givenBorrowedPrincipalAndLoss_whenPartialThenCompleteRepair]: ./donate.t.sol#L958
[test_whenAllowanceInsufficient_reverts]: ./donate.t.sol#L982
[test_whenBalanceInsufficient_reverts]: ./donate.t.sol#L1003
[test_whenBalanceAndAllowanceInsufficient_reverts]: ./donate.t.sol#L1024
[test_whenFundingFailureBoundarySeeds_revert]: ./donate.t.sol#L1050
[test_givenInexactUnderlying_whenDonating_reverts]: ./donate.t.sol#L1066
[test_givenVaultMintsTooFewShares_whenDonating_reverts]: ./donate.t.sol#L1110
[test_givenVaultMintsTooManyShares_whenDonating_reverts]: ./donate.t.sol#L1115
[test_givenVaultMintsNoShares_whenDonating_reverts]: ./donate.t.sol#L1120
[test_givenVaultReturnsZeroShares_whenDonating_reverts]: ./donate.t.sol#L1125
[test_givenVaultSwitchesToAsyncDeposit_whenDonating_reverts]: ./donate.t.sol#L1136
[test_givenVaultDepositFails_whenDonating_reverts]: ./donate.t.sol#L1149
[test_givenSyncValuationFails_whenDonating_reverts]: ./donate.t.sol#L1176
[test_givenAsyncValuationFails_whenDonating_reverts]: ./donate.t.sol#L1181
[test_givenManagerSelfCaller_whenDonating_reverts]: ./donate.t.sol#L1186
[test_givenUnderlyingCallbackCaught_whenDonating]: ./donate.t.sol#L1221
[test_givenUnderlyingCallbackPropagates_whenDonating_reverts]: ./donate.t.sol#L1235
[test_givenOrdinaryDepositVaultCallback_whenNestedDonation]: ./donate.t.sol#L1246
[test_whenQueryingInterfacesAndVersion]: ./donate.t.sol#L1269
[test_whenDonatingOwnUnderlying_thenCreditsOnlyTargetCustody]: ./donate.t.sol#L1302
[invariant_donationsPreserveIndependentPrincipalAndCustodyModels]: ./DepositManagerDonation.invariant.t.sol#L77
[test_givenAllCustodyRoutes_whenDeterministicActionSequence]: ./DepositManagerDonation.invariant.t.sol#L82
