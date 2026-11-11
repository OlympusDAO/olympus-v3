# BurnerLoansPayoutConfigTimelock.constructor coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [constructor](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-CONSTRUCTOR`. Fuzz deployer. Kernel and Payout are constructor inputs. No local/controller/Core admission is required before deployment.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Invalid inputs

| ID | Caller | Candidate | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-CONSTRUCTOR-I01 | Fuzz deployer | Payout=0 | BurnerLoansPayoutTimelock_InvalidPayout(0) | No deployment/logs | Covered: [test][test_whenPayoutZero_reverts] |
| BLCUCT-CONSTRUCTOR-I02 | Fuzz deployer | Nonzero Payout EOA | BurnerLoansPayoutTimelock_InvalidPayout(candidate) | No deployment/logs | Covered: [test][test_whenPayoutEOA_reverts] |

## Binding and interface checks

| ID | Caller | Fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-CONSTRUCTOR-D01 | Fuzz deployer | Deployed Payout lacks IBurnerLoansPayout | InvalidPayout(candidate) | No deployment | Covered: [test][test_givenMissingInterface_whenDeployed_reverts], [seeds][test_givenEachRequiredInterfaceMissing_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D02 | Fuzz deployer | ERC165 reverts | InvalidPayout(candidate) | No deployment | Covered: [test][test_givenERC165Reverts_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D03 | Fuzz deployer | ERC165 malformed response | InvalidPayout(candidate) | No deployment | Covered: [test][test_givenERC165Malformed_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D04 | Fuzz deployer | Interface supported; reports another Kernel | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | No deployment | Covered: [test][test_givenWrongKernel_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D05 | Fuzz deployer | Interface supported; kernel() reverts | PolicyDependency_InvalidDependency(Payout) | No deployment | Covered: [test][test_givenKernelProbeReverts_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D06 | Fuzz deployer | Interface supported; kernel() returns malformed data | PolicyDependency_InvalidDependency(Payout) | No deployment | Covered: [test][test_givenKernelProbeMalformed_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D07 | Fuzz deployer | Missing IConfigOperator interface | InvalidPayout(candidate) | No deployment | Covered: [test][test_givenMissingInterface_whenDeployed_reverts], [test][test_givenEachRequiredInterfaceMissing_whenDeployed_reverts] |
| BLCUCT-CONSTRUCTOR-D08 | Fuzz deployer | Missing IEnabler interface | InvalidPayout(candidate) | No deployment | Covered: [test][test_givenMissingInterface_whenDeployed_reverts], [test][test_givenEachRequiredInterfaceMissing_whenDeployed_reverts] |

## Lifecycle independence

Keep constructor Kernel/interface bindings valid while varying lifecycle independently.

| ID | Caller | Payout active | Payout enabled | Core active | Core enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-CONSTRUCTOR-L01 | Fuzz deployer | true | Fuzz false/true | Fuzz true/false | Fuzz true/false | Success | Immutable target/Kernel; local disabled; nextActionId=1; delay=1 day; grace=7 days; no payout/controller write | Covered: [test][test_givenIndependentLifecycle_whenDeployed_thenExactDefaults], [test][test_givenLifecycleSeeds_whenDeployed_thenExactDefaults] |
| BLCUCT-CONSTRUCTOR-L02 | Fuzz deployer | false | Fuzz false/true | Fuzz true/false | Fuzz true/false | Success | Same initialization; controller may be unset at deployment | Covered: [test][test_givenIndependentLifecycle_whenDeployed_thenExactDefaults], [test][test_givenLifecycleSeeds_whenDeployed_thenExactDefaults] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

## Construction without runtime readiness

The constructor validates the same consumed interface set as enable/reEnable and the same-Kernel binding. It does not read target activity, enabled state or selected configOperator.

| ID | Caller | Target condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-CONSTRUCTOR-L03 | Fuzz deployer | Target activity, isEnabled and configOperator reads revert; consumed interfaces and Kernel binding valid | Success | No readiness/selection reads; target bound; queue disabled | Covered: [test][test_givenRuntimeReadinessGettersRevert_whenConstructed] |

[test_givenERC165Malformed_whenDeployed_reverts]: ./constructor.t.sol#L60
[test_givenERC165Reverts_whenDeployed_reverts]: ./constructor.t.sol#L50
[test_givenIndependentLifecycle_whenDeployed_thenExactDefaults]: ./constructor.t.sol#L116
[test_givenKernelProbeMalformed_whenDeployed_reverts]: ./constructor.t.sol#L103
[test_givenKernelProbeReverts_whenDeployed_reverts]: ./constructor.t.sol#L86
[test_givenLifecycleSeeds_whenDeployed_thenExactDefaults]: ./constructor.t.sol#L144
[test_givenMissingInterface_whenDeployed_reverts]: ./constructor.t.sol#L32
[test_givenWrongKernel_whenDeployed_reverts]: ./constructor.t.sol#L70
[test_whenPayoutEOA_reverts]: ./constructor.t.sol#L26
[test_whenPayoutZero_reverts]: ./constructor.t.sol#L21
[test_givenEachRequiredInterfaceMissing_whenDeployed_reverts]: ./constructor.t.sol#L162
[test_givenRuntimeReadinessGettersRevert_whenConstructed]: ./constructor.t.sol#L171
