# DepositManagerConfigTimelock.queueBatch authorization scenarios

Scope: the shared admin-or-deposit_manager_admin authorization check, reached by queueBatch and the six typed queue functions: deposit cap, minimum deposit, share withdrawal requirement, period enablement, period disablement and period creation. Product inputs, batch boundaries and execution/cancellation retain their existing suites.

## Domains and assertions

- DMCT = DepositManagerConfigTimelock; DM = its bound DepositManager. Default: both enabled and Kernel-active; DMCT selected as DM's configOperator; configured asset and a valid one-action deposit-cap batch.
- Admin and Deposit Manager Admin are authorized caller classes, tested separately. Fuzz unauthorized callers excluding exactly those two fixture accounts; guarantee zero, emergency-only, deposit-operator-only and the previous config operator.
- Authorization rejection is IPolicyAdmin.NotAuthorised(), matching DMCT's existing combined-role reEnable check. Single-role cancellation retains ROLES_RequireRole(EMERGENCY_ROLE).
- Unchanged: nextActionId, pending action length/config guards, target deposit cap and operator unchanged; no committed events. The caller error wins over an invalid one-action payload. Batch-size validation runs before authorization; an empty batch is not an authorization test.

| ID | Caller | State / request | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-A01 | Admin; Deposit Manager Admin separately | Default; deposit-cap batch | Store exact proposer, target, selector and payload; one action ID consumed; no DM configuration change at queue | Covered: [admin][test_whenAdminQueues], [manager][test_whenDepositManagerAdminQueues] |
| DMCT-A02 | Fuzz unauthorized caller; fixed unauthorized identities | Default; valid deposit-cap batch or invalid asset | NotAuthorised(); Unchanged | Covered: [valid asset fuzz][test_whenCallerIsUnauthorized_reverts], [zero asset fuzz][test_whenCallerIsUnauthorized_whenAssetIsZero_reverts], [identities][test_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| DMCT-A03 | Fuzz unauthorized caller | Default; typed cap/share-withdrawal/period-creation queue | NotAuthorised(); input validation is not reached | Covered: [cap](./queueLimits.t.sol#L22), [withdrawal](./queueSetAssetShareWithdrawalRequired.t.sol#L27), [period][test_whenCallerIsNotAuthorized_reverts], [emergency][test_givenEmergency_whenQueueingRouteCreation_reverts] |

Lifecycle checks still precede authorization: DMCT enabled → DMCT active → DM active → caller role → selected operator → DM enabled → sub-action validation. Lifecycle behavior remains in [lifecycle](./lifecycle.t.sol) and [reEnable](./reEnable.t.sol); this error correction changes no gate or permitted role.

[test_whenAdminQueues]: ./queueBatch.t.sol#L20
[test_whenDepositManagerAdminQueues]: ./queueBatch.t.sol#L26
[test_whenCallerIsUnauthorized_reverts]: ./queueBatch.t.sol#L32
[test_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./queueBatch.t.sol#L45
[test_whenCallerIsNotAuthorized_reverts]: ./queueAddAssetPeriod.t.sol#L26
[test_givenEmergency_whenQueueingRouteCreation_reverts]: ./queueAddAssetPeriod.t.sol#L242

[test_whenCallerIsUnauthorized_whenAssetIsZero_reverts]: ./queueBatch.t.sol#L38
