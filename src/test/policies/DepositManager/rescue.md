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

Current source still accepts ADMIN or `deposit_manager_admin`, does not accept a role-free selected
operator, and has neither `previewRescue` nor `queueRescue` integration. Existing manager-success and unauthorized-caller tests
therefore need replacement expectations. The input cases below specify the existing
`DepositManager_CannotRescueAsset(token)` error for zero and no-code tokens as well as managed
tokens; current zero/no-code failures are inconsistent and sometimes have empty revert data. This
small validation requirement avoids a new error family. Contracts and executable tests are unchanged
by this planning task.

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
| DM-RESCUE-A01 | Fuzz A-only, C-only, and A=C | C nonzero; seed each authority class | B | Success | Sweep(B); Unchanged accounting | Unmapped |
| DM-RESCUE-A02 | Fuzz outside ADMIN holders and C | Include M, E, O, unrelated callers and zero | B; no viewer/caller authorization lookup | ConfigOperator_Unauthorized(caller) | Unchanged | Unmapped |
| DM-RESCUE-A03 | M | C=DMCT; M has no ADMIN grant | B | ConfigOperator_Unauthorized(M) | No direct-manager delay bypass | Unmapped |
| DM-RESCUE-A04 | Previously selected C0 | DM now selects C1; C0 lacks ADMIN | B | ConfigOperator_Unauthorized(C0) | Unchanged | Unmapped |
| DM-RESCUE-A05 | Zero caller | Delegation cleared to zero; zero lacks ADMIN | B | ConfigOperator_Unauthorized(address(0)) | Zero never becomes an authorized operator | Unmapped |
| DM-RESCUE-A06 | A | C zero, broken, disabled or Kernel-inactive; guarantee each | B without probing C | Success without probing C | Sweep(B); governance fallback independent of controller readiness | Unmapped |
| DM-RESCUE-A07 | C | Fuzz selected EOA or contract identity; no ADMIN grant | B | Success; selection is the authority | Sweep(B); no controller interface/lifecycle requirement on DM | Unmapped |

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
| DM-RESCUE-L01 | Any address, fuzz, without authorization exclusions | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DM; token=address(0) | DepositManager_PolicyInactive() before token validation | DepositManager_PolicyInactive() before rescue authority and token checks | Revert; no effects of the attempted action commit | Partial: [test][test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst]; add preview parity and explicit unchanged custody/accounting/log assertions |
| DM-RESCUE-L02 | Fuzz A or C | true | Fuzz false/true; guarantee disabled | Eligible T; fuzz B=0..MAX256 and seed 0,1,MAX256 | B from every V, including while disabled | Success while paused or enabled | Sweep(B) for B>0, otherwise no-op; enabled flag unchanged | Unmapped |
| DM-RESCUE-L03 | Fuzz A or C | false | Fuzz false/true | Eligible T; fuzz B independently | DepositManager_PolicyInactive() from every V | DepositManager_PolicyInactive() | Unchanged | Unmapped |
| DM-RESCUE-L04 | Fuzz A or C | true | true | After disable/reEnable within grace | B | Success | Sweep(B); preserve transition history | Unmapped |
| DM-RESCUE-L05 | Unauthorized caller | true | Fuzz false/true | Zero or managed token; seed each | DepositManager_CannotRescueAsset(token) | ConfigOperator_Unauthorized(caller) before token validation; caller authentication is execution-only | Unchanged | Unmapped |
| DM-RESCUE-L06 | A | Fuzz false/true | Fuzz false/true | Already inside a guarded token-moving operation; otherwise valid nested rescue | B if active, otherwise DepositManager_PolicyInactive(); no execution guard acquired by view | ReentrancyGuardReentrantCall() before lifecycle/authority/input checks | No nested effects | Unmapped |
| DM-RESCUE-L07 | A | true | Fuzz false/true | Asset cap below utilization; route disabled; outstanding borrows | B | Success for unmanaged T | Sweep(B); preserve debt, receipts and utilization | Unmapped |

