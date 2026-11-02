# BurnerLoansCollateral.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/abstracts/BaseBurnerLoansAction.sol#L123). Test mappings name the passing proofs.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope: `BLCOL-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: ROLES; no version validation in BaseBurnerLoansAction.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCOL-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Covered: [test_givenReplacementRoles_whenConfigured_thenCachedPointerRefreshes](configureDependencies.t.sol#L19), [test_givenUnvalidatedModuleMajor_whenFirstAndRepeatedConfiguration_thenNoVersionRead](configureDependencies.t.sol#L41), [test_whenDependenciesConfigured_thenRolesIsResolved](configureDependencies.t.sol#L92) |

## Missing module

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCOL-DEPENDENCIES-P02 | Fuzz all callers | Required ROLES module absent | Policy_ModuleDoesNotExist(ROLES) | Covered: [test_givenMissingRoles_whenConfigured_thenPreviousCachePreserved](configureDependencies.t.sol#L69) |

## Module-version independence

BaseBurnerLoansAction does not validate or read the ROLES major version. This is independent of missing-module rejection.

| ID | Caller | Module state | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-DEPENDENCIES-P03 | Fuzz all callers | Installed ROLES reports major/minor 255; fresh and repeated configuration | Success; ROLES keycode and current pointer | No VERSION call; lifecycle and loan accounting preserved | Covered: [test_givenUnvalidatedModuleMajor_whenFirstAndRepeatedConfiguration_thenNoVersionRead](configureDependencies.t.sol#L41) |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.
