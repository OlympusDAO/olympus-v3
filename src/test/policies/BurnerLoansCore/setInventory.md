# BurnerLoansCore.setInventory coverage plan

Source: [setInventory](../../../policies/burnerloans/BurnerLoansCore.sol#L683). Acceptance criteria below include replacement requirements not yet implemented by the current setter. No migration implementation is required for this spike.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-INVENTORY`. ADMIN only; Core must be active, but may be locally enabled or disabled. Guard order: Core reentrancy guard, own activity, ADMIN, address checks, shared candidate validation, OHM compatibility and ledger equality, then pointer/event.

The candidate must advertise IBurnerLoansInventory, IBurnerLoansCoreBound, IEnabler and IVersioned. Its `core()` must equal this Core and its OHM must match. Check membership with Core’s `kernel.isPolicyActive(candidate)`; a matching self-reported Kernel alone is insufficient. Inventory’s Core identity getter is `core()`, replacing `facility()`.

Let P=activePrincipalOhm(), S=suppliedOhm() (aggregate provider claims), J=suppliedIdleOhm(). Units are OHM raw token units; all three are uint128. Core compares candidate P with canonical FLOAN debt and, on replacement, old P and S with candidate P and S. A first installation has no old ledger to compare. Old P/S need not be zero.

Unchanged means the selected pointer, both ledgers, provider claims, FLOAN positions/aggregates, balances, approvals, independent config operators and logs remain unchanged. Body cases use distinct valid candidates unless stated otherwise. Numeric fuzzing includes 0,1,MAX128 and adjacent mismatches where representable.

## Shared Core-bound validation

Generalize the existing core-only IBurnerLoansCoreBound interface as standalone `IBurnerLoansCoreBound`, exposing `core()` with an ABI-encoded address return. No interface inheritance or new base contract is required. Concrete bound components advertise it separately from their own service interface. Its core() selector is unchanged; do not validate the old and new names twice.

Use one internal view helper in Core for all three dependency setters. It accepts the candidate and the component ERC-165 interface ID (`type(IBurnerLoansInventory).interfaceId` here); Core-bound, IEnabler and IVersioned IDs and policy checks are common. These are interface IDs, not a list of arbitrary method selectors. The helper separates compatibility from readiness; this setter owns `BurnerLoansCore_InvalidInventory(next)`. It neither changes state nor grants authority.

A required replacement must have deployed code, advertise every required interface through compliant ERC165 discovery, report the expected Kernel, belong to that authoritative Kernel, be locally enabled and return this Core from `core()`. Probe candidate metadata with static calls and require canonical ABI address/bool words; `core()` must return exactly 32 bytes with zero address padding. Missing methods other than Kernel/status getters, failed or malformed Core-binding reads, false interface support and wrong Core binding use `BurnerLoansCore_InvalidInventory(candidate)`. Failed or malformed Kernel/status reads use `PolicyDependency_InvalidDependency(candidate)`. Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel)`. An inactive or disabled replacement also uses `BurnerLoansCore_InvalidInventory(candidate)`. No candidate error, ABI-decode revert or panic escapes the validation boundary. Check compatibility before readiness. Reject an unchanged nonzero pointer before probing; zero remains an invalid dependency even when the current pointer is unset.

Share the identity/readiness predicates with Core activation, retaining operation-specific errors: setters reject unavailable candidates with `InvalidInventory(candidate)`, while enable/reEnable use `PolicyDependency_NotActive(dependency)` for drift in an already-selected service. Keep OHM and Inventory ledger checks in their setters and upstream Config selection outside this helper. The shared PolicyDependency helper implements Kernel/status validation; the tests below encode these acceptance criteria.

## Authorization

Core active; otherwise-valid candidate; guard idle.

| ID | Caller | Input / competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-A01 | Fuzz caller excluding every ADMIN_ROLE holder | Valid candidate; independently invalid candidate | ROLES_RequireRole(ADMIN_ROLE) | Unchanged; no compatibility reads | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Core lifecycle

Candidate active/enabled, correctly bound, with matching ledgers; ADMIN caller; initialized ROLES.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-L01 | Fuzz ADMIN_ROLE holder | true | true | Success | InventorySet(next); pointer only | Covered: [test][test_givenCompatibleReadyService_whenSelected] |
| BLCORE-INVENTORY-L02 | Fuzz ADMIN_ROLE holder | true | false | Success | Same selection while Core paused | Covered: [test][test_givenCompatibleReadyService_whenSelected] |
| BLCORE-INVENTORY-L03 | Fuzz ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Unchanged | Covered: [test][test_givenCoreInactive_whenSelected_reverts] |
| BLCORE-INVENTORY-L04 | Fuzz ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Unchanged | Covered: [test][test_givenCoreInactive_whenSelected_reverts] |

## Candidate lifecycle

Core active; fuzz Core local enablement with both seeds. Candidate supports required interfaces, reports this Kernel and has valid bindings/ledgers. Inventory active is the result of Core Kernel membership, not a candidate-provided claim.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-L05 | ADMIN_ROLE holder | true | true | Success | Select next; independent configOperator preserved | Covered: [test][test_givenCompatibleReadyService_whenSelected] |
| BLCORE-INVENTORY-L06 | ADMIN_ROLE holder | true | false | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-INVENTORY-D01 | ADMIN_ROLE holder | false | true | BurnerLoansCore_InvalidInventory(next) | Unchanged; reported matching Kernel cannot substitute for membership | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |
| BLCORE-INVENTORY-D02 | ADMIN_ROLE holder | false | false | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenServiceUnavailable_whenSelected_reverts], [test][test_whenUnavailableServiceStatesSeeded_reverts] |

## Dependency compatibility and invalid inputs

ADMIN; Core active; guard idle. Isolate each fault with earlier checks satisfied. For a reported-Kernel mismatch, retain membership in Core’s Kernel and change only the candidate’s reported Kernel.

| ID | Caller | Candidate fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-D03 | ADMIN_ROLE holder | Active in Core Kernel; kernel() reports another Kernel | PolicyDependency_KernelMismatch(next,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenWrongKernel_whenSelected_reverts] |
| BLCORE-INVENTORY-D04 | ADMIN_ROLE holder | Nonzero EOA | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenEOA_whenSelected_reverts] |
| BLCORE-INVENTORY-D05 | ADMIN_ROLE holder | Missing IBurnerLoansInventory | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenServiceInterface_whenSelected_reverts] |
| BLCORE-INVENTORY-D06 | ADMIN_ROLE holder | Missing IEnabler | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenEnabledInterface_whenSelected_reverts] |
| BLCORE-INVENTORY-D07 | ADMIN_ROLE holder | Missing IVersioned | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenVersionInterface_whenSelected_reverts] |
| BLCORE-INVENTORY-D08 | ADMIN_ROLE holder | ERC165 reverts | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenRevertingERC165_whenSelected_reverts] |
| BLCORE-INVENTORY-D09 | ADMIN_ROLE holder | ERC165 returns malformed data | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenMalformedERC165_whenSelected_reverts] |
| BLCORE-INVENTORY-D10 | ADMIN_ROLE holder | Required interfaces advertised; core() reverts with fixture CoreReadFailed() | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenRevertingCore_whenSelected_reverts] |
| BLCORE-INVENTORY-D11 | ADMIN_ROLE holder | Required interfaces advertised; core() returns a non-32-byte response; fuzz lengths 0..31 and 33..256; seed 0,1,31,33,64,256 | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenMalformedCore_whenSelected_reverts], [test][test_whenCoreReturnLengthSeeds_reverts] |
| BLCORE-INVENTORY-D12 | ADMIN_ROLE holder | Required interfaces advertised; core() missing; fixture has no fallback | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenMissingCore_whenSelected_reverts] |
| BLCORE-INVENTORY-I01 | ADMIN_ROLE holder | next.core() differs from address(this); seed zero and another deployed Core | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenOtherCore_whenSelected_reverts] |
| BLCORE-INVENTORY-I02 | ADMIN_ROLE holder | Next OHM differs from Core | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenOtherOhm_whenSelected_reverts] |
| BLCORE-INVENTORY-I06 | ADMIN_ROLE holder | Next address zero | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenZero_whenSelected_reverts] |
| BLCORE-INVENTORY-D13 | ADMIN_ROLE holder | Own service/IEnabler/IVersioned interfaces valid; IBurnerLoansCoreBound not advertised | BurnerLoansCore_InvalidInventory(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenBoundInterface_whenSelected_reverts] |
| BLCORE-INVENTORY-D15 | ADMIN_ROLE holder | core() returns 32 bytes with nonzero upper 96 bits and lower 160 bits equal to Core; seed a single high padding bit | BurnerLoansCore_InvalidInventory(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenDirtyCore_whenSelected_reverts], [test][test_givenSingleDirtyCorePaddingBit_whenSelected_reverts] |
| BLCORE-INVENTORY-D16 | ADMIN_ROLE holder | kernel() staticcall reverts with fixture KernelReadFailed() | PolicyDependency_InvalidDependency(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenRevertingKernel_whenSelected_reverts] |
| BLCORE-INVENTORY-D17 | ADMIN_ROLE holder | kernel() returns a malformed address word; fuzz non-32-byte lengths and seed dirty address padding | PolicyDependency_InvalidDependency(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenMalformedKernel_whenSelected_reverts], [test][test_whenKernelReturnLengthSeeds_reverts], [test][test_givenDirtyKernelPadding_whenSelected_reverts] |
| BLCORE-INVENTORY-D18 | ADMIN_ROLE holder | isEnabled() staticcall reverts with fixture EnabledReadFailed() | PolicyDependency_InvalidDependency(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenRevertingEnabled_whenSelected_reverts] |
| BLCORE-INVENTORY-D19 | ADMIN_ROLE holder | isEnabled() returns a malformed boolean; seed empty bytes, one byte, 32-byte value 2 and 64 bytes | PolicyDependency_InvalidDependency(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenMalformedEnabled_whenSelected_reverts], [test][test_whenEnabledReturnShapeSeeds_reverts] |
| BLCORE-INVENTORY-D20 | ADMIN_ROLE holder | ERC165 response is a noncanonical boolean word with value 2, even if a truthy integer would appear to pass | BurnerLoansCore_InvalidInventory(next) | Unchanged; no pointer, ledger, balance or committed-log change | Covered: [test][test_givenNoncanonicalERC165_whenSelected_reverts] |
| BLCORE-INVENTORY-D21 | ADMIN_ROLE holder | core() attempts a storage write instead of serving a read-only identity | BurnerLoansCore_InvalidInventory(next) | Static call fails; fixture storage, pointer and all accounting unchanged; no committed logs | Covered: [test][test_givenWritingCore_whenSelected_reverts] |
| BLCORE-INVENTORY-D22 | ADMIN_ROLE holder | ERC165 responds true to every ID, including 0xffffffff | BurnerLoansCore_InvalidInventory(next) | Unchanged; a noncompliant ERC165 responder cannot pass | Covered: [test][test_givenLyingERC165_whenSelected_reverts] |
| BLCORE-INVENTORY-D23 | ADMIN_ROLE holder | Required interfaces present; core() returns another Core and candidate is Kernel-inactive and disabled | BurnerLoansCore_InvalidInventory(next) | Unchanged; incompatible binding wins over readiness failure | Covered: [test][test_givenBadBindingAndUnavailable_whenSelected_reverts] |

## Ledger consistency

Both inventories correctly bound; candidate active/enabled; canonical FLOAN total fixed independently. Configure migrated ledgers directly in setter unit fixtures; migration itself is future work. Fuzz each mismatch below and above its expected value, including MAX128 when valid. Each rejection preserves both ledgers and the old pointer.

| ID | Caller | Old ledger | Candidate ledger / canonical debt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-I03 | ADMIN_ROLE holder | Absent on first installation | Next P differs from canonical FLOAN total | BurnerLoansCore_InvalidInventory(next) | Unchanged | Covered: [test][test_givenCanonicalMismatch_whenInventorySelected_reverts] |
| BLCORE-INVENTORY-I07 | ADMIN_ROLE holder | P differs from canonical FLOAN total | Next P equals canonical total but differs from old P | BurnerLoansCore_InvalidInventory(next) | Unchanged; replacement cannot silently rewrite principal | Covered: [test][test_givenOldPrincipalMismatch_whenInventorySelected_reverts] |
| BLCORE-INVENTORY-I08 | ADMIN_ROLE holder | P equals canonical total; S fixed | Next P matches, next S differs from old S | BurnerLoansCore_InvalidInventory(next) | Unchanged; preserve claims, including defaulted claims | Covered: [test][test_givenClaimMismatch_whenInventorySelected_reverts] |

Retire BLCORE-INVENTORY-I04/I05: nonzero old principal or provider claims are no longer rejection conditions. [The existing fully-defaulted-claims test](setInventory.t.sol#L20) proves the current restrictive guard, not the new replacement behavior.

## Successful installation and replacement

ADMIN; Core active; candidate active/enabled, required interfaces, Core/OHM/Kernel correct. Assert `inventory()` independently and unchanged `totalActiveDebtOhm()`. Provider claim and idle-backing assertions use the migration fixture’s independently specified values, not just candidate-returned aggregates.

| ID | Caller | Prior state / replacement preparation | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-P01 | ADMIN_ROLE holder | Old pointer unset; no debt; candidate P=S=J=0 | Success | Select next; InventorySet once; independent configOperator preserved | Covered: [test][test_givenOldInventoryUnset_whenEmptyInventorySelected] |
| BLCORE-INVENTORY-P03 | ADMIN_ROLE holder | Old P=0,S=100e9,J=0 after supply/draw/default of 100 OHM; next preserves P=0,S=100e9,J=0 and the same provider’s 100e9 claim | Success | Claims survive despite zero balance/principal; no automatic recapitalization or claim cancellation | Covered: [test][test_givenMigratedLedger_whenSelected], [test][test_whenMigratedLedgerBoundarySeeds], [test][test_givenDefaultedProviderClaims_whenInventorySelected] |
| BLCORE-INVENTORY-P04 | ADMIN_ROLE holder | Canonical/old/next P=60e9; Alice claim=70e9, Bob=30e9; old/next S=100e9,J=40e9; migration has moved 40e9 idle OHM and preserved each claim | Success | Pointer switches; canonical loans unchanged; new instance can service same debt/claims; Core itself transfers nothing | Covered: [test][test_givenMigratedLedger_whenSelected], [test][test_whenMigratedLedgerBoundarySeeds], [test][test_givenMigratedTwoProviderLedger_whenInventorySelected] |
| BLCORE-INVENTORY-P05 | ADMIN_ROLE holder | Old/next P=0,S=J=100e9; all provider claims and idle funds preserved by migration | Success | Positive idle funds/claims do not block selection at zero debt | Covered: [test][test_givenMigratedLedger_whenSelected], [test][test_whenMigratedLedgerBoundarySeeds], [test][test_givenMigratedIdleProviderFunds_whenInventorySelected] |

The future migration procedure must preserve every provider’s identity and claim, J and its OHM backing, and any surplus; prevent duplicate withdrawals/settlement on the old instance; and reconcile MINTR approvals. Matching P/S aggregates do not prove those properties. Keep that trust with OCG and the separately reviewed migrator; do not add provider enumeration or migration scaffolding to this setter now. The accepted brief pause and atomic governance transaction provide the migration boundary; this setter does not introduce a mandatory Core pause.

## Same contract address

Equality rejects before dependency reads, ledger comparison or any mutation.

| ID | Caller | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-INVENTORY-P02 | Fuzz ADMIN_ROLE holder | Current selected address | BurnerLoans_UnchangedAddress(candidate) | Unchanged; no compatibility reads or logs | Covered: [test][test_whenCurrentAddressIsSelected_reverts] |

[test_givenBadBindingAndUnavailable_whenSelected_reverts]: setInventory.t.sol#L647
[test_givenBoundInterface_whenSelected_reverts]: setInventory.t.sol#L420
[test_givenCanonicalMismatch_whenInventorySelected_reverts]: setInventory.t.sol#L760
[test_givenClaimMismatch_whenInventorySelected_reverts]: setInventory.t.sol#L814
[test_givenCompatibleReadyService_whenSelected]: setInventory.t.sol#L92
[test_givenCoreInactive_whenSelected_reverts]: setInventory.t.sol#L46
[test_givenDefaultedProviderClaims_whenInventorySelected]: setInventory.t.sol#L934
[test_givenDirtyCore_whenSelected_reverts]: setInventory.t.sol#L442
[test_givenDirtyKernelPadding_whenSelected_reverts]: setInventory.t.sol#L882
[test_givenEOA_whenSelected_reverts]: setInventory.t.sol#L150
[test_givenEnabledInterface_whenSelected_reverts]: setInventory.t.sol#L207
[test_givenLyingERC165_whenSelected_reverts]: setInventory.t.sol#L621
[test_givenMalformedCore_whenSelected_reverts]: setInventory.t.sol#L319
[test_givenMalformedERC165_whenSelected_reverts]: setInventory.t.sol#L398
[test_givenMalformedEnabled_whenSelected_reverts]: setInventory.t.sol#L548
[test_givenMalformedKernel_whenSelected_reverts]: setInventory.t.sol#L495
[test_givenMigratedIdleProviderFunds_whenInventorySelected]: setInventory.t.sol#L993
[test_givenMigratedLedger_whenSelected]: setInventory.t.sol#L696
[test_givenMigratedTwoProviderLedger_whenInventorySelected]: setInventory.t.sol#L963
[test_givenMissingCore_whenSelected_reverts]: setInventory.t.sol#L297
[test_givenNoncanonicalERC165_whenSelected_reverts]: setInventory.t.sol#L570
[test_givenOldInventoryUnset_whenEmptyInventorySelected]: setInventory.t.sol#L687
[test_givenOldPrincipalMismatch_whenInventorySelected_reverts]: setInventory.t.sol#L787
[test_givenOtherCore_whenSelected_reverts]: setInventory.t.sol#L274
[test_givenOtherOhm_whenSelected_reverts]: setInventory.t.sol#L251
[test_givenRevertingCore_whenSelected_reverts]: setInventory.t.sol#L346
[test_givenRevertingERC165_whenSelected_reverts]: setInventory.t.sol#L372
[test_givenRevertingEnabled_whenSelected_reverts]: setInventory.t.sol#L522
[test_givenRevertingKernel_whenSelected_reverts]: setInventory.t.sol#L469
[test_givenServiceInterface_whenSelected_reverts]: setInventory.t.sol#L185
[test_givenServiceUnavailable_whenSelected_reverts]: setInventory.t.sol#L113
[test_givenSingleDirtyCorePaddingBit_whenSelected_reverts]: setInventory.t.sol#L918
[test_givenVersionInterface_whenSelected_reverts]: setInventory.t.sol#L229
[test_givenWritingCore_whenSelected_reverts]: setInventory.t.sol#L599
[test_givenWrongKernel_whenSelected_reverts]: setInventory.t.sol#L166
[test_givenZero_whenSelected_reverts]: setInventory.t.sol#L135
[test_whenCallerIsNotAdmin_reverts]: setInventory.t.sol#L36
[test_whenCoreReturnLengthSeeds_reverts]: setInventory.t.sol#L852
[test_whenCurrentAddressIsSelected_reverts]: setInventory.t.sol#L66
[test_whenEnabledReturnShapeSeeds_reverts]: setInventory.t.sol#L898
[test_whenKernelReturnLengthSeeds_reverts]: setInventory.t.sol#L867
[test_whenMigratedLedgerBoundarySeeds]: setInventory.t.sol#L739
[test_whenUnavailableServiceStatesSeeded_reverts]: setInventory.t.sol#L841