## Token eligibility

Use A with DM active; local enabled is independently fuzzed and both values seeded. W denotes a
configured vault entry point; S is its onboarding-time stored share token. A managed-token balance
of zero does not weaken protection. Guarantee B=0 and B>0 in each managed-token family.

Preview is requested by V. In this table, both functions must return the exact same error selector
and arguments; token rejection precedes any token balance read or transfer.

| ID | Caller | Token / configuration | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-I01 | A | token=address(0); no configured assets, idle route, and vault route fixtures | DepositManager_CannotRescueAsset(address(0)) | Same exact error in every fixture | Unchanged; no opaque revert | Unmapped |
| DM-RESCUE-I02 | A | Nonzero no-code address, including an EOA | DepositManager_CannotRescueAsset(token) | Same exact error | Unchanged | Unmapped |
| DM-RESCUE-I03 | A | Configured underlying; idle custody or vault custody | DepositManager_CannotRescueAsset(token) | Same exact error | No managed underlying transfer | Unmapped |
| DM-RESCUE-I04 | A | Configured vault W; standard ERC-4626 or ERC-7575 entry point | DepositManager_CannotRescueAsset(W) | Same exact error | No vault-token transfer | Unmapped |
| DM-RESCUE-I05 | A | Stored external share token S distinct from underlying and W | DepositManager_CannotRescueAsset(S) | Same exact error | No share-token transfer | Unmapped |
| DM-RESCUE-I06 | A | W now reports another share token or its share getter reverts; rescue stored S | DepositManager_CannotRescueAsset(S) without querying W's live share getter | Same exact error without mutable lookup | Stored custody identity remains protected | Unmapped |
| DM-RESCUE-I07 | A | Configured asset/W/S after every associated route is disabled and liabilities reach zero | DepositManager_CannotRescueAsset(token) | Same exact error | No retirement-by-disable rescue loophole | Unmapped |
| DM-RESCUE-I08 | A | Configured asset/W/S with unsolicited balance above all recorded obligations | DepositManager_CannotRescueAsset(token) | Same exact error | This API never recovers managed-token surplus | Unmapped |

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
| DM-RESCUE-N01 | A | B=0; transfer mock would revert if called | 0 | Success, no-op | No transfer call or TokenRescued event from either call; Unchanged | Unmapped |
| DM-RESCUE-N02 | Fuzz A or C | Fuzz B=1..MAX256; seed 1, MAX256 and an interior raw amount | B, equal for unrelated viewers | Success | Sweep(B) exactly equals quote and seeded balance; no decimal scaling or amount cap | Unmapped |
| DM-RESCUE-P01 | A | Rescue T twice with no intervening receipt | B before first rescue; 0 after | First Sweep(B); second no-op | No double payout; unchanged accounting after both | Unmapped |
| DM-RESCUE-P02 | A | R0 replaced by R1 before both preview and rescue | B | Success | Only current R1 receives B; R0 unchanged | Unmapped |
| DM-RESCUE-D01 | A | TRSRY module absent; guarantee B=0 and B>0 | Policy_ModuleDoesNotExist(toKeycode("TRSRY")) | Same exact error from Kernel Policy base | Unchanged | Unmapped |
| DM-RESCUE-T01 | A | T.balanceOf(DM) reverts with a stable typed fixture error | Exact fixture error propagates | Same exact fixture error | Unchanged | Unmapped |
| DM-RESCUE-T02 | A | Mandatory transfer reverts with a stable typed fixture error | B; token delivery is execution-only | Exact fixture error propagates | Complete rollback, including token-side mutations and logs; no deferred payout | Unmapped |
| DM-RESCUE-T03 | A | Transfer fails; restore token behavior and retry | B before failure and again before retry | First exact transfer error; retry succeeds | Sweep original live B once; failure creates no entitlement/accounting bucket | Unmapped |
| DM-RESCUE-P04 | A | Quote at B=1 raw unit, donate 2 more units, quote and rescue again | 1 initially; 3 after donation | Sweep(3) | No stale-quote reservation; Treasury receives 3 exactly | Unmapped |

