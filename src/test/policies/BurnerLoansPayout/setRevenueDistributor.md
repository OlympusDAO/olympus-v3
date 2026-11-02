# BurnerLoansPayout.setRevenueDistributor coverage plan

Source: [setRevenueDistributor and validateRevenueDistributor](../../../policies/burnerloans/BurnerLoansPayout.sol).

Scenario scope: `BLCRD`. Distributor address changes are direct ADMIN operations; the config operator and Payout timelock have no replacement authority. Core/Payout settlement guards must be idle. Repair is available in every independent Core/Payout activity/enabled state. `Unchanged` means pointer, flags, balances, reserves, indexes and committed logs unchanged.

## Authorization

Valid distinct distributor. The public validator is permissionless and ignores setter authorization.

| ID | Caller | Execution | Validator | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCRD-A01 | ADMIN_ROLE holder | Success | Success | Pointer and RevenueDistributorSet | Covered: [test_givenValidDistributor_whenSelected_thenOnlyPointerChanges](./setRevenueDistributor.t.sol#L24) |
| BLCRD-A03 | Fuzz caller excluding every ADMIN holder; seed current config operator, timelock and former operator | ROLES_RequireRole(ADMIN_ROLE) | Same validation as ADMIN | Unchanged | Covered: [test_whenCallerLacksAdmin_thenSetterRejectsAndValidatorPermits](./setRevenueDistributor.t.sol#L81); [test_givenCurrentAndFormerOperators_whenSelectingDistributor_reverts](./setRevenueDistributor.t.sol#L97) |

## Lifecycle and repair

Cached ROLES initialized; caller ADMIN; candidate is valid and distinct. Fuzz Core active/enabled independently; neither is a readiness dependency.

| ID | Caller | Local active | Local enabled | Execution | Validator | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCRD-L01 | ADMIN_ROLE holder | true | true | Success | Success | Pointer/event only | Covered: [test_givenValidDistributor_whenSelected_thenOnlyPointerChanges](./setRevenueDistributor.t.sol#L24) |
| BLCRD-L02 | ADMIN_ROLE holder | true | false | Success | Success | Pointer/event only | Covered: [test_givenValidDistributor_whenSelected_thenOnlyPointerChanges](./setRevenueDistributor.t.sol#L24) |
| BLCRD-L03 | ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Payout) | Success | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts](./setRevenueDistributor.t.sol#L338) |
| BLCRD-L04 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Payout) | Success | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts](./setRevenueDistributor.t.sol#L338) |

## Candidate validation

Caller ADMIN, candidate distinct; all independent requirements not varied are satisfied. Every failing validator must be called in the same test as the failing setter.

| ID | Caller | Candidate | Execution | Validator | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCRD-I01 | ADMIN_ROLE holder | Nonzero EOA | BurnerLoans_InvalidRevenueDistributor(candidate) | Same error | Unchanged | Covered: [test_whenDistributorEoa_reverts](./setRevenueDistributor.t.sol#L109) |
| BLCRD-I02 | ADMIN_ROLE holder | Deployed; lacks IRevenueDistributor | BurnerLoans_InvalidRevenueDistributor(candidate) | Same error | Unchanged | Covered: [test_givenMissingInterface_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L225) |
| BLCRD-I03 | ADMIN_ROLE holder | ERC165 reverts | BurnerLoans_InvalidRevenueDistributor(candidate) | Same error | Unchanged | Covered: [test_givenRevertingInterface_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L242) |
| BLCRD-I04 | ADMIN_ROLE holder | ERC165 malformed | BurnerLoans_InvalidRevenueDistributor(candidate) | Same error | Unchanged | Covered: [test_givenMalformedInterface_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L259) |
| BLCRD-D01 | ADMIN_ROLE holder | Reports another Kernel | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | Same error | Unchanged | Covered: [test_givenWrongKernel_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L276) |
| BLCRD-D02 | ADMIN_ROLE holder | Same Kernel; inactive and enabled | PolicyDependency_NotActive(candidate) | Same error | Unchanged | Covered: [test_givenInactiveEnabled_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L293) |
| BLCRD-D03 | ADMIN_ROLE holder | Same Kernel; active and disabled | PolicyDependency_NotActive(candidate) | Same error | Unchanged | Covered: [test_givenActivePaused_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L309) |
| BLCRD-D04 | ADMIN_ROLE holder | Same Kernel; inactive and disabled | PolicyDependency_NotActive(candidate) | Same error | Unchanged | Covered: [test_givenInactivePaused_whenValidatedAndSelected_reverts](./setRevenueDistributor.t.sol#L322) |

## Address and routing transitions

ADMIN caller, idle guards; positive pending obligations may already exist. Routing changes never move funds or erase liabilities.

| ID | Caller | Proposed address | Fee flag | Yield flag | Execution | Validator | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCRD-P01 | ADMIN_ROLE holder | Distinct active/enabled same-Kernel distributor | Fuzz false/true | Fuzz false/true | Success | Success | New pointer/event; pending fees follow new current route on retry | Covered: [test_givenValidDistributor_whenSelected_thenOnlyPointerChanges](./setRevenueDistributor.t.sol#L24) ; [test_givenFeeRouting_whenDistributorReplaced](./setRevenueDistributor.t.sol#L54) |
| BLCRD-P02 | ADMIN_ROLE holder | Current nonzero valid distributor | Fuzz false/true | Fuzz false/true | BurnerLoans_UnchangedAddress(candidate) before dependency reads | Success | Unchanged | Covered: [test_givenCurrentDistributor_whenSelected_revertsBeforeReadiness](./setRevenueDistributor.t.sol#L115) |
| BLCRD-P03 | ADMIN_ROLE holder | 0, previously nonzero | false | false | Success | BurnerLoans_RevenueDistributorRequired() | Pointer cleared/event; pending buckets preserved | Covered: [test_givenBothFlagsFalse_whenDistributorCleared_thenOnlyPointerChanges](./setRevenueDistributor.t.sol#L138) |
| BLCRD-I05 | ADMIN_ROLE holder | 0, previously nonzero | true | false | BurnerLoans_RevenueDistributorRequired() | Same error | Unchanged | Covered: [test_givenFeeRouting_whenDistributorCleared_reverts](./setRevenueDistributor.t.sol#L154) |
| BLCRD-I06 | ADMIN_ROLE holder | 0, previously nonzero | false | true | BurnerLoans_RevenueDistributorRequired() | Same error | Unchanged | Covered: [test_givenYieldRouting_whenDistributorCleared_reverts](./setRevenueDistributor.t.sol#L160) |
| BLCRD-I07 | ADMIN_ROLE holder | 0, previously nonzero | true | true | BurnerLoans_RevenueDistributorRequired() | Same error | Unchanged | Covered: [test_givenBothRoutes_whenDistributorCleared_reverts](./setRevenueDistributor.t.sol#L167) |
| BLCRD-I08 | ADMIN_ROLE holder | 0, already unset | false | false | BurnerLoans_UnchangedAddress(0) | BurnerLoans_RevenueDistributorRequired() | Unchanged | Covered: [test_givenUnsetDistributor_whenZeroSelected_revertsAsUnchanged](./setRevenueDistributor.t.sol#L174) |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCRD-L05 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins](./setRevenueDistributor.t.sol#L352) |
