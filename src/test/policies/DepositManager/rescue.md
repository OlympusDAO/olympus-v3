# DepositManager.rescue coverage plan

Sources: [rescue and authorization](../../../policies/deposits/DepositManager.sol#L1221),
[managed-token classification](../../../bases/BaseAssetManager.sol#L480),
[controller identity](../../../policies/utils/ConfigOperatorSingleStep.sol#L46), and
[delayed rescue](../DepositManagerConfigTimelock/queueRescue.md).

## Acceptance criteria and current implementation

This plan specifies the agreed change: ADMIN may rescue directly; a delegated manager must propose
rescue through DepositManagerConfigTimelock (DMCT). DepositManager (DM) accepts its selected nonzero
config operator or ADMIN. Holding `deposit_manager_admin` alone no longer authorizes direct rescue.
Treasury remains the only destination. Configured underlying assets, vault entry points and stored
share tokens remain protected, regardless of liabilities, route enablement or custody balance.

The implementation uses the existing config-authority predicate for rescue, retaining separate
manager-only reEnable authority. `rescue` and `previewRescue` belong to `IDepositManagerV1_1`.
Both functions use the same eligibility, balance and Treasury checks. Zero and no-code tokens use
the existing `DepositManager_CannotRescueAsset(token)` error, matching managed-token rejection.

`previewRescue(address token) returns (uint256 amount)` is required alongside rescue. Keep its
scenarios and assertions in this action's document and test file. It is permissionless, requires DM
Kernel activity, permits local disablement, and validates token eligibility, the balance read and
current Treasury availability. It returns the live full balance, including zero. Share these
checks with execution so a quote cannot silently bypass a rescue eligibility rule. DMCT uses this
canonical preview for queue admission instead of recreating DM's token classifier.

Execution alone authenticates its caller, acquires the shared reentrancy guard and performs the
mandatory transfer. A successful preview does not prove those execution-only conditions. It makes
no transfer/approval, changes no state, and emits no event. For otherwise equivalent state, compare
the exact quoted amount/error with execution; use independently seeded balances and custody deltas
as the oracle, rather than deriving expected output only from the preview.

## Domains, fixtures and effects

- A is a fuzzed ADMIN_ROLE holder. C is DM's selected nonzero `configOperator`; C need not hold any
  role. Exercise A-only, C-only and overlapping authority, guaranteeing each exclusive class.
- V is the independently fuzzed preview viewer, with no role exclusions. Seed unrelated EOAs and
  contracts, M, E, O, A, C and zero. Changing only V must not change the quote/error. V never supplies
  execution authority on another caller's behalf.
- M holds only DEPOSIT_MANAGER_ADMIN_ROLE. E holds only EMERGENCY_ROLE. O holds only
  DEPOSIT_OPERATOR_ROLE. None is A or C unless a row explicitly grants overlapping authority.
- Unauthorized fuzzing excludes every ADMIN_ROLE holder and C; include M, E, O, a previously selected
  operator, unrelated contracts, EOAs and the zero address as deterministic caller seeds.
- T is an otherwise unmanaged ERC-20 with a canonical `balanceOf`; R is the current TRSRY module.
  B is DM's balance of T in raw token units, independent of token decimals. Fuzz B in 0..MAX256,
  guaranteeing 0, 1 and MAX256. Give R zero T for the MAX256 seed to avoid fixture-supply overflow.
- Unless varied, DM is Kernel-active and locally enabled, ROLES is initialized, R is installed,
  C=DMCT, B>0, and DMCT has no ADMIN or deposit-manager-admin grant.
- `Sweep(B)` means DM's T balance falls by B to zero, R's rises by B, and exactly one
  `TokenRescued(T,B)` event is emitted by DM. No value is returned. For B=0, no transfer or rescue event.
- Unchanged means underlying/share custody, per-operator assets/shares, liabilities, borrowed amounts,
  receipt supply/balances, aggregate cap utilization, asset/route registries, allowances,
  configuration and lifecycle fields stay equal. Successful rescue changes only the specified stray
  token balances and event. A revert restores every balance, allowance and state field and commits
  no logs. Check multiple operators and at least two configured assets, including unrelated routes.

Errors below use their declaring interfaces: `ConfigOperator_Unauthorized(caller)` from
[IConfigOperator](../../../policies/interfaces/utils/IConfigOperator.sol),
`DepositManager_PolicyInactive()` from [V1.1](../../../policies/interfaces/deposits/IDepositManagerV1_1.sol),
and `DepositManager_CannotRescueAsset(token)` from
[IDepositManager](../../../policies/interfaces/deposits/IDepositManager.sol).
`ReentrancyGuardReentrantCall()` is the inherited transient guard error.

## Authorization

DM active/enabled; T eligible and funded. State and token faults are varied separately below.

Preview is requested by V in every row, independently of the execution caller.

| ID | Caller | Selected operator / role grants | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-A01 | Fuzz A-only, C-only, and A=C | C nonzero; seed each authority class | B | Success | Sweep(B); Unchanged accounting | Covered: [test][test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview], [test][test_givenAdmin_whenRescuing_matchesPermissionlessPreview], [test][test_givenEachAuthorityClass_whenRescuing] |
| DM-RESCUE-A02 | Fuzz outside ADMIN holders and C | Include M, E, O, unrelated callers and zero | B; no viewer/caller authorization lookup | ConfigOperator_Unauthorized(caller) | Unchanged | Covered: [test][test_whenCallerIsUnauthorized_reverts], [test][test_givenEachUnauthorizedClass_whenRescuing_reverts] |
| DM-RESCUE-A03 | M | C=DMCT; M has no ADMIN grant | B | ConfigOperator_Unauthorized(M) | No direct-manager delay bypass | Covered: [test][test_givenContractDisabled_whenCallerIsDepositManagerAdmin_reverts], [test][test_givenContractEnabled_whenCallerIsDepositManagerAdmin_reverts], [test][test_givenEachUnauthorizedClass_whenRescuing_reverts] |
| DM-RESCUE-A04 | Previously selected C0 | DM now selects C1; C0 lacks ADMIN | B | ConfigOperator_Unauthorized(C0) | Unchanged | Covered: [test][test_givenOperatorRotated_whenOldOperatorRescues_reverts] |
| DM-RESCUE-A05 | Zero caller | Delegation cleared to zero; zero lacks ADMIN | B | ConfigOperator_Unauthorized(address(0)) | Zero never becomes an authorized operator | Covered: [test][test_givenDelegationCleared_whenZeroCallerRescues_reverts] |
| DM-RESCUE-A06 | A | C zero, broken, disabled or Kernel-inactive; guarantee each | B without probing C | Success without probing C | Sweep(B); governance fallback independent of controller readiness | Covered: [test][test_givenNoController_whenAdminRescues], [test][test_givenControllerViewsBroken_whenAdminRescues], [test][test_givenControllerDisabled_whenAdminRescues], [test][test_givenControllerInactive_whenAdminRescues] |
| DM-RESCUE-A07 | C | Fuzz selected EOA or contract identity; no ADMIN grant | B | Success; selection is the authority | Sweep(B); no controller interface/lifecycle requirement on DM | Covered: [test][test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview], [test][test_givenEachAuthorityClass_whenRescuing] |

## Lifecycle and guard precedence

Use initialized/cached ROLES after real Kernel activation/deactivation. Do not conflate this with a
never-activated instance whose ROLES pointer is unset. Seed both booleans wherever grouped.
For L02/L03, fuzz the two independent boolean inputs `policyActive` and `locallyEnabled`, the
authorized execution caller, V and B. Exercise all four activity/enablement pairs with deterministic
seed drivers: inactive/disabled and inactive/enabled revert; active/disabled and active/enabled
succeed. Do not discard disabled or inactive inputs with assumptions or early returns. Prove
local-disabled success with B>0 and an actual Treasury transfer, as well as the B=0 no-op. Quote and
execute under identical state before any transfer or lifecycle change; neither action changes the
enabled flag. Retain L01 as the separate competing-fault regression.

| ID | Caller | Local active | Local enabled | Token / competing fault | Preview | Execution and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-L01 | Any address, fuzz, without authorization exclusions | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DM; token=address(0) | DepositManager_PolicyInactive() before token validation | DepositManager_PolicyInactive() before rescue authority and token checks | Revert; no effects of the attempted action commit | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst] |
| DM-RESCUE-L02 | Fuzz A or C | true | Fuzz false/true; guarantee disabled | Eligible T; fuzz B=0..MAX256 and seed 0,1,MAX256 | B from every V, including while disabled | Success while paused or enabled | Sweep(B) for B>0, otherwise no-op; enabled flag unchanged | Covered: [test][test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview], [test][test_givenAdmin_whenRescuing_matchesPermissionlessPreview], [test][test_givenLifecycleBoundarySeeds_whenRescuing] |
| DM-RESCUE-L03 | Fuzz A or C | false | Fuzz false/true | Eligible T; fuzz B independently | DepositManager_PolicyInactive() from every V | DepositManager_PolicyInactive() | Unchanged | Covered: [test][test_givenPolicyInactive_whenRescuing_revertsRegardlessOfEnablement], [test][test_givenInactiveLifecycleBoundarySeeds_whenRescuing_reverts], [test][test_givenSelectedOperatorAndPolicyInactive_whenRescuing_reverts], [test][test_givenSelectedOperatorInactiveBoundarySeeds_whenRescuing_reverts], [test][test_givenPolicyReactivated_whenRescuing] |
| DM-RESCUE-L04 | Fuzz A or C | true | true | After disable/reEnable within grace | B | Success | Sweep(B); preserve transition history | Covered: [test][test_givenReEnabled_whenRescuing_preservesTransitionHistory], [test][test_givenSelectedOperatorAndReEnabled_whenRescuing_preservesTransitionHistory] |
| DM-RESCUE-L05 | Unauthorized caller | true | Fuzz false/true | Zero or managed token; seed each | DepositManager_CannotRescueAsset(token) | ConfigOperator_Unauthorized(caller) before token validation; caller authentication is execution-only | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenTokenZero_revertsAuthorityFirst], [test][test_givenUnauthorizedCaller_whenManagedToken_revertsAuthorityFirst], [test][test_givenAuthorityFirstLifecycleSeeds_whenRescuing_reverts] |
| DM-RESCUE-L06 | A | Fuzz false/true | Fuzz false/true | Already inside a guarded token-moving operation; otherwise valid nested rescue | B if active, otherwise DepositManager_PolicyInactive(); no execution guard acquired by view | ReentrancyGuardReentrantCall() before lifecycle/authority/input checks | No nested effects | Covered: [test][test_givenActivePolicyDuringCallback_whenRescueReenters_guardWins], [test][test_givenInactivePolicyDuringCallback_whenRescueReenters_guardWins], [test][test_givenEachCallbackLifecyclePair_whenRescuing_guardWins] |
| DM-RESCUE-L07 | A | true | Fuzz false/true | Asset cap below utilization; route disabled; outstanding borrows | B | Success for unmanaged T | Sweep(B); preserve debt, receipts and utilization | Covered: [test][test_givenUtilizationExceedsLoweredCap_whenRescuingUnmanagedToken_succeeds], [test][test_givenIndebtedDisabledRouteLifecycleSeeds_whenRescuing] |

## Token eligibility

Use A with DM active; local enabled is independently fuzzed and both values seeded. W denotes a
configured vault entry point; S is its onboarding-time stored share token. A managed-token balance
of zero does not weaken protection. Guarantee B=0 and B>0 in each managed-token family.

Preview is requested by V. In this table, both functions must return the exact same error selector
and arguments; token rejection precedes any token balance read or transfer.

| ID | Caller | Token / configuration | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-I01 | A | token=address(0); no configured assets, idle route, and vault route fixtures | DepositManager_CannotRescueAsset(address(0)) | Same exact error in every fixture | Unchanged; no opaque revert | Covered: [test][test_rescue_givenNoManagedAssets_givenTokenAddressZero_reverts], [test][test_rescue_givenAssetWithZeroVault_givenTokenAddressZero_reverts], [test][test_rescue_givenAssetWithVault_givenTokenAddressZero_reverts], [test][test_givenZeroAndNoCodeLifecycleSeeds_whenRescuing_reverts] |
| DM-RESCUE-I02 | A | Nonzero no-code address, including an EOA | DepositManager_CannotRescueAsset(token) | Same exact error | Unchanged | Covered: [test][test_whenTokenHasNoCode_revertsConsistently], [test][test_givenZeroAndNoCodeLifecycleSeeds_whenRescuing_reverts] |
| DM-RESCUE-I03 | A | Configured underlying; idle custody or vault custody | DepositManager_CannotRescueAsset(token) | Same exact error | No managed underlying transfer | Covered: [test][test_rescue_givenTokenIsConfiguredAsset_reverts], [test][test_givenManagedUnderlying_whenBalanceVaries_reverts], [test][test_givenManagedIdleUnderlying_whenBalanceVaries_reverts], [test][test_givenManagedBalanceBoundarySeeds_whenRescuing_reverts] |
| DM-RESCUE-I04 | A | Configured vault W; standard ERC-4626 or ERC-7575 entry point | DepositManager_CannotRescueAsset(W) | Same exact error | No vault-token transfer | Covered: [test][test_rescue_givenTokenIsConfiguredVault_reverts], [test][test_givenManagedVault_whenBalanceVaries_reverts], [test][test_givenManagedBalanceBoundarySeeds_whenRescuing_reverts] |
| DM-RESCUE-I05 | A | Stored external share token S distinct from underlying and W | DepositManager_CannotRescueAsset(S) | Same exact error | No share-token transfer | Covered: [test][test_givenTokenIsConfiguredExternalShareToken_reverts], [test][test_givenManagedExternalShares_whenBalanceVaries_reverts], [test][test_givenManagedBalanceBoundarySeeds_whenRescuing_reverts] |
| DM-RESCUE-I06 | A | W now reports another share token or its share getter reverts; rescue stored S | DepositManager_CannotRescueAsset(S) without querying W's live share getter | Same exact error without mutable lookup | Stored custody identity remains protected | Covered: [test][test_givenVaultChangesReportedShare_whenRescuingStoredShare_reverts], [test][test_givenVaultShareReadReverts_whenRescuingStoredShare_reverts], [test][test_givenStoredShareAndRetiredRouteBoundarySeeds_whenRescuing_reverts] |
| DM-RESCUE-I07 | A | Configured asset/W/S after every associated route is disabled and liabilities reach zero | DepositManager_CannotRescueAsset(token) | Same exact error | No retirement-by-disable rescue loophole | Covered: [test][test_rescue_givenTokenIsConfiguredAsset_givenAssetDisabled_reverts], [test][test_givenDisabledEmptyExternalShareRoute_whenRescuingAnyManagedToken_reverts], [test][test_givenStoredShareAndRetiredRouteBoundarySeeds_whenRescuing_reverts] |
| DM-RESCUE-I08 | A | Configured asset/W/S with unsolicited balance above all recorded obligations | DepositManager_CannotRescueAsset(token) | Same exact error | This API never recovers managed-token surplus | Covered: [test][test_givenManagedTokenSurplus_whenRescuing_reverts], [test][test_givenStoredExternalShareSurplus_whenRescuing_reverts], [test][test_givenManagedSurplusLifecycleSeeds_whenRescuing_reverts] |

## Balances, Treasury and transfers

T remains eligible. R0 and R1 are distinct installed Treasury module instances. Use raw units,
including tokens with 6, 9 and 18 decimals; rescue performs no conversion or rounding.

Preview is requested by V and must leave the full Unchanged snapshot intact. Compare the quote
against the independently funded B before execution, then assert actual Treasury/DM balance deltas,
the event amount and protected accounting. Repeat preview after successful execution: it returns
zero and the next execution is a no-op. If T receives more tokens between calls, a fresh quote and
execution use the new live balance; the old quote does not reserve or cap it.

| ID | Caller | Balance / external condition | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-N01 | A | B=0; transfer mock would revert if called | 0 | Success, no-op | No transfer call or TokenRescued event from either call; Unchanged | Covered: [test][test_givenZeroBalance_whenTransferWouldFail_isNoOp], [test][test_givenSixDecimals_whenRescuing_matchesRawBalance], [test][test_givenNineDecimals_whenRescuing_matchesRawBalance], [test][test_givenEighteenDecimals_whenRescuing_matchesRawBalance], [test][test_givenTokenDecimalBoundarySeeds_whenRescuing_matchesRawBalance] |
| DM-RESCUE-N02 | Fuzz A or C | Fuzz B=1..MAX256; seed 1, MAX256 and an interior raw amount | B, equal for unrelated viewers | Success | Sweep(B) exactly equals quote and seeded balance; no decimal scaling or amount cap | Covered: [test][test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview], [test][test_givenAdmin_whenRescuing_matchesPermissionlessPreview], [test][test_givenLifecycleBoundarySeeds_whenRescuing], [test][test_givenEachAuthorityClass_whenRescuing], [test][test_givenSixDecimals_whenRescuing_matchesRawBalance], [test][test_givenNineDecimals_whenRescuing_matchesRawBalance], [test][test_givenEighteenDecimals_whenRescuing_matchesRawBalance], [test][test_givenTokenDecimalBoundarySeeds_whenRescuing_matchesRawBalance] |
| DM-RESCUE-P01 | A | Rescue T twice with no intervening receipt | B before first rescue; 0 after | First Sweep(B); second no-op | No double payout; unchanged accounting after both | Covered: [test][test_givenAlreadyRescued_whenRescuingAgain_isNoOp] |
| DM-RESCUE-P02 | A | R0 replaced by R1 before both preview and rescue | B | Success | Only current R1 receives B; R0 unchanged | Covered: [test][test_givenTreasuryUpgraded_whenRescuing_usesCurrentModule] |
| DM-RESCUE-D01 | A | TRSRY module absent; guarantee B=0 and B>0 | Policy_ModuleDoesNotExist(toKeycode("TRSRY")) | Same exact error from Kernel Policy base | Unchanged | Covered: [test][test_givenTreasuryMissing_whenPreviewAndRescue_revert], [test][test_givenTreasuryMissing_whenBalanceAtBoundaries_reverts] |
| DM-RESCUE-T01 | A | T.balanceOf(DM) reverts with a stable typed fixture error | Exact fixture error propagates | Same exact fixture error | Unchanged | Covered: [test][test_givenBalanceReadFails_whenPreviewAndRescue_revert] |
| DM-RESCUE-T02 | A | Mandatory transfer reverts with a stable typed fixture error | B; token delivery is execution-only | Exact fixture error propagates | Complete rollback, including token-side mutations and logs; no deferred payout | Covered: [test][test_givenTransferFails_whenRestored_rescueRetriesOnce] |
| DM-RESCUE-T03 | A | Transfer fails; restore token behavior and retry | B before failure and again before retry | First exact transfer error; retry succeeds | Sweep original live B once; failure creates no entitlement/accounting bucket | Covered: [test][test_givenTransferFails_whenRestored_rescueRetriesOnce] |
| DM-RESCUE-P04 | A | Quote at B=1 raw unit, donate 2 more units, quote and rescue again | 1 initially; 3 after donation | Sweep(3) | No stale-quote reservation; Treasury receives 3 exactly | Covered: [test][test_givenDonationAfterQuote_whenRescuing_usesFreshBalance] |

Use the approved SafeERC20 library for return-shape behavior. Do not duplicate every true/false/no-data
library test here or add outgoing balance-delta guards for unsupported token behavior.

## Callbacks and stateful properties

For nested borrowing, grant the callback token DEPOSIT_OPERATOR_ROLE and fund/configure a valid
operator position. For nested rescue, select the callback contract as C or grant it ADMIN so that
the call reaches the guard. Prove the same nested operation succeeds outside the outer call.

| ID | Caller | Callback / sequence | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-C01 | A | T.transfer catches an otherwise-valid nested borrowingWithdraw rejection | Pre-call quote B; transfer callbacks are execution-only | Nested ReentrancyGuardReentrantCall(); outer succeeds | Sweep(B) once; nested debt/custody/accounting unchanged | Covered: [test][test_givenRescuedTokenCallback_whenBorrowingWithdrawal] |
| DM-RESCUE-C02 | A | T.transfer catches an authorized nested rescue(T2) rejection | Pre-call quote B; does not invoke transfer callback | Nested ReentrancyGuardReentrantCall(); outer succeeds | Only T swept; T2 untouched; no nested rescue event | Covered: [test][test_givenAuthorizedRescueCallback_whenCaught_outerSucceedsOnce] |
| DM-RESCUE-C03 | A | T.transfer propagates authorized nested rescue guard rejection | Pre-call quote B; cannot predict a mandatory-transfer failure | Outer ReentrancyGuardReentrantCall() | Complete rollback; no transfer, accounting mutation or committed event | Covered: [test][test_givenAuthorizedRescueCallback_whenPropagated_outerRollsBack] |
| DM-RESCUE-P03 | Stateful handler with A, C and unauthorized actors | Arbitrary donations, direct/queued rescues, custody actions, route disables and authorized controller rotations | Every preview preserves the snapshot; under equal state an authorized execution agrees with quote/eligible errors | Only current C or ADMIN may sweep eligible tokens; execution-only errors remain separate | Managed custody always backs modeled positions; rescue never changes per-operator accounting/cap utilization or sends value outside current Treasury | Covered: [invariant][invariant_rescuePreservesProtectedAccountingAndAuthority], [invariant][invariant_receiptPrincipalAndBorrowingMatchIndependentModels] |

## Test evidence and model limits

The [rescue tests](./rescue.t.sol) compare permissionless previews against independently funded
balances and successful execution, including all four activity/enablement pairs and raw-unit bounds.
The [callback tests](./rescueCallback.t.sol) exercise the shared guard with otherwise-valid nested
operations. The [stateful campaign](./rescue.invariant.t.sol) models two operators and two assets
across idle and synchronous-vault custody, with fixed one-to-one conversion and no yield. Its
Treasury remains fixed; the separate P02 test covers a real Treasury module upgrade. Reciprocal
scenario annotations and named links below identify each row's evidence.

## Bytecode acceptance

Keep the DM change small: reuse its existing config-authority path and managed-token check, with
shared validation between preview and execution rather than a second classifier or preview state. Leave
queue storage, metadata, conflict keys, batch validation and delay calculations in DMCT. Do not
broaden the rescue API to accept a recipient or amount, or change reEnable's manager authority by
editing a helper shared with rescue.

Measure baseline and final artifacts under the unchanged `deploy` profile from
[foundry.toml](../../../../foundry.toml): solc 0.8.36, optimizer enabled, 400 runs, Prague target.
Verify the artifact's actual settings; default-profile unoptimized sizes are not deployment evidence.
Use focused builds:

```sh
FOUNDRY_PROFILE=deploy forge build --sizes src/policies/deposits/DepositManager.sol
FOUNDRY_PROFILE=deploy forge build --sizes src/policies/deposits/DepositManagerConfigTimelock.sol
```

Report DM and DMCT baseline/final deployed bytes, delta and remaining headroom. Runtime must be at
most 24,576 bytes ([EIP-170](https://eips.ethereum.org/EIPS/eip-170)); deployment initcode, including
actual constructor arguments, must be at most 49,152 bytes
([EIP-3860](https://eips.ethereum.org/EIPS/eip-3860)). A size that fits only after changing compiler
settings or raising the test code-size limit does not satisfy this plan. Seek explicit review for
any compiler-profile or contract-extraction proposal. No historical size is a current baseline.

Pinned dependencies were installed with user approval. Baseline artifacts were measured before
production changes; final measurements use the same compiler and deployment profile.

| Contract | Baseline runtime | Final runtime | Delta | EIP-170 headroom |
| --- | --- | --- | --- | --- |
| DepositManager | 24,475 | 24,552 | +77 | 24 |
| DepositManagerConfigTimelock | 18,809 | 20,015 | +1,206 | 4,561 |

| Contract | Baseline initcode | Final initcode | Delta | Constructor arguments | Final total | EIP-3860 headroom |
| --- | --- | --- | --- | --- | --- | --- |
| DepositManager | 25,067 | 25,144 | +77 | 64 | 25,208 | 23,944 |
| DepositManagerConfigTimelock | 20,575 | 21,809 | +1,234 | 64 | 21,873 | 27,279 |

All sizes are bytes. Artifact metadata confirms solc `0.8.36+commit.8a079791`, optimizer enabled
with 400 runs, and Prague. Both constructors take two statically encoded addresses. The 24-byte
DM runtime margin is tight; further production edits require a fresh deployment-profile size check.

Focused rescue tests pass: 70 DM checks and 124 DMCT checks, including the stateful rescue campaigns
with 256 runs and 128,000 handler calls each. The existing DM/DMCT regression suites also pass.
The separately approved repository-wide `pnpm run test:unit` passes 12,630 tests across 834 suites,
with zero failures or skips. Fork tests were not run. Repository lint and both reciprocal mapping
checks pass; existing out-of-scope compiler/linter warnings remain.

- [x] Inspect implementation, inherited guards, custody classification and existing rescue tests.
- [x] Specify desired authority, preview parity, explicit lifecycle fuzzing, accounting, boundaries, callbacks and size gates.
- [x] Capture failing preview and direct-manager-bypass tests before production edits; cover all four activity/enablement pairs.
- [x] Implement and map each row with reciprocal scenario IDs; preserve unchanged reEnable behavior.
- [x] Run focused rescue/queue integration and stateful invariant tests.
- [x] Record baseline/final deploy-profile sizes and verify limits without compiler-setting changes.

[invariant_receiptPrincipalAndBorrowingMatchIndependentModels]: ./rescue.invariant.t.sol#L120
[invariant_rescuePreservesProtectedAccountingAndAuthority]: ./rescue.invariant.t.sol#L109
[test_givenActivePolicyDuringCallback_whenRescueReenters_guardWins]: ./rescueCallback.t.sol#L116
[test_givenAdmin_whenRescuing_matchesPermissionlessPreview]: ./rescue.t.sol#L427
[test_givenAlreadyRescued_whenRescuingAgain_isNoOp]: ./rescue.t.sol#L1143
[test_givenAuthorityFirstLifecycleSeeds_whenRescuing_reverts]: ./rescue.t.sol#L785
[test_givenAuthorizedRescueCallback_whenCaught_outerSucceedsOnce]: ./rescueCallback.t.sol#L19
[test_givenAuthorizedRescueCallback_whenPropagated_outerRollsBack]: ./rescueCallback.t.sol#L74
[test_givenBalanceReadFails_whenPreviewAndRescue_revert]: ./rescue.t.sol#L1217
[test_givenContractDisabled_whenCallerIsDepositManagerAdmin_reverts]: ./rescue.t.sol#L177
[test_givenContractEnabled_whenCallerIsDepositManagerAdmin_reverts]: ./rescue.t.sol#L350
[test_givenControllerDisabled_whenAdminRescues]: ./rescue.t.sol#L641
[test_givenControllerInactive_whenAdminRescues]: ./rescue.t.sol#L649
[test_givenControllerViewsBroken_whenAdminRescues]: ./rescue.t.sol#L632
[test_givenDelegationCleared_whenZeroCallerRescues_reverts]: ./rescue.t.sol#L618
[test_givenDisabledEmptyExternalShareRoute_whenRescuingAnyManagedToken_reverts]: ./rescue.t.sol#L928
[test_givenDonationAfterQuote_whenRescuing_usesFreshBalance]: ./rescue.t.sol#L1277
[test_givenEachAuthorityClass_whenRescuing]: ./rescue.t.sol#L570
[test_givenEachCallbackLifecyclePair_whenRescuing_guardWins]: ./rescueCallback.t.sol#L157
[test_givenEachUnauthorizedClass_whenRescuing_reverts]: ./rescue.t.sol#L595
[test_givenEighteenDecimals_whenRescuing_matchesRawBalance]: ./rescue.t.sol#L1063
[test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst]: ./rescue.t.sol#L387
[test_givenInactiveLifecycleBoundarySeeds_whenRescuing_reverts]: ./rescue.t.sol#L496
[test_givenInactivePolicyDuringCallback_whenRescueReenters_guardWins]: ./rescueCallback.t.sol#L138
[test_givenIndebtedDisabledRouteLifecycleSeeds_whenRescuing]: ./rescue.t.sol#L562
[test_givenLifecycleBoundarySeeds_whenRescuing]: ./rescue.t.sol#L476
[test_givenManagedBalanceBoundarySeeds_whenRescuing_reverts]: ./rescue.t.sol#L880
[test_givenManagedExternalShares_whenBalanceVaries_reverts]: ./rescue.t.sol#L867
[test_givenManagedIdleUnderlying_whenBalanceVaries_reverts]: ./rescue.t.sol#L845
[test_givenManagedSurplusLifecycleSeeds_whenRescuing_reverts]: ./rescue.t.sol#L1018
[test_givenManagedTokenSurplus_whenRescuing_reverts]: ./rescue.t.sol#L982
[test_givenManagedUnderlying_whenBalanceVaries_reverts]: ./rescue.t.sol#L834
[test_givenManagedVault_whenBalanceVaries_reverts]: ./rescue.t.sol#L856
[test_givenNineDecimals_whenRescuing_matchesRawBalance]: ./rescue.t.sol#L1055
[test_givenNoController_whenAdminRescues]: ./rescue.t.sol#L627
[test_givenOperatorRotated_whenOldOperatorRescues_reverts]: ./rescue.t.sol#L609
[test_givenPolicyInactive_whenRescuing_revertsRegardlessOfEnablement]: ./rescue.t.sol#L445
[test_givenPolicyReactivated_whenRescuing]: ./rescue.t.sol#L702
[test_givenReEnabled_whenRescuing_preservesTransitionHistory]: ./rescue.t.sol#L657
[test_givenRescuedTokenCallback_whenBorrowingWithdrawal]: ./rescue.t.sol#L41
[test_givenSelectedOperatorAndPolicyInactive_whenRescuing_reverts]: ./rescue.t.sol#L514
[test_givenSelectedOperatorAndReEnabled_whenRescuing_preservesTransitionHistory]: ./rescue.t.sol#L679
[test_givenSelectedOperatorInactiveBoundarySeeds_whenRescuing_reverts]: ./rescue.t.sol#L544
[test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview]: ./rescue.t.sol#L409
[test_givenSixDecimals_whenRescuing_matchesRawBalance]: ./rescue.t.sol#L1047
[test_givenStoredExternalShareSurplus_whenRescuing_reverts]: ./rescue.t.sol#L1000
[test_givenStoredShareAndRetiredRouteBoundarySeeds_whenRescuing_reverts]: ./rescue.t.sol#L954
[test_givenTokenDecimalBoundarySeeds_whenRescuing_matchesRawBalance]: ./rescue.t.sol#L1071
[test_givenTokenIsConfiguredExternalShareToken_reverts]: ./rescue.t.sol#L310
[test_givenTransferFails_whenRestored_rescueRetriesOnce]: ./rescue.t.sol#L1240
[test_givenTreasuryMissing_whenBalanceAtBoundaries_reverts]: ./rescue.t.sol#L1209
[test_givenTreasuryMissing_whenPreviewAndRescue_revert]: ./rescue.t.sol#L1177
[test_givenTreasuryUpgraded_whenRescuing_usesCurrentModule]: ./rescue.t.sol#L1157
[test_givenUnauthorizedCaller_whenManagedToken_revertsAuthorityFirst]: ./rescue.t.sol#L748
[test_givenUnauthorizedCaller_whenTokenZero_revertsAuthorityFirst]: ./rescue.t.sol#L711
[test_givenUtilizationExceedsLoweredCap_whenRescuingUnmanagedToken_succeeds]: ./rescue.t.sol#L110
[test_givenVaultChangesReportedShare_whenRescuingStoredShare_reverts]: ./rescue.t.sol#L900
[test_givenVaultShareReadReverts_whenRescuingStoredShare_reverts]: ./rescue.t.sol#L914
[test_givenZeroAndNoCodeLifecycleSeeds_whenRescuing_reverts]: ./rescue.t.sol#L811
[test_givenZeroBalance_whenTransferWouldFail_isNoOp]: ./rescue.t.sol#L1033
[test_rescue_givenAssetWithVault_givenTokenAddressZero_reverts]: ./rescue.t.sol#L258
[test_rescue_givenAssetWithZeroVault_givenTokenAddressZero_reverts]: ./rescue.t.sol#L249
[test_rescue_givenNoManagedAssets_givenTokenAddressZero_reverts]: ./rescue.t.sol#L240
[test_rescue_givenTokenIsConfiguredAsset_givenAssetDisabled_reverts]: ./rescue.t.sol#L271
[test_rescue_givenTokenIsConfiguredAsset_reverts]: ./rescue.t.sol#L288
[test_rescue_givenTokenIsConfiguredVault_reverts]: ./rescue.t.sol#L301
[test_whenCallerIsUnauthorized_reverts]: ./rescue.t.sol#L186
[test_whenTokenHasNoCode_revertsConsistently]: ./rescue.t.sol#L800