Use the approved SafeERC20 library for return-shape behavior. Do not duplicate every true/false/no-data
library test here or add outgoing balance-delta guards for unsupported token behavior.

## Callbacks and stateful properties

For nested borrowing, grant the callback token DEPOSIT_OPERATOR_ROLE and fund/configure a valid
operator position. For nested rescue, select the callback contract as C or grant it ADMIN so that
the call reaches the guard. Prove the same nested operation succeeds outside the outer call.

| ID | Caller | Callback / sequence | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-C01 | A | T.transfer catches an otherwise-valid nested borrowingWithdraw rejection | Pre-call quote B; transfer callbacks are execution-only | Nested ReentrancyGuardReentrantCall(); outer succeeds | Sweep(B) once; nested debt/custody/accounting unchanged | Unmapped |
| DM-RESCUE-C02 | A | T.transfer catches an authorized nested rescue(T2) rejection | Pre-call quote B; does not invoke transfer callback | Nested ReentrancyGuardReentrantCall(); outer succeeds | Only T swept; T2 untouched; no nested rescue event | Unmapped |
| DM-RESCUE-C03 | A | T.transfer propagates authorized nested rescue guard rejection | Pre-call quote B; cannot predict a mandatory-transfer failure | Outer ReentrancyGuardReentrantCall() | Complete rollback; no transfer, accounting mutation or committed event | Unmapped |
| DM-RESCUE-P03 | Stateful handler with A, C and unauthorized actors | Arbitrary donations, direct/queued rescues, custody actions, route disables and authorized controller rotations | Every preview preserves the snapshot; under equal state an authorized execution agrees with quote/eligible errors | Only current C or ADMIN may sweep eligible tokens; execution-only errors remain separate | Managed custody always backs modeled positions; rescue never changes per-operator accounting/cap utilization or sends value outside current Treasury | Unmapped |

## Existing test evidence and mapping work

The existing [rescue test file](./rescue.t.sol) has useful starting evidence: direct ADMIN success
while enabled/disabled (lines 134 and 302), managed-token rejection (lines 206, 229, 248 and 263),
zero-balance handling (line 288), cap-utilization preservation (line 97), and a funded borrowing
callback (line 34). Those are candidates for expanded assertions and reciprocal mappings, not proof
of every new row/domain above. The preserved DM-RESCUE-L01 mapping is Partial because it checks
the exact revert but lacks the explicitly required state/log assertions.

Do not retain manager-success expectations at lines 141 and 313. The unauthorized fuzz at line 147
must exclude every ADMIN holder and the selected operator, include manager-only callers, and match
the target authorization error. Preserve the representative callback fixture and its otherwise-valid
nested-operation proof. Add reciprocal `// Scenarios:` IDs when implementing/mapping the new rows.

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

At planning time this worktree has no Solidity dependencies or build artifacts, so a fresh baseline
is unavailable. The earlier dependency-install approval question remains unanswered. No size-pass
claim is made by these documents.

- [x] Inspect implementation, inherited guards, custody classification and existing rescue tests.
- [x] Specify desired authority, preview parity, explicit lifecycle fuzzing, accounting, boundaries, callbacks and size gates.
- [ ] Add failing tests for preview/execution parity and all four independently seeded activity/enablement pairs before changing production.
- [ ] Implement and map each row with reciprocal scenario IDs; preserve unchanged reEnable behavior.
- [ ] Run focused rescue/queue integration and stateful invariant tests.
- [ ] Record baseline/final deploy-profile sizes and verify limits without compiler-setting changes.

[test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst]: ./rescue.t.sol#L340
