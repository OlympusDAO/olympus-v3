# BurnerLoansRisk.setBackingOracle coverage plan

Source: [setBackingOracle](../../../policies/burnerloans/BurnerLoansRisk.sol#L562). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-BACKING-ORACLE` identifies this contract/function.

Governance uses Risk's Kernel-resolved ROLES. Risk must be active; ADMIN may replace pricing addresses while paused to repair the service. Validate deployed code and IBackingOracle/IEnabler support with the oracle-specific error, then require its reported Kernel to match Risk. No IVersioned support is required. Membership and enablement are checked at activation and consumption, allowing replacement while paused.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-BACKING-ORACLE-L01 | ADMIN_ROLE holder | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenEnabled_whenDependencyChanges] |
| BLRISK-BACKING-ORACLE-L02 | ADMIN_ROLE holder | true | false | Same valid function result | No changes on rejection | Covered: [test][test_givenDisabled_whenDependencyChanges] |
| BLRISK-BACKING-ORACLE-L03 | ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenDependencyChanges_reverts] |
| BLRISK-BACKING-ORACLE-L04 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenDependencyChanges_reverts] |

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-BACKING-ORACLE-A01 | Fuzz caller excluding every ADMIN holder, including selected Config without ADMIN | Valid and invalid input | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenUnauthorizedCaller_reverts] |

## Invalid inputs

Fixed for this table: pointer unchanged; no committed logs. IEnabler must be advertised separately from IBackingOracle.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-BACKING-ORACLE-I01 | Fuzz ADMIN_ROLE holder | candidate=0 | BurnerLoans_InvalidBackingOracle(0) | Covered: [test][test_whenZero_reverts] |
| BLRISK-BACKING-ORACLE-I02 | Fuzz ADMIN_ROLE holder | candidate is nonzero EOA | BurnerLoans_InvalidBackingOracle(candidate) | Covered: [test][test_whenEoa_reverts] |
| BLRISK-BACKING-ORACLE-I03 | Fuzz ADMIN_ROLE holder | Deployed candidate lacks IBackingOracle support | BurnerLoans_InvalidBackingOracle(candidate) | Covered: [test][test_whenMissingInterface_reverts] |
| BLRISK-BACKING-ORACLE-D02 | ADMIN_ROLE holder | Nonzero deployed oracle supports IBackingOracle but not IEnabler | BurnerLoans_InvalidBackingOracle(oracle) | Covered: [test][test_whenMissingEnabler_reverts] |
| BLRISK-BACKING-ORACLE-I04 | ADMIN_ROLE holder | ERC165 reverts | BurnerLoans_InvalidBackingOracle(candidate) | Covered: [test][test_whenRevertingERC165_reverts] |
| BLRISK-BACKING-ORACLE-I05 | ADMIN_ROLE holder | ERC165 returns malformed data | BurnerLoans_InvalidBackingOracle(candidate) | Covered: [test][test_whenMalformedERC165_reverts] |

## Successful execution

Fixed for this table: Accounting / events: No eager backing price read; future snapshot validates zero.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-BACKING-ORACLE-P01 | Fuzz ADMIN_ROLE holder | Distinct supported oracle, including one returning zero backing later | Store+BackingOracleSet; existing loans use the replacement on later risk evaluation | Covered: [test][test_whenZeroBackingOracleSelected] |
| BLRISK-BACKING-ORACLE-I06 | ADMIN | Candidate advertises IBackingOracle and IEnabler but rejects the removed backing/setBacking-only interface ID | Store+BackingOracleSet; snapshot reads the same 18-decimal backing | Covered: [current interface][test_whenOnlyCurrentInterfaceSupported] |

Co-located API assertions: `backingOracle`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same contract address

ADMIN-only code-address selection: submitting the current address must revert, including zero when the optional dependency is already unset. Implemented equality rejection precedes dependency reads and event emission.

| ID | Caller | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-BACKING-ORACLE-P02 | Fuzz ADMIN_ROLE holder | Current nonzero oracle address | BurnerLoans_UnchangedAddress(candidate) | Unchanged; no downstream validation or events | Covered: [test][test_whenUnchanged_reverts] |

## Backing lifecycle acceptance

Replacement requires IBackingOracle/IEnabler support and matching Kernel,
without IVersioned. Candidate activity/enablement is deferred to activation and
consumption, preserving governance repair while Risk is locally paused.

| ID | Caller | Scenario | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-BACKING-ORACLE-D03 | ADMIN | Oracle kernel() reports 0xBAD instead of Risk Kernel | PolicyDependency_KernelMismatch(oracle,Risk Kernel,0xBAD) | Covered: [test][test_givenBackingForeignKernel_whenAdmitted_reverts] |
| BLRISK-BACKING-ORACLE-D04 | ADMIN | Oracle kernel() returns uint256.max, a noncanonical address | PolicyDependency_InvalidDependency(oracle) | Covered: [test][test_givenBackingMalformedKernel_whenAdmitted_reverts] |

[test_givenDisabled_whenDependencyChanges]: setBackingOracle.t.sol#L71

[test_givenEnabled_whenDependencyChanges]: setBackingOracle.t.sol#L66

[test_givenInactiveAndDisabled_whenDependencyChanges_reverts]: setBackingOracle.t.sol#L86

[test_givenInactive_whenDependencyChanges_reverts]: setBackingOracle.t.sol#L78

[test_whenEoa_reverts]: setBackingOracle.t.sol#L107

[test_whenMalformedERC165_reverts]: setBackingOracle.t.sol#L139

[test_whenMissingInterface_reverts]: setBackingOracle.t.sol#L112

[test_whenRevertingERC165_reverts]: setBackingOracle.t.sol#L128

[test_whenUnauthorizedCaller_reverts]: setBackingOracle.t.sol#L94

[test_whenUnchanged_reverts]: setBackingOracle.t.sol#L150

[test_whenMissingEnabler_reverts]: setBackingOracle.t.sol#L117

[test_whenZeroBackingOracleSelected]: setBackingOracle.t.sol#L166

[test_whenZero_reverts]: setBackingOracle.t.sol#L102
[test_whenOnlyCurrentInterfaceSupported]: setBackingOracle.t.sol#L23

[test_givenBackingForeignKernel_whenAdmitted_reverts]: ./setBackingOracle.t.sol#L177

[test_givenBackingMalformedKernel_whenAdmitted_reverts]: ./setBackingOracle.t.sol#L196
