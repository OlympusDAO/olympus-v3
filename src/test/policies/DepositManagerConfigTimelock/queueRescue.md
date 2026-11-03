# DepositManagerConfigTimelock.queueRescue coverage plan

Sources: [DMCT](../../../policies/deposits/DepositManagerConfigTimelock.sol),
[configuration queue](../../../policies/utils/ConfigTimelockBatchQueue.sol),
[queue lifecycle](../../../policies/utils/TimelockBatchQueue.sol), and
[DepositManager rescue acceptance](../DepositManager/rescue.md).
Closest precedent: [Inventory's Treasury-only delayed rescue](../BurnerLoansInventoryConfigTimelock/queueRescueSurplus.md).

## Acceptance criteria and current implementation

The proposed API is `queueRescue(address token) returns (uint64 actionId)`. ADMIN or
DEPOSIT_MANAGER_ADMIN_ROLE holders may propose. DMCT must be DepositManager's selected config
operator. Anyone may execute a valid pending action after its delay and through the inclusive
expiry boundary. DM receives DMCT as msg.sender and independently authorizes the selected operator;
the external proposer's roles are not forwarded to DM.

DMCT must remain Kernel-active and locally enabled. DM must remain active in the same Kernel;
its local disabled state must not block rescue queueing or execution. Other configuration actions
keep their existing DM-enabled requirement. Rescue supports only unmanaged ERC-20 tokens and sends
their entire execution-time balance to the then-current TRSRY. There is no recipient/amount input,
token reservation, allowance grant or transfer at queue time.
Queue admission calls DM.previewRescue(T) for canonical token/balance/Treasury validation. DMCT has
no rescue role merely to obtain this quote. A zero quote is valid; the quoted amount is neither
stored as a payout amount nor hashed into the configuration commitment.

Current source has no queueRescue API/selector dispatch, and its shared queue/execution hooks require
DM enabled. DM also has the old direct-manager rescue authority. This is a desired-state plan;
all rows are Unmapped until the new API and its tests exist. Existing generic execute/cancel tests
are reference evidence, not a mapped proof of this new selector.

## Domains, fixtures and errors

- TL is DMCT; DM is its immutable manager; T and U are distinct eligible ERC-20 tokens. A holds
  ADMIN_ROLE; M holds DEPOSIT_MANAGER_ADMIN_ROLE. Fuzz proposer identities with ADMIN-only,
  manager-only and overlapping grants, guaranteeing each. TL itself has neither role on DM.
- Unauthorized proposers exclude every holder of either accepted role; seed EMERGENCY-only,
  DEPOSIT_OPERATOR-only, unrelated addresses and zero. Permissionless executor fuzzing has no role
  exclusions; include the proposer and unrelated EOAs/contracts as seeds.
- Unless varied, both policies are active/enabled in Kernel K, DM selects TL, ROLES is initialized,
  T is unmanaged, its balance read is canonical, and no T rescue is pending.
- `MAXn=2**n-1`. Token amounts B use raw units and fuzz 0..MAX256, guaranteeing 0, 1 and MAX256.
  Use zero Treasury token balance for the MAX256 fixture. Queue time Q is a positive uint48 second.
  Delay D is the stored `timelockDelay`, fuzzed across 1 day..30 days with both bounds seeded.
  X=Q+D; Y=X+3 days. Derive execution assertions from stored X/Y, not fixture clock assumptions.
- Unchanged means nextActionId, existing action metadata/payloads, configuration guards/key owners,
  token balances/allowances, DM custody/accounting/receipts/cap utilization, configuration and
  lifecycle fields stay equal. Reverts commit no logs. Failed execution retains the complete
  pending action and every reserved key; terminal success/cancellation clears payload/guards/keys
  while retaining proposer/timestamps and the appropriate terminal flag.

Use exact errors from [queue](../../../policies/interfaces/utils/ITimelockBatchQueue.sol),
[configuration queue](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol),
[DMCT](../../../policies/interfaces/deposits/IDepositManagerConfigTimelock.sol),
[controller](../../../policies/interfaces/utils/IConfigOperator.sol), and
[DM rescue](../../../policies/interfaces/deposits/IDepositManager.sol).
Below `Action*` means `ITimelockBatchQueue_Action*`; `Config*` means
`IConfigTimelockBatchQueue_Config*`. `NotAuthorised()` is the inherited proposer error;
`NotEnabled()` is inherited from IEnabler. Token eligibility uses
`DepositManager_CannotRescueAsset(token)` as specified in the rescue plan. No new production error
family is required. DM.previewRescue is required by the paired rescue plan and shares its checks
with DM.rescue; DMCT must not duplicate DM's managed-token eligibility algorithm for admission.

Queue admission precedence: TL own activity, TL local enablement, proposer authority, DM Kernel
binding/activity, selected-operator identity, action-specific validation, then conflict reservation.
Rescue omits only DM local enablement. Preserve inherited checked counter/time arithmetic and the
generic execute/cancel state/window checks before their product hooks. Do not infer a universal
first error from a fixture containing an exhausted counter as well as invalid input.

## Authorization and lifecycle

Typed queue only; T eligible; free key. Guarantee every boolean pair named in a row independently.

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Other condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-A01 | Fuzz ADMIN-only, manager-only and overlap | true | true | true | Fuzz false/true | TL selected; TL has no DM roles | Return next ID | Queue one rescue; no transfer; target enablement unchanged | Unmapped |
| DMCT-RESCUE-A02 | Fuzz outside ADMIN/manager holder sets | true | true | true | Fuzz false/true | TL selected | NotAuthorised() | Unchanged | Unmapped |
| DMCT-RESCUE-A03 | A | true | true | true | Fuzz false/true | DM selects another nonzero C | ConfigOperator_Unauthorized(TL) | Unchanged even though proposer is ADMIN | Unmapped |
| DMCT-RESCUE-A04 | M | true | true | true | Fuzz false/true | DM config operator cleared to zero | ConfigOperator_Unauthorized(TL) | Unchanged | Unmapped |
| DMCT-RESCUE-A05 | M | true | true | true | false | Attempt direct DM.rescue instead of proposing | ConfigOperator_Unauthorized(M) | No manager bypass; DMCT proposal still succeeds | Unmapped |
| DMCT-RESCUE-L01 | A | false | false | true | true | Unauthorized proposer and zero-token competing faults | DepositManagerConfigTimelock_PolicyInactive(TL) | Unchanged; own inactivity wins | Unmapped |
| DMCT-RESCUE-L02 | A | false | true | true | true | Otherwise admissible | DepositManagerConfigTimelock_PolicyInactive(TL) | Unchanged | Unmapped |
| DMCT-RESCUE-L03 | Unauthorized proposer | true | false | true | true | Zero-token competing fault | NotEnabled() | Unchanged; local pause wins over authority/input | Unmapped |
| DMCT-RESCUE-L04 | A | true | true | false | Fuzz false/true | Same Kernel | PolicyDependency_NotActive(DM) | Unchanged | Unmapped |
| DMCT-RESCUE-L05 | A | true | true | true | false | Otherwise admissible | Return next ID | DM stays disabled; queue creates no user accounting | Unmapped |
| DMCT-RESCUE-L06 | A | true | true | true | true | TL disabled then reEnabled within grace | Return next ID | Exactly one new action/key; history unchanged | Unmapped |
| DMCT-RESCUE-L07 | Unauthorized proposer | true | true | false | true | DM inactive plus zero token | NotAuthorised() before target/input checks | Unchanged | Unmapped |

## Dependency binding and token admission

Use A and an otherwise operational TL. T is independent of any token returned dynamically by a
vault after onboarding. DM's stored custody-token identity is authoritative.

| ID | Caller | Binding / token condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-D01 | A | DM reports K2 different from expected K; DM locally disabled too | PolicyDependency_KernelMismatch(DM,K,K2) | Unchanged; pause does not mask mismatch | Unmapped |
| DMCT-RESCUE-D02 | A | Required DM.kernel read fails or is malformed | PolicyDependency_InvalidDependency(DM) | Unchanged | Unmapped |
| DMCT-RESCUE-I01 | A | token=address(0), with no assets, idle asset and vault asset fixtures | DepositManager_CannotRescueAsset(address(0)) | No action/key/ID committed | Unmapped |
| DMCT-RESCUE-I02 | A | Nonzero no-code token address | DepositManager_CannotRescueAsset(token) | Unchanged | Unmapped |
| DMCT-RESCUE-I03 | A | Configured underlying token; seed idle/vault custody | DepositManager_CannotRescueAsset(token) | Unchanged | Unmapped |
| DMCT-RESCUE-I04 | A | Configured vault entry point | DepositManager_CannotRescueAsset(token) | Unchanged | Unmapped |
| DMCT-RESCUE-I05 | A | Stored share token, including one from a vault whose live share() changed/reverts | DepositManager_CannotRescueAsset(token) | Unchanged; no reliance on mutable share metadata | Unmapped |
| DMCT-RESCUE-I06 | A | Managed underlying/vault/share after routes disabled or liabilities zero | DepositManager_CannotRescueAsset(token) | No queue-time managed-token escape | Unmapped |
| DMCT-RESCUE-P01 | A | Eligible T, fuzz B=0..MAX256; seed 0,1,MAX256 | DM.previewRescue(T)=B; return next ID | No transfer, transferFrom, approve or token reservation; quote not fixed into later payout | Unmapped |
| DMCT-RESCUE-T03 | A | DM.previewRescue(T) encounters a stable typed token balance-read error | Same exact fixture error propagates from preview through queue admission | No action/key/ID or custody mutation | Unmapped |
| DMCT-RESCUE-D06 | A | DM.previewRescue(T) encounters missing TRSRY; seed B=0 and B>0 | Policy_ModuleDoesNotExist(toKeycode("TRSRY")), matching direct preview and authorized rescue | No action/key/ID or custody mutation | Unmapped |

## Stored operation, keys and batch equivalence

A successful typed proposal stores one sub-action `(DM,bytes4(keccak256("rescue(address)")),abi.encode(T))`
with exactly 32 payload bytes and destination DM. It consumes one uint64 ID and returns that ID.
Getters must agree on proposer, Q, X, Y, false terminal flags, sub-action count/selector/payload,
destination, expected state and scoped pending-key owner.

Require one conflict domain per `(DM,T,rescue)` shared by typed and generic-batch proposals. The exact
domain constant is an implementation detail; tests independently derive the selected encoding and
check observable key ownership. Unrelated T/U keys and existing cap/minimum/mode/period domains must
remain independent. Commit token rescue eligibility, not token balance, Treasury identity, proposer
role membership or DM local enablement. New receipts and Treasury upgrades must not stale recovery.
If T becomes any configured underlying/vault/stored share token, the rescue must stop before transfer.
Use ConfigStateChanged with the exact stored/current hashes for that eligibility drift.

Queue event order is ConfigStateQueued, TimelockSubActionQueued, TimelockActionQueued. Assert TL as
emitter and every indexed/non-indexed field: action ID, sub-action/state index, scoped key,
destination, expected hash, target, selector, payload hash, batch hash, proposer, X and Y.
Queue admission obtains the live balance through DM.previewRescue, but neither commits that balance
nor treats zero as an error. Preview failures must not leave a reserved key.

| ID | Caller | Proposal / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-P02 | Fuzz A or M | Typed proposal; free T key | Return n | nextActionId=n+1; exact one-action metadata/getters/events above; no custody changes | Unmapped |
| DMCT-RESCUE-P03 | Fuzz A or M | Equivalent singleton queueBatch rescue | Same admission and commitment as typed queue, including paused DM | Same metadata except transaction-specific ID/time; no bypass | Unmapped |
| DMCT-RESCUE-P04 | A | T rescue already pending; typed or batch duplicate | ConfigKeyPending(scopedTKey,owner) | Original action unchanged; no consumed new ID | Unmapped |
| DMCT-RESCUE-P05 | M | T rescue pending; propose U rescue | Success | Independent U action/key; T action/key unchanged | Unmapped |
| DMCT-RESCUE-P06 | A | T rescue pending; queue cap/minimum/mode/period action with its prerequisites satisfied | Success | Existing configuration domains remain independent | Unmapped |
| DMCT-RESCUE-I07 | A | Batch rescue has non-DM target | ActionInvalid(target,rescueSelector) | Entire batch unchanged | Unmapped |
| DMCT-RESCUE-I08 | A | Batch rescue payload length fuzzed outside 32; seed 0,1,31,33 and a longer bounded payload | ActionInvalid(DM,rescueSelector) | No partial metadata/key reservations | Unmapped |
| DMCT-RESCUE-I09 | A | 32-byte payload word exceeds MAX160; seed MAX160+1,MAX256 | ActionInvalid(DM,rescueSelector) | No address truncation or ABI panic | Unmapped |
| DMCT-RESCUE-I10 | A | Batch contains unsupported selector | ActionInvalid(DM,unsupportedSelector) | Entire batch unchanged | Unmapped |
| DMCT-RESCUE-L08 | A | DM paused; rescue-only batch with 1..15 distinct eligible tokens; seed 1 and 15 | Success | One key per token; no transfer | Unmapped |
| DMCT-RESCUE-L09 | A | DM paused; mixed rescue/configuration batch, both orders | NotEnabled() for the enabled-only configuration action | Entire batch rolls back, including earlier rescue reservations | Unmapped |
| DMCT-RESCUE-P07 | A | DM enabled; mixed nonconflicting rescue/configuration batch | Success | Existing configuration validation retained; rescue schedules no immediate transfer | Unmapped |

Inherited empty/oversized-batch checks remain owned by [queueBatch](./queueBatch.md). The integration
rows above establish the new rescue selector's effect on batches without duplicating that whole plan.

## Numeric and notice-window boundaries

No public amount parameter exists. Counter exhaustion and timestamps use explicit storage/clock
fixtures. Except the exhausted-counter row, reserve a valid available ID and free T key.

| ID | Caller | Boundary / guaranteed seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-N01 | A | nextActionId=MAX64-1 | Return MAX64-1; nextActionId=MAX64 | One valid pending action; no narrowing | Unmapped |
| DMCT-RESCUE-N02 | A | nextActionId=MAX64 | Panic(0x11) at checked increment | No action/key/ID mutation | Unmapped |
| DMCT-RESCUE-N03 | A | D fuzz 1day..30days, Q=MAX48-D-3days; seed both D bounds | Success; Y=MAX48 | Exact uint48 metadata, no truncation | Unmapped |
| DMCT-RESCUE-N04 | A | Q=MAX48-D-3days+1 | Panic(0x11) at expiry addition | Complete queue rollback | Unmapped |
| DMCT-RESCUE-N05 | A | Q=MAX48-D+1 | Panic(0x11) at executableAt addition | Complete queue rollback | Unmapped |
| DMCT-RESCUE-N06 | Fuzz any executor | Valid pending rescue; now fuzz Q..X-1, seed Q and X-1 | ActionNotReady(id,X) | Pending operation/key/custody unchanged | Unmapped |
| DMCT-RESCUE-N07 | Fuzz any executor | Valid pending rescue; now fuzz X..Y, seed X,X+1,Y-1,Y | Success | Full live balance swept once; terminal metadata/key cleanup | Unmapped |
| DMCT-RESCUE-N08 | Fuzz any executor | Valid pending rescue; now fuzz Y+1..MAX48 where nonempty; seed Y+1,MAX48 | ActionExpired(id,Y) | No transfer; expired action/key retained until cancellation | Unmapped |

## Rescue execution after queueing

These are action-specific integrations through `executeQueuedAction(id)`; they do not replace the
generic [executeQueuedAction](./executeQueuedAction.md) plan. Use a mature, unexpired pending rescue
and an unrelated executor unless varied. The executor receives no DM authority; TL is the DM caller.

| ID | Caller | Intervening transition / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-P08 | Fuzz any executor | Preview=1 at queue; another 2 raw units arrive; fresh preview=3 before execution | Success | Treasury +3, DM T=0; exact TokenRescued(T,3) matches fresh quote, sub-action and execution events | Unmapped |
| DMCT-RESCUE-P09 | Fuzz any executor | Queue at B=0, then positive receipt arrives | Success | Sweep full live B once | Unmapped |
| DMCT-RESCUE-P10 | Fuzz any executor | Direct ADMIN rescues first; no new receipt | Successful zero-balance execution | No DM transfer/event; TL still executes, clears action/key and emits terminal queue events | Unmapped |
| DMCT-RESCUE-P11 | Fuzz any executor | Treasury R0 upgraded to R1 | Success | Only R1 gets live balance; no stale-Treasury payment | Unmapped |
| DMCT-RESCUE-L10 | Fuzz any executor | DM locally disabled after queue; also queue while disabled and keep it disabled | Success in both histories | DM remains disabled; no receipt/debt/custody-accounting change | Unmapped |
| DMCT-RESCUE-L11 | Fuzz any executor | TL disabled after queue | NotEnabled() | Action/key retained; reEnable within grace permits retry before expiry | Unmapped |
| DMCT-RESCUE-L12 | Fuzz any executor | TL Kernel-inactive; local enabled fuzz false/true | DepositManagerConfigTimelock_PolicyInactive(TL) | Action/key retained; reactivation allows unexpired retry | Unmapped |
| DMCT-RESCUE-L13 | Fuzz any executor | DM Kernel-inactive; local enabled fuzz false/true | PolicyDependency_NotActive(DM) | No transfer; pending action survives; reactivation allows retry | Unmapped |
| DMCT-RESCUE-D03 | Fuzz any executor | DM reports foreign Kernel K2 after queue | PolicyDependency_KernelMismatch(DM,K,K2) | Pending operation/key retained | Unmapped |
| DMCT-RESCUE-D04 | Fuzz any executor | Selected operator rotated to C or zero | ConfigOperator_Unauthorized(TL) | No TL dispatch; restoration to TL allows unexpired retry | Unmapped |
| DMCT-RESCUE-A06 | Unrelated executor | Original M loses proposer role after valid queue | Success | Existing proposal remains executable; role revocation alone does not erase notice | Unmapped |
| DMCT-RESCUE-D05 | Fuzz any executor | T onboarded as underlying, vault or stored share token after queue; seed all three | ConfigStateChanged(id,0,key,expectedHash,currentHash) | No token transfer; complete pending action/key retained | Unmapped |
| DMCT-RESCUE-T01 | Fuzz any executor | Token balance/transfer reverts with exact typed fixture error | Exact error propagates through DM/DMCT | Token/state/log rollback; action not executed; keys retained | Unmapped |
| DMCT-RESCUE-T02 | Fuzz any executor | Restore failed transfer and retry before expiry | Success | Live balance swept exactly once; key released | Unmapped |
| DMCT-RESCUE-C01 | Fuzz any executor | Token callback attempts same action execution | ActionAlreadyExecuted(id) in nested call; caught by token | Outer success exactly once; no duplicate sweep/events | Unmapped |
| DMCT-RESCUE-C02 | Fuzz any executor | Token callback executes distinct mature U rescue; token propagates nested failure | DM ReentrancyGuardReentrantCall() | Both action executed flags/keys and both token balances roll back | Unmapped |

For C02 ensure the distinct queued action's admission/window/key checks all pass so that its call
reaches DM's shared guard; otherwise the test would prove the wrong boundary. Mandatory-transfer
and callback behavior belongs to [rescue](../DepositManager/rescue.md); these rows additionally prove
queue rollback. Do not create a second token-library return-shape matrix here.

## Cancellation, independence and stateful properties

Existing cancellation requires TL active and the EMERGENCY role, permits TL local disablement and
does not inspect DM readiness or selected operator. ADMIN-only and M-only do not acquire cancellation
authority. Use [cancelQueuedAction](./cancelQueuedAction.md) for shared state/error precedence.

| ID | Caller | Operation / transition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-P12 | Fuzz EMERGENCY holder | Cancel pending rescue before maturity, during window, and after expiry; seed each; TL enabled/disabled | Success | No transfer; cancellation metadata retained; T key/guards/payload released | Unmapped |
| DMCT-RESCUE-P13 | EMERGENCY holder | DM inactive/paused or controller rotated; TL active | Cancellation succeeds | Broken target/controller cannot trap rescue key | Unmapped |
| DMCT-RESCUE-A07 | Fuzz outside EMERGENCY holders | Cancel pending rescue; seed ADMIN-only and M-only | ROLES_RequireRole(EMERGENCY_ROLE) | Pending operation/key unchanged | Unmapped |
| DMCT-RESCUE-P14 | Fuzz A or M | T rescue executed or cancelled, then propose T again | Return new ID | Old terminal metadata remains; new notice/key reservation | Unmapped |
| DMCT-RESCUE-I11 | Fuzz any executor | Re-execute executed or cancelled rescue; seed each | ActionAlreadyExecuted(id) or ActionCancelled(id), respectively | No second transfer/key mutation | Unmapped |
| DMCT-RESCUE-P15 | Fuzz any executor | Older T rescue expired/stale; unrelated mature U rescue valid | U executes | No global queue-order blockage; T key/action untouched | Unmapped |
| DMCT-RESCUE-P16 | Stateful authorized/unauthorized handlers | Arbitrary queue/donate/rescue/cancel/execute, pauses, asset onboarding and controller changes | Every successful delegated transfer follows an unexpired mature action; ADMIN direct recovery is an explicit exception | Pending keys have one owner and release only on terminal success/cancel; managed custody/accounting conserved; Treasury-only payouts; no manager bypass or double execution | Unmapped |

## Implementation and size gates

Use the existing queue machinery; no second scheduler or recovery-controller system. Keep
metadata, conflict commitments and paused-rescue discrimination in TL. Use DM.previewRescue for
canonical admission and share DM's validation with rescue execution. The manager remains the final
authority for token eligibility and current Treasury at transfer time. Reuse its existing
config-authority predicate without changing manager-only bounded reEnable authority.

The [rescue plan's bytecode gate](../DepositManager/rescue.md#bytecode-acceptance) applies to DM and TL:
measure baseline/final deployment-profile runtime and initcode, record deltas/headroom, and keep
compiler settings unchanged. No fresh bytecode result is available in this dependency-free worktree.

- [x] Verify current queue lifecycle, exact errors, Inventory precedent and DM recovery boundaries.
- [x] Specify authority, paused recovery, canonical preview admission, keys, notice bounds, drift and rollback.
- [ ] Add failing typed-queue, batch-equivalence and direct-manager-bypass tests before implementation.
- [ ] Implement the agreed API and selector-specific guards; preserve ordinary configuration gates.
- [ ] Implement stateful conservation/queue-ownership coverage and reciprocal scenario mappings.
- [ ] Run focused tests, Markdown/mapping checks, and baseline/final deploy-profile size validation.
