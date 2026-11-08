# BurnerLoansCore.setPayout coverage plan

Source: [setPayout](../../../policies/burnerloans/BurnerLoansCore.sol#L944). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-CUSTODY` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN only, callable while Core active and locally enabled/disabled; no disabled prerequisite. Incoming contract must be active in Core’s Kernel according to kernel.isPolicyActive(candidate), report that same Kernel, be locally enabled, advertise IBurnerLoansPayout/IBurnerLoansCoreBound/IEnabler/IVersioned and return this Core from core(). Self-reported Kernel identity is not membership. Implemented change: selection preserves its independently initialized local Payout-timelock controller; there is no general Config synchronization. Guard order: Core reentrancy guard, own activity, ADMIN, address checks, shared candidate validation, then pointer/event. Compatibility failures use BurnerLoansCore_InvalidPayout(candidate); a readable mismatched Kernel uses PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel).

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Shared Core-bound validation

Generalize the existing core-only IBurnerLoansCoreBound interface as standalone `IBurnerLoansCoreBound`, exposing `core()` with an ABI-encoded address return. No interface inheritance or new base contract is required. Concrete bound components advertise it separately from their own service interface. Its core() selector is unchanged; do not validate the old and new names twice.

Use one internal view helper in Core for all three dependency setters. It accepts the candidate and the component ERC-165 interface ID (`type(IBurnerLoansPayout).interfaceId` here); Core-bound, IEnabler and IVersioned IDs and policy checks are common. These are interface IDs, not a list of arbitrary method selectors. The helper separates compatibility from readiness; this setter owns `BurnerLoansCore_InvalidPayout(candidate)`. It neither changes state nor grants authority.

A required replacement must have deployed code, advertise every required interface through compliant ERC165 discovery, report the expected Kernel, belong to that authoritative Kernel, be locally enabled and return this Core from `core()`. Probe candidate metadata with static calls and require canonical ABI address/bool words; `core()` must return exactly 32 bytes with zero address padding. Missing methods other than Kernel/status getters, failed or malformed Core-binding reads, false interface support and wrong Core binding use `BurnerLoansCore_InvalidPayout(candidate)`. Failed or malformed Kernel/status reads use `PolicyDependency_InvalidDependency(candidate)`. Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel)`. An inactive or disabled replacement also uses `BurnerLoansCore_InvalidPayout(candidate)`. No candidate error, ABI-decode revert or panic escapes the validation boundary. Check compatibility before readiness. Reject an unchanged nonzero pointer before probing; zero remains an invalid dependency even when the current pointer is unset.

Share the identity/readiness predicates with Core activation, retaining operation-specific errors: setters reject unavailable candidates with `InvalidPayout(candidate)`, while enable/reEnable use `PolicyDependency_NotActive(dependency)` for drift in an already-selected service. Keep OHM and Inventory ledger checks in their setters and upstream Config selection outside this helper. The shared PolicyDependency helper implements Kernel/status validation; the tests below encode these acceptance criteria.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-A01 | Non-ADMIN (fuzz excluding all ADMIN holders) | Any candidate including invalid | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Invalid inputs

Core active; permitted ADMIN; idle guard; remaining compatibility checks pass until the isolated fault.

| ID | Caller | Candidate fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-I01 | Fuzz ADMIN_ROLE holder | 0 | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenZero_whenSelected_reverts] |
| BLCORE-CUSTODY-I02 | Fuzz ADMIN_ROLE holder | Nonzero address without code | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenEOA_whenSelected_reverts] |
| BLCORE-CUSTODY-I03 | Fuzz ADMIN_ROLE holder | Deployed compatible Payout bound to another Core | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenOtherCore_whenSelected_reverts] |
| BLCORE-CUSTODY-I04 | Fuzz ADMIN_ROLE holder | Deployed candidate missing IBurnerLoansPayout | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenServiceInterface_whenSelected_reverts] |
| BLCORE-CUSTODY-I05 | Fuzz ADMIN_ROLE holder | Candidate advertises interface but core() is missing | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenMissingCore_whenSelected_reverts] |
| BLCORE-CUSTODY-I06 | Fuzz ADMIN_ROLE holder | Required interfaces advertised; core() returns a non-32-byte response; fuzz lengths 0..31 and 33..256; seed 0,1,31,33,64,256 | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenMalformedCore_whenSelected_reverts], [test][test_whenCoreReturnLengthSeeds_reverts] |
| BLCORE-CUSTODY-I07 | Fuzz ADMIN_ROLE holder | Candidate core() raises fixture CoreReadFailed() | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenRevertingCore_whenSelected_reverts] |
| BLCORE-CUSTODY-I08 | ADMIN_ROLE holder | IBurnerLoansPayout supported; IEnabler not advertised | BurnerLoansCore_InvalidPayout(candidate) | Current selection/obligations unchanged | Covered: [test][test_givenEnabledInterface_whenSelected_reverts] |
| BLCORE-CUSTODY-I09 | ADMIN_ROLE holder | IBurnerLoansPayout/IEnabler supported; IVersioned not advertised | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenVersionInterface_whenSelected_reverts] |
| BLCORE-CUSTODY-I10 | ADMIN_ROLE holder | ERC165 reverts | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenRevertingERC165_whenSelected_reverts] |
| BLCORE-CUSTODY-I11 | ADMIN_ROLE holder | ERC165 returns malformed data | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenMalformedERC165_whenSelected_reverts] |
| BLCORE-CUSTODY-D07 | ADMIN_ROLE holder | Own service/IEnabler/IVersioned interfaces valid; IBurnerLoansCoreBound not advertised | BurnerLoansCore_InvalidPayout(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenBoundInterface_whenSelected_reverts] |
| BLCORE-CUSTODY-D09 | ADMIN_ROLE holder | core() returns 32 bytes with nonzero upper 96 bits and lower 160 bits equal to Core; seed a single high padding bit | BurnerLoansCore_InvalidPayout(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenDirtyCore_whenSelected_reverts], [test][test_givenSingleDirtyCorePaddingBit_whenSelected_reverts] |
| BLCORE-CUSTODY-D10 | ADMIN_ROLE holder | kernel() staticcall reverts with fixture KernelReadFailed() | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenRevertingKernel_whenSelected_reverts] |
| BLCORE-CUSTODY-D11 | ADMIN_ROLE holder | kernel() returns a malformed address word; fuzz non-32-byte lengths and seed dirty address padding | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenMalformedKernel_whenSelected_reverts], [test][test_whenKernelReturnLengthSeeds_reverts], [test][test_givenDirtyKernelPadding_whenSelected_reverts] |
| BLCORE-CUSTODY-D12 | ADMIN_ROLE holder | isEnabled() staticcall reverts with fixture EnabledReadFailed() | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenRevertingEnabled_whenSelected_reverts] |
| BLCORE-CUSTODY-D13 | ADMIN_ROLE holder | isEnabled() returns a malformed boolean; seed empty bytes, one byte, 32-byte value 2 and 64 bytes | PolicyDependency_InvalidDependency(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenMalformedEnabled_whenSelected_reverts], [test][test_whenEnabledReturnShapeSeeds_reverts] |
| BLCORE-CUSTODY-D14 | ADMIN_ROLE holder | ERC165 response is a noncanonical boolean word with value 2, even if a truthy integer would appear to pass | BurnerLoansCore_InvalidPayout(candidate) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenNoncanonicalERC165_whenSelected_reverts] |
| BLCORE-CUSTODY-D15 | ADMIN_ROLE holder | core() attempts a storage write instead of serving a read-only identity | BurnerLoansCore_InvalidPayout(candidate) | Static call fails; fixture storage, pointer and all accounting unchanged; no committed logs | Covered: [test][test_givenWritingCore_whenSelected_reverts] |
| BLCORE-CUSTODY-D16 | ADMIN_ROLE holder | ERC165 responds true to every ID, including 0xffffffff | BurnerLoansCore_InvalidPayout(candidate) | Unchanged; a noncompliant ERC165 responder cannot pass | Covered: [test][test_givenLyingERC165_whenSelected_reverts] |
| BLCORE-CUSTODY-D17 | ADMIN_ROLE holder | Required interfaces present; core() returns another Core and candidate is Kernel-inactive and disabled | BurnerLoansCore_InvalidPayout(candidate) | Unchanged; incompatible binding wins over readiness failure | Covered: [test][test_givenBadBindingAndUnavailable_whenSelected_reverts] |

## Configuration transitions

| ID | Caller | Candidate / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-P01 | Fuzz ADMIN_ROLE holder | Distinct active/enabled same-Kernel Core-bound Payout; live loans and old pending payouts | Success | PayoutSet(previous,next); local controller preserved; positions and old obligations/balances unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected], [test][test_givenOldPendingObligations_whenPayoutSelected] |

## Callbacks and reentrancy

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Callback / nested call | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-C01 | ADMIN_ROLE holder | Replacement during guarded settlement callback | ReentrancyGuardReentrantCall | Covered: [test][test_givenBusyCore_whenSelected_reverts] |

## Own policy activity

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-P02 | Fuzz ADMIN_ROLE holder | true | true | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected], [test][test_givenOldPendingObligations_whenPayoutSelected] |
| BLCORE-CUSTODY-P03 | Fuzz ADMIN_ROLE holder | true | false | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCompatibleReadyService_whenSelected], [test][test_givenOldPendingObligations_whenPayoutSelected] |
| BLCORE-CUSTODY-P04 | Fuzz ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenSelected_reverts] |
| BLCORE-CUSTODY-P05 | Fuzz ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenSelected_reverts] |

## Shared assertions

Retired Payout remains claimable and rejects new credits; new Payout receives subsequent fees and seizure outputs, old obligations unchanged. Reselecting an old Payout is permitted by binding checks.

Co-located API assertions: `payout`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Existing tests informing this plan

New modular entrypoint with no direct legacy counterpart. Its caller/binding/replacement cases supplement the existing settlement and lifecycle suites; do not manufacture a legacy coverage mapping.

Also reject an inactive/different-Kernel replacement before selection, and prove an interface/binding failure preserves the old pointer. Initialize replacement routing and its own timelock explicitly; old routing/controller remain independent, with no automatic copying or synchronization. Same-pointer selection must revert before binding reads or events.

## Same contract address

Core active; guard idle; permitted caller. Address equality is checked before binding validation, migration, synchronization or event emission. Implemented unchanged-address rejection; assert it before compatibility reads or any mutation.

| ID | Caller | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-P06 | Fuzz ADMIN_ROLE holder | Current selected address | BurnerLoans_UnchangedAddress(candidate) | Unchanged; no binding reads, transfers, sync or logs | Covered: [test][test_whenCurrentAddressIsSelected_reverts] |

## Candidate Kernel membership and enablement

Core active; fuzz Core enabled true/false with both seeds. Required interfaces and immutable core() match. Payout must be active and enabled at installation, as Inventory must be. A later independent pause/deactivation still blocks new credits and Core activation; replacement does not change existing claims on the old Payout. Reported-Kernel mismatch is isolated with real membership still present, for example after candidate Kernel migration.

| ID | Caller | Payout active | Payout enabled | Reported Kernel | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-CUSTODY-D01 | ADMIN_ROLE holder | true | true | Expected Kernel | Success | Pointer/event only; old payouts preserved | Covered: [test][test_givenCompatibleReadyService_whenSelected] |
| BLCORE-CUSTODY-D06 | ADMIN_ROLE holder | true | false | Expected Kernel | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-CUSTODY-D03 | ADMIN_ROLE holder | false | true | Falsely reports expected Kernel | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-CUSTODY-D04 | ADMIN_ROLE holder | false | false | Falsely reports expected Kernel | BurnerLoansCore_InvalidPayout(candidate) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-CUSTODY-D05 | ADMIN_ROLE holder | true | true | Another Kernel | PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenWrongKernel_whenSelected_reverts] |

Retire BLCORE-CUSTODY-D02: selecting a disabled replacement is no longer permitted. Candidate-validation rows keep the earlier guard/interface/membership checks satisfied; missing, malformed or reverting validation responses use BurnerLoansCore_InvalidPayout(candidate); no dependency revert data is bubbled.

[test_givenBadBindingAndUnavailable_whenSelected_reverts]: setPayout.t.sol#L644
[test_givenBoundInterface_whenSelected_reverts]: setPayout.t.sol#L409
[test_givenBusyCore_whenSelected_reverts]: setPayout.t.sol#L668
[test_givenCompatibleReadyService_whenSelected]: setPayout.t.sol#L91
[test_givenCoreInactive_whenSelected_reverts]: setPayout.t.sol#L45
[test_givenDirtyCore_whenSelected_reverts]: setPayout.t.sol#L431
[test_givenDirtyKernelPadding_whenSelected_reverts]: setPayout.t.sol#L733
[test_givenEOA_whenSelected_reverts]: setPayout.t.sol#L150
[test_givenEnabledInterface_whenSelected_reverts]: setPayout.t.sol#L207
[test_givenLyingERC165_whenSelected_reverts]: setPayout.t.sol#L618
[test_givenMalformedCore_whenSelected_reverts]: setPayout.t.sol#L300
[test_givenMalformedERC165_whenSelected_reverts]: setPayout.t.sol#L383
[test_givenMalformedEnabled_whenSelected_reverts]: setPayout.t.sol#L541
[test_givenMalformedKernel_whenSelected_reverts]: setPayout.t.sol#L484
[test_givenMissingCore_whenSelected_reverts]: setPayout.t.sol#L274
[test_givenNoncanonicalERC165_whenSelected_reverts]: setPayout.t.sol#L567
[test_givenOldPendingObligations_whenPayoutSelected]: setPayout.t.sol#L789
[test_givenOtherCore_whenSelected_reverts]: setPayout.t.sol#L251
[test_givenRevertingCore_whenSelected_reverts]: setPayout.t.sol#L331
[test_givenRevertingERC165_whenSelected_reverts]: setPayout.t.sol#L357
[test_givenRevertingEnabled_whenSelected_reverts]: setPayout.t.sol#L515
[test_givenRevertingKernel_whenSelected_reverts]: setPayout.t.sol#L458
[test_givenServiceInterface_whenSelected_reverts]: setPayout.t.sol#L185
[test_givenServiceUnavailable_whenSelected_reverts]: setPayout.t.sol#L113
[test_givenSingleDirtyCorePaddingBit_whenSelected_reverts]: setPayout.t.sol#L773
[test_givenVersionInterface_whenSelected_reverts]: setPayout.t.sol#L229
[test_givenWritingCore_whenSelected_reverts]: setPayout.t.sol#L596
[test_givenWrongKernel_whenSelected_reverts]: setPayout.t.sol#L166
[test_givenZero_whenSelected_reverts]: setPayout.t.sol#L135
[test_whenCallerIsNotAdmin_reverts]: setPayout.t.sol#L35
[test_whenCoreReturnLengthSeeds_reverts]: setPayout.t.sol#L695
[test_whenCurrentAddressIsSelected_reverts]: setPayout.t.sol#L65
[test_whenEnabledReturnShapeSeeds_reverts]: setPayout.t.sol#L749
[test_whenKernelReturnLengthSeeds_reverts]: setPayout.t.sol#L714
[test_whenUnavailableServiceStatesSeeded_reverts]: setPayout.t.sol#L684
