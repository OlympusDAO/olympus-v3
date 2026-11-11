# BurnerLoansPayout.setConfigOperator coverage plan

Source: [setConfigOperator](../../../policies/burnerloans/BurnerLoansPayout.sol#L167). Shared setter semantics are inherited from ConfigOperatorSingleStep. Apply [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md).

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

## Domains and behavior

Scenario scope: `BLCU-CONFIGURATOR` identifies this contract/function.

Implemented change: ADMIN installs a locally stored PayoutConfigTimelock address, independently of Core's general Config. Core no longer has controller-synchronization authority. The controller is upstream: do not query its activity, enablement, Kernel, facility, OHM or interface. No reverse policy validation occurs. Direct ADMIN mutation checks requireNotReentrant on Core and Payout's local guard. Core/Payout lifecycle does not gate authority repair.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CONFIGURATOR-P01 | Fuzz ADMIN_ROLE holder | true | Fuzz true/false independently | Fuzz true/false | Fuzz true/false | Distinct nonzero controller | Success without reverse getters | Store local authority; ConfigOperatorSet; balances/claims unchanged | Covered: [test_whenAdminInstallsController_thenNoReverseReads][test_whenAdminInstallsController_thenNoReverseReads], [test_givenExistingAdmin_whenControllerInstalled_thenNoReverseReads][test_givenExistingAdmin_whenControllerInstalled_thenNoReverseReads] |
| BLCU-CONFIGURATOR-P02 | Fuzz ADMIN_ROLE holder | false | Fuzz true/false independently | Fuzz true/false | Fuzz true/false | Distinct nonzero controller | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts][test_givenPayoutInactive_whenCalled_reverts] |

## Pointer inputs

| ID | Caller | Input / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CONFIGURATOR-A02 | Fuzz ADMIN_ROLE holder | Current controller address | IConfigOperator.ConfigOperator_Unchanged() | Unchanged; no validation or events | Covered: [test_whenOperatorUnchanged_reverts][test_whenOperatorUnchanged_reverts] |
| BLCU-CONFIGURATOR-A03 | Fuzz ADMIN_ROLE holder | Distinct controller whose lifecycle/identity/interface getters reject | Success | No reverse getters called | Covered: [test_whenAdminInstallsController_thenNoReverseReads][test_whenAdminInstallsController_thenNoReverseReads], [test_givenExistingAdmin_whenControllerInstalled_thenNoReverseReads][test_givenExistingAdmin_whenControllerInstalled_thenNoReverseReads] |
| BLCU-CONFIGURATOR-A04 | Fuzz ADMIN_ROLE holder | Zero controller, previous nonzero | Success | Delegation revoked; ConfigOperatorSet(0) | Covered: [test_givenNonzeroOperator_whenCleared_thenDelegationRevoked][test_givenNonzeroOperator_whenCleared_thenDelegationRevoked] |

## Independent authority installation

Core's Config handoff and Payout selection must not call this setter. Initial linking works before the timelock is active/enabled, avoiding startup cycles. Previous Payout authority stays local. Its timelock covers routing and recovery and must not be overwritten by general Config handoff. A failed direct installation preserves the old controller and all balances/claims.

## Installation authorization

Core idle and Payout local guard clear; distinct nonzero candidate. The stored controller cannot appoint its successor without ADMIN.

| ID | Caller | Request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CONFIGURATOR-A01 | Fuzz caller excluding every ADMIN holder; seed Core without ADMIN | Any controller | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_whenCallerLacksAdmin_reverts][test_whenCallerLacksAdmin_reverts]; [test_givenCoreOrStoredOperator_whenInstallingSuccessor_reverts][test_givenCoreOrStoredOperator_whenInstallingSuccessor_reverts] |

Retired BLCU-CONFIGURATOR-A05 duplicated the unauthorized-caller family retained as A01.

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CONFIGURATOR-L01 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |

[test_givenCoreOrStoredOperator_whenInstallingSuccessor_reverts]: ./setConfigOperator.t.sol#L61
[test_givenNonzeroOperator_whenCleared_thenDelegationRevoked]: ./setConfigOperator.t.sol#L77
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./setConfigOperator.t.sol#L120
[test_givenPayoutInactive_whenCalled_reverts]: ./setConfigOperator.t.sol#L106
[test_whenAdminInstallsController_thenNoReverseReads]: ./setConfigOperator.t.sol#L21
[test_whenCallerLacksAdmin_reverts]: ./setConfigOperator.t.sol#L49
[test_whenOperatorUnchanged_reverts]: ./setConfigOperator.t.sol#L69

[test_givenExistingAdmin_whenControllerInstalled_thenNoReverseReads]: setConfigOperator.t.sol#L133
