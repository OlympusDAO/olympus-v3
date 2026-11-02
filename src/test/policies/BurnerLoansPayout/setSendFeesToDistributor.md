# BurnerLoansPayout.setSendFeesToDistributor coverage plan

Source: [setSendFeesToDistributor](../../../policies/burnerloans/BurnerLoansPayout.sol#L223). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Normalized scenario scope: `BLCU-FEES` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Implemented same-value rule: authorize and validate requested true, then return without writes/events when unchanged. Changing-value rows exclude the current value. Requested true still validates the selected distributor; requested false skips that validation.

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

Stored nonzero configOperator or ADMIN, without reverse controller lifecycle/interface/Kernel checks. No Core activity/enabled gate; Payout must be Kernel-active for routing. Other flag fixed independently to false/true. Flag true validates currently selected distributor live, including same-value calls.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-FEES-A01 | Fuzz callers excluding selected config operator and every ADMIN_ROLE holder | Unselected caller without ADMIN | NotAuthorised() | Covered: [test_whenUnauthorized_reverts](./setSendFeesToDistributor.t.sol#L23) |

## Lifecycle

| ID | Caller | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-FEES-L01 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | Core inactive or disabled; Payout active | Success after authorization (new=false) | If changed, flag/event; if unchanged, no-op; no balance/obligation movement | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L72); [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L288); [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable](./setSendFeesToDistributor.t.sol#L396) |
| BLCU-FEES-L03 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | new=true; distributor Kernel-inactive | PolicyDependency_NotActive(distributor) | Unchanged | Covered: [test_givenInactiveDistributor_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L150); [test_givenInactiveDistributor_givenEachRecoveryRole_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L335) |
| BLCU-FEES-L05 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | new=true; distributor locally disabled | PolicyDependency_NotActive(distributor) | Unchanged | Covered: [test_givenPausedDistributor_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L171); [test_givenPausedDistributor_givenEachRecoveryRole_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L350) |
| BLCU-FEES-L07 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=true; new=false; distributor later disabled | Success | Flag=false; emit flag event; no distributor validation | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L72); [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L288); [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable](./setSendFeesToDistributor.t.sol#L396) |
| BLCU-FEES-L09 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=false; new=false; distributor later disabled | Success | No-op; no flag write/event or distributor validation (implemented no-op) | Covered: [test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp](./setSendFeesToDistributor.t.sol#L101); [test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp](./setSendFeesToDistributor.t.sol#L305) |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-FEES-I01 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | new=true, distributor=0 | RevenueDistributorRequired | Covered: [test_givenUnsetDistributor_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L124); [test_givenUnsetDistributor_givenEachRecoveryRole_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L321) |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-FEES-P01 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=false; new=true; selected distributor valid | Success | Flag=true; exact flag event | Covered: [test_whenEnabled_thenOnlyFlagChanges](./setSendFeesToDistributor.t.sol#L33); [test_givenEachRecoveryRole_whenEnabled_thenOnlyFlagChanges](./setSendFeesToDistributor.t.sol#L258) |
| BLCU-FEES-P03 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | old=true; new=true; selected distributor valid | Success | Revalidate distributor, then no-op without flag write/event (implemented no-op) | Covered: [test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp](./setSendFeesToDistributor.t.sol#L52); [test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp](./setSendFeesToDistributor.t.sol#L273); [test_whenSameFlagValue_thenRoutingSlotNotWritten](./setSendFeesToDistributor.t.sol#L417) |

## Shared assertions

Pending fee bucket follows fee destination resolved by Payout from the Payout's local routing flags at retry; seizure backing follows current Treasury, keeper remains original. Yield goes directly to route and has no pending Payout bucket. A flag change never moves existing balances.

Co-located API assertions: `sendFeesToDistributor`, fee routing. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same configuration value

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCU-FEES-P05 | Fuzz permitted caller (ADMIN-only, stored controller-only, overlap seeds) | Exactly current complete value; fuzz the valid domain defined above, including its explicit boundary seeds | No-op after required validation | No setter writes/events; positions, obligations, authority and balances unchanged | Covered: [test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp](./setSendFeesToDistributor.t.sol#L52); [test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp](./setSendFeesToDistributor.t.sol#L101); [test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp](./setSendFeesToDistributor.t.sol#L273); [test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp](./setSendFeesToDistributor.t.sol#L305); [test_whenSameFlagValue_thenRoutingSlotNotWritten](./setSendFeesToDistributor.t.sol#L417) |

## Stored-controller identity

Retired BLCU-FEES-A02/A03/A04 assumed reverse controller checks. The target authorizes its stored address. Equivalent permitted-caller families replace duplicate role rows; guarantee exclusive-role and overlap seeds.

| ID | Caller | Controller condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-FEES-D01 | Stored nonzero configOperator without ADMIN | Kernel-inactive; requested false differs from true | Success | Flag/event only; no controller read | Covered: [test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices](./setSendFeesToDistributor.t.sol#L238) |
| BLCU-FEES-D02 | Stored nonzero configOperator without ADMIN | Locally disabled; requested false differs from true | Success | No controller enabled getter | Covered: [test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices](./setSendFeesToDistributor.t.sol#L238) |
| BLCU-FEES-D03 | Stored nonzero configOperator without ADMIN | kernel() reports another Kernel or reverts; requested false differs from true | Success | No reverse Kernel/interface validation | Covered: [test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices](./setSendFeesToDistributor.t.sol#L238) |

## Distributor Kernel consistency

Payout's controller is an upstream authority reference; the downstream distributor must share Payout's current Kernel. Both local flags otherwise have valid independent values.

| ID | Caller | Proposed flag | Distributor | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-FEES-D04 | Fuzz ADMIN-only, stored nonzero configOperator-only and overlap | true; old false/true | Reports another Kernel | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | Unchanged | Covered: [test_givenDistributorKernelDrift_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L192); [test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetTrue_reverts](./setSendFeesToDistributor.t.sol#L365) |
| BLCU-FEES-D05 | Fuzz ADMIN-only, stored nonzero configOperator-only and overlap | false; old=true | Reports another Kernel | Success without distributor validation | Flag=false; corresponding event only | Covered: [test_givenDistributorKernelDrift_whenSetFalse_thenRepairWorks](./setSendFeesToDistributor.t.sol#L217); [test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetFalse_thenRepairWorks](./setSendFeesToDistributor.t.sol#L380) |

## Local repair lifecycle

Caller is ADMIN or stored nonzero configOperator, fuzz both exclusive classes and overlap; Core flags independent. Proposed false differs from true.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-FEES-L20 | Fuzz permitted caller | true | true | Success | Only flag/event changes; obligations unchanged | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L72); [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L288); [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable](./setSendFeesToDistributor.t.sol#L396) |
| BLCU-FEES-L21 | Fuzz permitted caller | true | false | Success | Only flag/event changes; obligations unchanged | Covered: [test_givenPayoutActive_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L72); [test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks](./setSendFeesToDistributor.t.sol#L288); [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable](./setSendFeesToDistributor.t.sol#L396) |
| BLCU-FEES-L22 | Fuzz permitted caller | false | true | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts](./setSendFeesToDistributor.t.sol#L429) |
| BLCU-FEES-L23 | Fuzz permitted caller | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts](./setSendFeesToDistributor.t.sol#L429) |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-FEES-L24 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins](./setSendFeesToDistributor.t.sol#L447) |
