# BurnerLoansPayout.setSendYieldToDistributor coverage plan

Source: [setSendYieldToDistributor](../../../policies/burnerloans/BurnerLoansPayout.sol#L243). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Normalized scenario scope: `BLCU-YIELD` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Implemented same-value rule: authorize and validate requested true, then return without writes/events when unchanged. Changing-value rows exclude the current value. Requested true still validates the selected distributor; requested false skips that validation.

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

Stored nonzero configOperator or ADMIN, without reverse controller lifecycle/interface/Kernel checks. No Core activity/enabled gate; Payout must be Kernel-active for routing. Other flag fixed independently to false/true. Flag true validates currently selected distributor live, including same-value calls.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-YIELD-A01 | Fuzz callers excluding selected config operator and every ADMIN_ROLE holder | Unselected caller without ADMIN | NotAuthorised() | Covered: [test_whenUnauthorized_reverts][test_whenUnauthorized_reverts] |

## Lifecycle

| ID | Caller | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-YIELD-L01 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | Core inactive or disabled; Payout active | Success after authorization (new=false) | If changed, flag/event; if unchanged, no-op; no balance/obligation movement | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks][test_givenPayoutActive_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks][test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable][test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable] |
| BLCU-YIELD-L03 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | new=true; distributor Kernel-inactive | PolicyDependency_NotActive(distributor) | Unchanged | Covered: [test_givenInactiveDistributor_whenSetTrue_reverts][test_givenInactiveDistributor_whenSetTrue_reverts]; [test_givenInactiveDistributor_givenEachRecoveryRole_whenSetTrue_reverts][test_givenInactiveDistributor_givenEachRecoveryRole_whenSetTrue_reverts] |
| BLCU-YIELD-L05 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | new=true; distributor locally disabled | PolicyDependency_NotActive(distributor) | Unchanged | Covered: [test_givenPausedDistributor_whenSetTrue_reverts][test_givenPausedDistributor_whenSetTrue_reverts]; [test_givenPausedDistributor_givenEachRecoveryRole_whenSetTrue_reverts][test_givenPausedDistributor_givenEachRecoveryRole_whenSetTrue_reverts] |
| BLCU-YIELD-L07 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=true; new=false; distributor later disabled | Success | Flag=false; emit flag event; no distributor validation | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks][test_givenPayoutActive_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks][test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable][test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable] |
| BLCU-YIELD-L09 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=false; new=false; distributor later disabled | Success | No-op; no flag write/event or distributor validation (implemented no-op) | Covered: [test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp][test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp]; [test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp][test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-YIELD-I01 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | new=true, distributor=0 | RevenueDistributorRequired | Covered: [test_givenUnsetDistributor_whenSetTrue_reverts][test_givenUnsetDistributor_whenSetTrue_reverts]; [test_givenUnsetDistributor_givenEachRecoveryRole_whenSetTrue_reverts][test_givenUnsetDistributor_givenEachRecoveryRole_whenSetTrue_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-YIELD-P01 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=false; new=true; selected distributor valid | Success | Flag=true; exact flag event | Covered: [test_whenEnabled_thenOnlyFlagChanges][test_whenEnabled_thenOnlyFlagChanges]; [test_givenEachRecoveryRole_whenEnabled_thenOnlyFlagChanges][test_givenEachRecoveryRole_whenEnabled_thenOnlyFlagChanges] |
| BLCU-YIELD-P03 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=true; new=true; selected distributor valid | Success | Revalidate distributor, then no-op without flag write/event (implemented no-op) | Covered: [test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp][test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp]; [test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp][test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp]; [test_whenSameFlagValue_thenRoutingSlotNotWritten][test_whenSameFlagValue_thenRoutingSlotNotWritten] |

## Shared assertions

Pending fee bucket follows fee destination resolved by Payout from the Payout's local routing flags at retry; seizure backing follows current Treasury, keeper remains original. Yield goes directly to route and has no pending Payout bucket. A flag change never moves existing balances.

Co-located API assertions: `sendYieldToDistributor`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same configuration value

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCU-YIELD-P05 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | Exactly current complete value; fuzz the valid domain defined above, including its explicit boundary seeds | No-op after required validation | No setter writes/events; positions, obligations, authority and balances unchanged | Covered: [test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp][test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp]; [test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp][test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp]; [test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp][test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp]; [test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp][test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp]; [test_whenSameFlagValue_thenRoutingSlotNotWritten][test_whenSameFlagValue_thenRoutingSlotNotWritten] |

## Stored-controller identity

Retired BLCU-YIELD-A02/A03/A04 assumed reverse controller checks. The target authorizes its stored address. Equivalent permitted-caller families replace duplicate role rows; guarantee exclusive-role and overlap seeds.

| ID | Caller | Controller condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-YIELD-D01 | Stored nonzero configOperator without ADMIN | Kernel-inactive; requested false differs from true | Success | Flag/event only; no controller read | Covered: [test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices][test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices] |
| BLCU-YIELD-D02 | Stored nonzero configOperator without ADMIN | Locally disabled; requested false differs from true | Success | No controller enabled getter | Covered: [test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices][test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices] |
| BLCU-YIELD-D03 | Stored nonzero configOperator without ADMIN | kernel() reports another Kernel or reverts; requested false differs from true | Success | No reverse Kernel/interface validation | Covered: [test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices][test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices] |

## Distributor Kernel consistency

Payout's controller is an upstream authority reference; the downstream distributor must share Payout's current Kernel. Both local flags otherwise have valid independent values.

| ID | Caller | Proposed flag | Distributor | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-YIELD-D04 | Fuzz ADMIN-only, stored nonzero configOperator-only and overlap | true; old false/true | Reports another Kernel | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | Unchanged | Covered: [test_givenDistributorKernelDrift_whenSetTrue_reverts][test_givenDistributorKernelDrift_whenSetTrue_reverts]; [test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetTrue_reverts][test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetTrue_reverts] |
| BLCU-YIELD-D05 | Fuzz ADMIN-only, stored nonzero configOperator-only and overlap | false; old=true | Reports another Kernel | Success without distributor validation | Flag=false; corresponding event only | Covered: [test_givenDistributorKernelDrift_whenSetFalse_thenRepairWorks][test_givenDistributorKernelDrift_whenSetFalse_thenRepairWorks]; [test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetFalse_thenRepairWorks][test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetFalse_thenRepairWorks] |

## Local repair lifecycle

Caller is ADMIN or stored nonzero configOperator, fuzz both exclusive classes and overlap; Core flags independent. Proposed false differs from true.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-YIELD-L20 | Fuzz permitted caller | true | true | Success | Only flag/event changes; obligations unchanged | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks][test_givenPayoutActive_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks][test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable][test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable] |
| BLCU-YIELD-L21 | Fuzz permitted caller | true | false | Success | Only flag/event changes; obligations unchanged | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks][test_givenPayoutActive_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks][test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks]; [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable][test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable] |
| BLCU-YIELD-L22 | Fuzz permitted caller | false | true | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts][test_givenPayoutInactive_whenCalled_reverts] |
| BLCU-YIELD-L23 | Fuzz permitted caller | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts][test_givenPayoutInactive_whenCalled_reverts] |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-YIELD-L24 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |

