# BurnerLoansCore.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansCore.sol#L105). Acceptance plan; coverage and execution results are recorded separately.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-CONSTRUCTOR` identifies this contract/function.

Kernel,OHM,DepositManager; Implemented change: all replaceable component pointers start unset, including Payout. Deploy Core-bound Payout separately, then select it through ADMIN. No Lens pointer exists. Grants/maps start empty.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Dependency compatibility

Fixed for this table: Accounting / events: No deployment or committed logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-CONSTRUCTOR-D01 | Fuzz all deployers | DepositManager ERC165 reverts | BurnerLoansCore_InvalidDepositManager(DM) | Covered: [test][test_givenRevertingERC165_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-D02 | Fuzz all deployers | DepositManager ERC165 returns malformed response | BurnerLoansCore_InvalidDepositManager(DM) | Covered: [test][test_givenMalformedERC165_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-D03 | Fuzz all deployers | DepositManager interface valid; reports another Kernel | PolicyDependency_KernelMismatch(DepositManager,expectedKernel,reportedKernel) | Covered: [test][test_givenWrongKernel_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-P01 | Fuzz all deployers | DepositManager interface valid; kernel getter reverts | PolicyDependency_InvalidDependency(DM) | Covered: [test][test_givenKernelGetterReverts_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-P02 | Fuzz all deployers | OHM decimals getter reverts | BurnerLoansCore_InvalidOhm(OHM) | Covered: [test][test_givenDecimalsGetterReverts_whenDeployed_reverts] |

## Invalid inputs

Fixed for this table: Accounting / events: No deployment or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-CONSTRUCTOR-I01 | Fuzz all deployers | OHM=0; DepositManager compatible | BurnerLoansCore_InvalidOhm(0) | Covered: [test][test_givenZeroOhm_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-I02 | Fuzz all deployers | OHM nonzero; DepositManager=0 | BurnerLoansCore_InvalidDepositManager(0) | Covered: [test][test_givenZeroDepositManager_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-I03 | Fuzz all deployers | DepositManager is EOA | BurnerLoansCore_InvalidDepositManager(DM) | Covered: [test][test_givenEOADepositManager_whenDeployed_reverts] |
| BLCORE-CONSTRUCTOR-I04 | Fuzz all deployers | DepositManager lacks IDepositManagerV1_1 | BurnerLoansCore_InvalidDepositManager(DM) | Covered: [test][test_givenMissingInterface_whenDeployed_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: No deployment or committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-CONSTRUCTOR-N01 | Fuzz all deployers | OHM decimals fuzz 37..MAX8 | BurnerLoansCore_InvalidOhm(OHM) | Covered: [test][test_givenUnsupportedDecimals_whenDeployed_reverts], [test][test_whenUnsupportedDecimalSeeds_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CONSTRUCTOR-P03 | Fuzz all deployers | Valid inputs; OHM decimals 0..36; seed 0,1,9,18,36 | Success | Immutable OHM/DM; disabled; no Risk/Inventory/Config/Payout; no child deployment or PayoutSet event; gracePeriod=7 days; GracePeriodSet | Covered: [test][test_whenDeployed], [test][test_whenDecimalsBoundarySeeds] |
| BLCORE-CONSTRUCTOR-P04 | Fuzz all deployers | Valid inputs; DepositManager active=true; enabled=true | Success | No deployment-time DM lifecycle gate | Covered: [test][test_whenDeployed] |
| BLCORE-CONSTRUCTOR-P05 | Fuzz all deployers | Valid inputs; DepositManager active=true; enabled=false | Success | No deployment-time DM lifecycle gate | Covered: [test][test_whenDeployed] |
| BLCORE-CONSTRUCTOR-P06 | Fuzz all deployers | Valid inputs; DepositManager active=false; enabled=true | Success | No deployment-time DM lifecycle gate | Covered: [test][test_whenDeployed] |
| BLCORE-CONSTRUCTOR-P07 | Fuzz all deployers | Valid inputs; DepositManager active=false; enabled=false | Success | No deployment-time DM lifecycle gate | Covered: [test][test_whenDeployed] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `ohm`, `depositManager`, `payout`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

[test_givenDecimalsGetterReverts_whenDeployed_reverts]: constructor.t.sol#L220
[test_givenEOADepositManager_whenDeployed_reverts]: constructor.t.sol#L98
[test_givenKernelGetterReverts_whenDeployed_reverts]: constructor.t.sol#L199
[test_givenMalformedERC165_whenDeployed_reverts]: constructor.t.sol#L155
[test_givenMissingInterface_whenDeployed_reverts]: constructor.t.sol#L110
[test_givenRevertingERC165_whenDeployed_reverts]: constructor.t.sol#L134
[test_givenUnsupportedDecimals_whenDeployed_reverts]: constructor.t.sol#L236
[test_givenWrongKernel_whenDeployed_reverts]: constructor.t.sol#L176
[test_givenZeroDepositManager_whenDeployed_reverts]: constructor.t.sol#L86
[test_givenZeroOhm_whenDeployed_reverts]: constructor.t.sol#L79
[test_whenDecimalsBoundarySeeds]: constructor.t.sol#L62
[test_whenDeployed]: constructor.t.sol#L25
[test_whenUnsupportedDecimalSeeds_reverts]: constructor.t.sol#L248
