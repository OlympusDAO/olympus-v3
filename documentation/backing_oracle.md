# Backing oracle

`BackingOracle` stores the canonical reserve value per OHM in 18 decimals.
`BackingOracleConfigTimelock` is a separate Policy that proposes delayed changes
and applies them through the oracle's selected config operator. Backing storage
and its validation remain on the oracle when the timelock is replaced.

BurnerLoansRisk interprets backing as USD reserve value per OHM. Configure the
oracle in those units before relying on Risk pricing; the oracle itself does not
convert currencies or derive reserve values.

## Authority

| Operation | Authority | Activity and enablement |
| --- | --- | --- |
| Enable oracle with initial backing | ADMIN | Oracle active and disabled |
| Set backing directly | ADMIN or current nonzero config operator | Oracle active and enabled |
| Validate a proposed backing value | Anyone | Oracle active and enabled |
| Select, rotate or revoke config operator | ADMIN | Oracle active; may be paused |
| Queue backing update | backing_admin or ADMIN | Both policies active/enabled; queue selected |
| Execute queued update | Anyone | Both policies active/enabled; queue selected |
| Cancel queued update | Until the update expires: ADMIN, EMERGENCY or its proposer. After expiry: anyone | Queue active; may be paused; no oracle reads |
| Enable queue | ADMIN | Queue active/disabled; compatible same-Kernel active oracle and selected queue; oracle may be paused |
| Re-enable either policy | ADMIN or backing_admin | Previously initialized, own policy active/disabled, within grace; queue revalidates target identity/activity/selection |
| Set re-enable grace | ADMIN | Own policy active and enabled; nonzero period |
| Disable either policy | ADMIN or EMERGENCY | Currently enabled; own Kernel inactivity does not block pause |

ADMIN is intended to be the OCG timelock. The operational multisig holds
`backing_admin` for queue proposals and bounded recovery of the oracle and queue;
an independent emergency multisig holds EMERGENCY. This role alone does not allow
direct `setBacking`, operator rotation or initial enablement. Assign the config
operator to a timelock that enforces the intended notice period: selecting a plain
account delegates immediate bounded write authority to that account.

Both policies depend only on ROLES major version one and request no module-write
permissions. Kernel membership and local enablement are independent. Oracle reads,
interface queries and framework hooks retain their read/framework semantics.
The oracle getter remains readable while paused or inactive. BurnerLoansRisk
requires a same-Kernel, active and enabled oracle at enable/reEnable and whenever
it consumes backing, including supplied snapshots. Binding requires IBackingOracle
and IEnabler, without an IVersioned requirement. A ready oracle getter can still
revert independently; Risk propagates that failure when acquiring a snapshot.

## Updates and numeric rules

Oracle enable accepts exactly one ABI-encoded nonzero uint256. Timelock enable
and both policies' disable functions accept empty data.
ADMIN can disable and enable again with a fresh initial value; this is an explicit
administrative reset outside the per-update bounds. Both policies expose parameterless `reEnable` with a default seven-day grace window
measured from the last disable transition. ADMIN or backing_admin may recover a
previously initialized, active policy while it is disabled and within the inclusive
grace deadline. Recovery preserves backing, operator selection, queued payloads,
reservations and original execution deadlines. It never initializes fresh backing.
ADMIN can configure a nonzero uint32 grace period while the policy is active and
enabled; configuration preserves transition timestamps and emits GracePeriodSet
even when the value is unchanged. Deadline overflow uses the canonical SafeCast error.

For current backing B, an update must be nonzero and lie in the inclusive interval
`[floor(B * 9_000 / 10_000), floor(B * 11_000 / 10_000)]`. The fixed change limit is
1,000 basis points (10%) on the repository's 10,000-point scale. The values and bounds have 18 decimals.
The oracle's permissionless `validateSetBacking` uses the same lifecycle and numeric
checks as a successful authorized `setBacking`. Execution checks the bounds again.

Both bounds round down, preserving the source's tiny-value behavior: 19 → 17 is
permitted, a decrease greater than 10%. Full-precision `Math.mulDiv` avoids intermediate
multiplication overflow when applying the basis-point scale. If the calculated 110%
upper bound itself exceeds uint256, updates still panic; initializing to MAX256 is
one such case. ADMIN can recover through disable/enable. Integrations should use
realistic 18-decimal USD reserve values. Repeated valid updates may compound;
there is no aggregate rate cap.

## Timelock and pending intent

