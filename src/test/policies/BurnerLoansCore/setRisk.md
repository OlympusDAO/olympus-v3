# BurnerLoansCore.setRisk coverage plan

Source: [setRisk](../../../policies/burnerloans/BurnerLoansCore.sol#L836). Acceptance plan; coverage and execution results are recorded separately.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-RISK` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN only, callable while Core active and locally enabled/disabled; no disabled prerequisite. Incoming contract must advertise IBurnerLoansRisk, IBurnerLoansCoreBound, IEnabler and IVersioned, belong to Core’s Kernel, report that Kernel, use the same OHM and return address(this) from core(). Risk selects its own configuration operator independently of Core’s Config. The Core binding is an immutable identity only: Risk does not read Core for prices, configuration or lifecycle. Installation rejects inactive or locally disabled candidates, as setInventory does. Later Core activation and Risk service calls also enforce readiness after independent lifecycle drift. Installation never reads or writes either Risk's configOperator or the former configurator API. Guard order: Core reentrancy guard, own activity, ADMIN, address checks, shared candidate validation, OHM compatibility, then pointer/event.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Shared Core-bound validation

Generalize the existing core-only IBurnerLoansCoreBound interface as standalone `IBurnerLoansCoreBound`, exposing `core()` with an ABI-encoded address return. No interface inheritance or new base contract is required. Concrete bound components advertise it separately from their own service interface. Its core() selector is unchanged; do not validate the old and new names twice.

Use one internal view helper in Core for all three dependency setters. It accepts the candidate and the component ERC-165 interface ID (`type(IBurnerLoansRisk).interfaceId` here); Core-bound, IEnabler and IVersioned IDs and policy checks are common. These are interface IDs, not a list of arbitrary method selectors. The helper separates compatibility from readiness; this setter owns `BurnerLoansCore_InvalidRisk(candidate)`. It neither changes state nor grants authority.

A required replacement must have deployed code, advertise every required interface through compliant ERC165 discovery, report the expected Kernel, belong to that authoritative Kernel, be locally enabled and return this Core from `core()`. Probe candidate metadata with static calls and require canonical ABI address/bool words; `core()` must return exactly 32 bytes with zero address padding. Missing methods other than Kernel/status getters, failed or malformed Core-binding reads, false interface support and wrong Core binding use `BurnerLoansCore_InvalidRisk(candidate)`. Failed or malformed Kernel/status reads use `PolicyDependency_InvalidDependency(candidate)`. Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel)`. An inactive or disabled replacement also uses `BurnerLoansCore_InvalidRisk(candidate)`. No candidate error, ABI-decode revert or panic escapes the validation boundary. Check compatibility before readiness. Reject an unchanged nonzero pointer before probing; zero remains an invalid dependency even when the current pointer is unset.

Share the identity/readiness predicates with Core activation, retaining operation-specific errors: setters reject unavailable candidates with `InvalidRisk(candidate)`, while enable/reEnable use `PolicyDependency_NotActive(dependency)` for drift in an already-selected service. Keep OHM and Inventory ledger checks in their setters and upstream Config selection outside this helper. The shared PolicyDependency helper implements Kernel/status validation; the tests below encode these acceptance criteria.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-RISK-A01 | Non-ADMIN (fuzz excluding all ADMIN holders) | Any candidate including invalid | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Invalid inputs

Core outside settlement; ADMIN caller; all canonical loan, collateral and payout state preserved on rejection.

| ID | Caller | Candidate address / getter | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-RISK-I01 | ADMIN_ROLE holder | address(0) | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no committed logs | Covered: [test][test_givenZero_whenSelected_reverts] |
| BLCORE-RISK-I02 | ADMIN_ROLE holder | EOA | `BurnerLoansCore_InvalidRisk(candidate)` | Unchanged; no committed logs | Covered: [test][test_givenEOA_whenSelected_reverts] |
| BLCORE-RISK-I03 | ADMIN_ROLE holder | Active in Core Kernel; required interfaces supported; kernel() reports another Kernel | `PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel)` | Unchanged; no committed logs | Covered: [test][test_givenWrongKernel_whenSelected_reverts] |
| BLCORE-RISK-I04 | ADMIN_ROLE holder | Deployed; IBurnerLoansRisk missing | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no committed logs | Covered: [test][test_givenServiceInterface_whenSelected_reverts] |
| BLCORE-RISK-I05 | ADMIN_ROLE holder | Deployed; IEnabler missing | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no committed logs | Covered: [test][test_givenEnabledInterface_whenSelected_reverts] |
| BLCORE-RISK-I06 | ADMIN_ROLE holder | Deployed; IVersioned missing | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no committed logs | Covered: [test][test_givenVersionInterface_whenSelected_reverts] |
| BLCORE-RISK-I10 | ADMIN_ROLE holder | Required interfaces and Kernel match, OHM differs | BurnerLoansCore_InvalidRisk(candidate) | No selection changes or logs | Covered: [test][test_givenOtherOhm_whenSelected_reverts] |
| BLCORE-RISK-I11 | ADMIN_ROLE holder | Required interfaces and real Kernel membership valid; core() returns another Core; separately seed zero | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no committed logs | Covered: [test][test_givenOtherCore_whenSelected_reverts], [test][test_givenZeroCoreBinding_whenSelected_reverts] |
| BLCORE-RISK-I12 | ADMIN_ROLE holder | Required interfaces advertised; core() missing | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenMissingCore_whenSelected_reverts] |
| BLCORE-RISK-I13 | ADMIN_ROLE holder | Required interfaces advertised; core() returns a non-32-byte response; fuzz lengths 0..31 and 33..256; seed 0,1,31,33,64,256 | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenMalformedCore_whenSelected_reverts], [test][test_whenCoreReturnLengthSeeds_reverts] |
| BLCORE-RISK-I14 | ADMIN_ROLE holder | Required interfaces advertised; core() reverts with fixture CoreReadFailed() | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenRevertingCore_whenSelected_reverts] |
| BLCORE-RISK-I15 | ADMIN_ROLE holder | ERC165 reverts | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenRevertingERC165_whenSelected_reverts] |
| BLCORE-RISK-I16 | ADMIN_ROLE holder | ERC165 returns malformed data | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenMalformedERC165_whenSelected_reverts] |
| BLCORE-RISK-D09 | ADMIN_ROLE holder | Own service/IEnabler/IVersioned interfaces valid; IBurnerLoansCoreBound not advertised | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenBoundInterface_whenSelected_reverts] |
| BLCORE-RISK-D11 | ADMIN_ROLE holder | core() returns 32 bytes with nonzero upper 96 bits and lower 160 bits equal to Core; seed a single high padding bit | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenDirtyCore_whenSelected_reverts], [test][test_givenSingleDirtyCorePaddingBit_whenSelected_reverts] |
| BLCORE-RISK-D12 | ADMIN_ROLE holder | kernel() staticcall reverts with fixture KernelReadFailed() | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenRevertingKernel_whenSelected_reverts] |
| BLCORE-RISK-D13 | ADMIN_ROLE holder | kernel() returns a malformed address word; fuzz non-32-byte lengths and seed dirty address padding | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenMalformedKernel_whenSelected_reverts], [test][test_whenKernelReturnLengthSeeds_reverts], [test][test_givenDirtyKernelPadding_whenSelected_reverts] |
| BLCORE-RISK-D14 | ADMIN_ROLE holder | isEnabled() staticcall reverts with fixture EnabledReadFailed() | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenRevertingEnabled_whenSelected_reverts] |
| BLCORE-RISK-D15 | ADMIN_ROLE holder | isEnabled() returns a malformed boolean; seed empty bytes, one byte, 32-byte value 2 and 64 bytes | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenMalformedEnabled_whenSelected_reverts], [test][test_whenEnabledReturnShapeSeeds_reverts] |
| BLCORE-RISK-D16 | ADMIN_ROLE holder | ERC165 response is a noncanonical boolean word with value 2, even if a truthy integer would appear to pass | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenNoncanonicalERC165_whenSelected_reverts] |
| BLCORE-RISK-D17 | ADMIN_ROLE holder | core() attempts a storage write instead of serving a read-only identity | BurnerLoansCore_InvalidRisk(candidate) | Static call fails; fixture storage, pointer and all accounting unchanged; no committed logs | Covered: [test][test_givenWritingCore_whenSelected_reverts] |
| BLCORE-RISK-D18 | ADMIN_ROLE holder | ERC165 responds true to every ID, including 0xffffffff | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; a noncompliant ERC165 responder cannot pass | Covered: [test][test_givenLyingERC165_whenSelected_reverts] |
| BLCORE-RISK-D19 | ADMIN_ROLE holder | Required interfaces present; core() returns another Core and candidate is Kernel-inactive and disabled | BurnerLoansCore_InvalidRisk(candidate) | Unchanged; incompatible binding wins over readiness failure | Covered: [test][test_givenBadBindingAndUnavailable_whenSelected_reverts] |

## Configuration transitions

Core outside settlement; Core must be active; local enablement is not a gate. Candidate is active and enabled in Core’s Kernel, has valid interfaces, this Core binding and the same Kernel/OHM. Live loans and pending payouts are present.

| ID | Caller | Current pointer | Candidate | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RISK-P01 | Fuzz ADMIN_ROLE holder | Previous compatible Risk | Distinct active/enabled same-Kernel/OHM Core-bound Risk; its operator independently unset, equal to or different from Core Config | Success | Only selected pointer changes; one RiskSet(candidate); no Risk configuration getter/setter call; positions/balances/controllers unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected], [test][test_givenIndependentRiskOperator_whenSelected], [test][test_whenIndependentOperatorSeeds] |

## Callbacks and reentrancy

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Callback / nested call | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-RISK-C01 | ADMIN_ROLE holder | Replacement during guarded settlement callback | ReentrancyGuardReentrantCall | Covered: [test][test_givenBusyCore_whenSelected_reverts] |

## Own policy activity

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RISK-P02 | Fuzz ADMIN_ROLE holder | true | true | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected], [test][test_givenIndependentRiskOperator_whenSelected], [test][test_whenIndependentOperatorSeeds] |
| BLCORE-RISK-P03 | Fuzz ADMIN_ROLE holder | true | false | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected], [test][test_givenIndependentRiskOperator_whenSelected], [test][test_whenIndependentOperatorSeeds] |
| BLCORE-RISK-P04 | Fuzz ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenSelected_reverts] |
| BLCORE-RISK-P05 | Fuzz ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenSelected_reverts] |

## Shared assertions

Replacing Risk alters subsequent prices/health/fees for existing loans without moving canonical accounting. Check the Risk API, pause/version interfaces, Core/OHM identity and actual Kernel membership at installation. Binding Risk to Core does not couple their configuration authorities or create a reverse operational dependency. The source currently lacks the new Core-binding/membership requirements; existing tests are partial evidence only where compatible.

Co-located API assertions: `risk`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Existing tests informing this plan

New modular entrypoint with no direct legacy counterpart. Its caller/binding/replacement cases supplement the existing settlement and lifecycle suites; do not manufacture a legacy coverage mapping.

## Same contract address

Core active; guard idle; permitted caller. Address equality is checked before compatibility reads or event emission.

| ID | Caller | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-RISK-P06 | Fuzz ADMIN_ROLE holder | Current selected address | BurnerLoans_UnchangedAddress(candidate) | Unchanged; no binding reads, transfers, sync or logs | Covered: [test][test_whenCurrentAddressIsSelected_reverts] |

## Independent configuration authority

Other Risk compatibility checks pass. Core remains active; local enablement is not a gate. Each rejection-oriented case below concerns an unused authority getter, not a required service getter. Retired IDs BLCORE-RISK-I07/I08/I09 described authority-coupling failures and are superseded by these success requirements.

| ID | Caller | Risk authority / unused getter | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-RISK-D01 | Fuzz ADMIN_ROLE holder | configOperator independently zero, Core Config, or a distinct address; guarantee each seed | Success | Risk selected; its operator and all Core/Config/Inventory/Payout authorities unchanged; RiskSet once | Covered: [test][test_givenIndependentRiskOperator_whenSelected], [test][test_whenIndependentOperatorSeeds] |
| BLCORE-RISK-D02 | Fuzz ADMIN_ROLE holder | configOperator() and former configurator() both revert if called | Success | No authority getter or setter calls; only Risk selection changes | Covered: [test][test_givenRevertingAuthorityGetters_whenSelected] |
| BLCORE-RISK-D03 | Fuzz ADMIN_ROLE holder | configOperator() and former configurator() return malformed bytes if called | Success | No unused authority decoding; loans, balances and independent authorities preserved | Covered: [test][test_givenMalformedAuthorityGetters_whenSelected] |

## Candidate Kernel membership

Core active; fuzz Core enabled true/false with both seeds. Candidate has valid interfaces, matching Core/OHM and reports Core’s Kernel. Candidate activity means `kernel.isPolicyActive(candidate)` in Core’s intended Kernel. Self-reported Kernel identity cannot substitute for this lookup. Check local enablement separately from Kernel membership: both must be true at installation. Later independent lifecycle drift is covered by Core activation and Risk service tests.

| ID | Caller | Risk active | Risk enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RISK-D04 | ADMIN_ROLE holder | true | true | Success | Pointer/event only; authority unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected] |
| BLCORE-RISK-D08 | ADMIN_ROLE holder | true | false | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-RISK-D06 | ADMIN_ROLE holder | false | true | BurnerLoansCore_InvalidRisk(candidate) | Unchanged even when kernel() falsely reports the expected Kernel | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-RISK-D07 | ADMIN_ROLE holder | false | false | BurnerLoansCore_InvalidRisk(candidate) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |

Retire BLCORE-RISK-D05: selecting a disabled replacement is no longer permitted. Compatibility rows keep earlier checks satisfied; missing, malformed or reverting validation responses use BurnerLoansCore_InvalidRisk(candidate); no dependency revert data is bubbled.

[test_givenBadBindingAndUnavailable_whenSelected_reverts]: setRisk.t.sol#L651
[test_givenBoundInterface_whenSelected_reverts]: setRisk.t.sol#L424
[test_givenBusyCore_whenSelected_reverts]: setRisk.t.sol#L717
[test_givenCompatibleReadyService_whenSelected]: setRisk.t.sol#L89
[test_givenCoreInactive_whenSelected_reverts]: setRisk.t.sol#L43
[test_givenDirtyCore_whenSelected_reverts]: setRisk.t.sol#L446
[test_givenDirtyKernelPadding_whenSelected_reverts]: setRisk.t.sol#L774
[test_givenEOA_whenSelected_reverts]: setRisk.t.sol#L148
[test_givenEnabledInterface_whenSelected_reverts]: setRisk.t.sol#L206
[test_givenIndependentRiskOperator_whenSelected]: setRisk.t.sol#L675
[test_givenLyingERC165_whenSelected_reverts]: setRisk.t.sol#L625
[test_givenMalformedAuthorityGetters_whenSelected]: setRisk.t.sol#L707
[test_givenMalformedCore_whenSelected_reverts]: setRisk.t.sol#L323
[test_givenMalformedERC165_whenSelected_reverts]: setRisk.t.sol#L402
[test_givenMalformedEnabled_whenSelected_reverts]: setRisk.t.sol#L552
[test_givenMalformedKernel_whenSelected_reverts]: setRisk.t.sol#L499
[test_givenMissingCore_whenSelected_reverts]: setRisk.t.sol#L301
[test_givenNoncanonicalERC165_whenSelected_reverts]: setRisk.t.sol#L574
[test_givenOtherCore_whenSelected_reverts]: setRisk.t.sol#L273
[test_givenOtherOhm_whenSelected_reverts]: setRisk.t.sol#L250
[test_givenRevertingAuthorityGetters_whenSelected]: setRisk.t.sol#L697
[test_givenRevertingCore_whenSelected_reverts]: setRisk.t.sol#L350
[test_givenRevertingERC165_whenSelected_reverts]: setRisk.t.sol#L376
[test_givenRevertingEnabled_whenSelected_reverts]: setRisk.t.sol#L526
[test_givenRevertingKernel_whenSelected_reverts]: setRisk.t.sol#L473
[test_givenServiceInterface_whenSelected_reverts]: setRisk.t.sol#L184
[test_givenServiceUnavailable_whenSelected_reverts]: setRisk.t.sol#L111
[test_givenSingleDirtyCorePaddingBit_whenSelected_reverts]: setRisk.t.sol#L810
[test_givenVersionInterface_whenSelected_reverts]: setRisk.t.sol#L228
[test_givenWritingCore_whenSelected_reverts]: setRisk.t.sol#L603
[test_givenWrongKernel_whenSelected_reverts]: setRisk.t.sol#L164
[test_givenZeroCoreBinding_whenSelected_reverts]: setRisk.t.sol#L296
[test_givenZero_whenSelected_reverts]: setRisk.t.sol#L133
[test_whenCallerIsNotAdmin_reverts]: setRisk.t.sol#L33
[test_whenCoreReturnLengthSeeds_reverts]: setRisk.t.sol#L744
[test_whenCurrentAddressIsSelected_reverts]: setRisk.t.sol#L63
[test_whenEnabledReturnShapeSeeds_reverts]: setRisk.t.sol#L790
[test_whenIndependentOperatorSeeds]: setRisk.t.sol#L826
[test_whenKernelReturnLengthSeeds_reverts]: setRisk.t.sol#L759
[test_whenUnavailableServiceStatesSeeded_reverts]: setRisk.t.sol#L733