[test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp]: ./setSendYieldToDistributor.t.sol#L308
[test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp]: ./setSendYieldToDistributor.t.sol#L104
[test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp]: ./setSendYieldToDistributor.t.sol#L276
[test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp]: ./setSendYieldToDistributor.t.sol#L55
[test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetFalse_thenRepairWorks]: ./setSendYieldToDistributor.t.sol#L383
[test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L368
[test_givenDistributorKernelDrift_whenSetFalse_thenRepairWorks]: ./setSendYieldToDistributor.t.sol#L220
[test_givenDistributorKernelDrift_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L195
[test_givenEachRecoveryRole_whenEnabled_thenOnlyFlagChanges]: ./setSendYieldToDistributor.t.sol#L261
[test_givenInactiveDistributor_givenEachRecoveryRole_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L338
[test_givenInactiveDistributor_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L153
[test_givenPausedDistributor_givenEachRecoveryRole_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L353
[test_givenPausedDistributor_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L174
[test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks]: ./setSendYieldToDistributor.t.sol#L291
[test_givenPayoutActive_whenDisabled_thenRepairWorks]: ./setSendYieldToDistributor.t.sol#L75
[test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable]: ./setSendYieldToDistributor.t.sol#L399
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./setSendYieldToDistributor.t.sol#L479
[test_givenPayoutInactive_whenCalled_reverts]: ./setSendYieldToDistributor.t.sol#L461
[test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices]: ./setSendYieldToDistributor.t.sol#L241
[test_givenUnsetDistributor_givenEachRecoveryRole_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L324
[test_givenUnsetDistributor_whenSetTrue_reverts]: ./setSendYieldToDistributor.t.sol#L127
[test_whenEnabled_thenOnlyFlagChanges]: ./setSendYieldToDistributor.t.sol#L36
[test_whenSameFlagValue_thenRoutingSlotNotWritten]: ./setSendYieldToDistributor.t.sol#L449
[test_whenUnauthorized_reverts]: ./setSendYieldToDistributor.t.sol#L26