The notice period is fixed at one day and has no public setter. Each queued action
stores its own deadlines. A different notice policy requires a replacement timelock
implementation selected through ADMIN-controlled operator rotation.
Execution is permitted throughout the inclusive interval from `executableAt` to
`executableAt + 7 days`. Before that interval the action is not ready; after it the
action is expired. An expired action retains its reservation until cancellation.

Until an action expires, ADMIN, EMERGENCY and the action's proposer can cancel it.
The proposer is matched by address: the account that queued the action can cancel
it after losing `backing_admin`, and another `backing_admin` holder cannot. Once
the action is expired, anyone can cancel it, so public cancellation never overlaps
the execution interval. Every cancellation requires the queue to be active in its
Kernel; the queue may be paused, and the oracle is not read.

The queue uses the shared `ConfigTimelockBatchQueue`. The typed `queueSetBacking`
helper creates one action for the immutable oracle's `setBacking(uint256)` selector
and its ABI-encoded uint256 parameter. No public arbitrary-target or batch entry
point is exposed.

There is one backing configuration domain:

- Local key: `keccak256(abi.encode(IBackingOracle.setBacking.selector))`.
- Scoped key: `keccak256(abi.encode(oracleAddress, localKey))`.
- Expected state: `keccak256(abi.encode(configOperator, backing))`.

Only one unresolved backing proposal can reserve this key in each queue. The
proposal checks current backing bounds before acquiring it. Execution verifies
current lifecycle, selected operator, recorded destination and committed pre-state
before dispatch. The oracle then enforces live authority and numeric bounds.
Failure reverts the entire execution, preserving the action, payload and key.
Success or cancellation releases the key.

| Change during notice | Result |
| --- | --- |
| ADMIN changes backing | State commitment mismatch; pending intent retained |
| ADMIN replaces/revokes operator | Old queue cannot execute; ADMIN, EMERGENCY or the proposer can still cancel |
| Oracle or queue paused/inactive | Ordinary execution blocked; restore readiness within original window to retry |
| Backing/operator changes away and back | Current-state commitment may match again; no historical epoch invalidation |
| Action expires | Execution rejected; anyone can cancel, which releases the reservation |

Reservations are local to each queue instance. Replacing the selected operator is
the authority boundary between old and new queues; an old reservation cannot block
fresh proposals on the replacement queue.

## Deployment and replacement

1. Deploy the oracle against its Kernel; install ROLES and activate the oracle.
2. Deploy the timelock with the same Kernel and the oracle's immutable address.
3. ADMIN selects the timelock with `oracle.setConfigOperator(timelock)`.
4. Activate and enable the timelock. The oracle may still be paused at this step.
5. ADMIN enables the oracle with the initial backing. Assign proposer and emergency roles.

Construction checks the oracle's IBackingOracle, IConfigOperator and IEnabler
interfaces and canonical same-Kernel binding. It does not query target activity,
enablement or selected operator. Queue enable and reEnable recheck own activity and target compatibility, same-Kernel
binding, target membership and operator selection without reading target enablement.
This permits repairing the queue while the oracle is active but paused. Queueing
and execution still require the oracle to be active and enabled, so activating the
queue alone cannot reopen an unavailable configuration service.

To replace a queue, deploy and activate a replacement for the same oracle, then
ADMIN selects it and enables it. Rotation is immediate and is available while the
oracle is paused. Zero revokes delegation. Re-selecting the current address reverts
after authorization. Selection does not query the candidate queue's readiness.
ADMIN, EMERGENCY or the proposer can cancel old pending intents, and anyone can
cancel them once expired, while the old queue is active; its local pause or broken
target metadata does not prevent cancellation. No backing is moved or copied
during replacement.

## Interfaces and origin

The oracle advertises IBackingOracle, IConfigOperator, IVersioned and its inherited
Enabler/re-enable/grace/ERC165 interfaces. BurnerLoansRisk uses IBackingOracle for
interface admission and reads of the same 18-decimal backing value. Queue interfaces are advertised by the
separate timelock, which exposes the shared batch/config queue query API.

The backing-value implementation originated on `origin/feat/multi-asset-yrf` in
commit `2121e66b333eab9971a8026b9a71f6ced1d7ed68`; the source snapshot is
`fffb18b5e67c0591d86386a27e69278e89cceb1f`. The separate queue, replaceable operator,
Kernel lifecycle admission, Risk's use of IBackingOracle and full-precision
basis-point bounds are integration changes. Scenario documents and tests are under `src/test/policies/BackingOracle/`
and `src/test/policies/BackingOracleConfigTimelock/`.
