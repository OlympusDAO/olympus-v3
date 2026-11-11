# BurnerLoansSeizerTask.addAsset coverage plan

Source: [addAsset](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L149). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-ADD-ASSET` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansSeizerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN; enabled/disabled and re-enabled states are allowed with usable ROLES. Own inactivity rejects before input validation. An asset must already be registered in the bound Core. Core activity/enablement and the asset's origination flag do not gate this registration read: paused markets can still have debt to seize.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-ADD-ASSET-A01 | Fuzz callers excluding every ADMIN holder | Any address, including zero/unregistered | ROLES_RequireRole(ADMIN_ROLE) before input checks | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-ADD-ASSET-I01 | ADMIN_ROLE holder | Zero address | BurnerLoansCore_AssetNotConfigured(address(0)) | No membership/event | Covered: [test][test_whenAssetIsZero_reverts] |
| BLSEIZ-ADD-ASSET-I03 | ADMIN_ROLE holder | Fuzz nonzero unregistered address; seed address(1), MAX160 and deployed unregistered contract | BurnerLoansCore_AssetNotConfigured(asset) | No membership, cursor or event | Covered: [test][test_whenAssetIsUnregistered_reverts], [test][test_whenUnregisteredAddressBoundaries_reverts] |
| BLSEIZ-ADD-ASSET-P01 | ADMIN_ROLE holder | Duplicate asset | AssetAlreadyManaged(asset) before any Core registration read | Registry, borrower cursor and events unchanged | Covered: [test][test_givenDuplicateAsset_whenAdded_reverts] |

## Successful execution

Fixed for this table: Accounting / events: No cursor change.

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-ADD-ASSET-I02 | Fuzz ADMIN_ROLE holder | Registered asset; task enabled, disabled or re-enabled | Add membership once, AssetAdded(asset) | Exact managed list; cursor zero; lifecycle unchanged; no Core mutation | Covered: [enabled][test_givenEnabled_whenAdminAddsRegisteredAsset], [disabled][test_givenDisabled_whenAdminAddsRegisteredAsset], [re-enabled][test_givenReEnabled_whenAdminAddsRegisteredAsset], [test][test_whenLifecycleStatesSeeded_thenRegisteredAssetAdded] |
| BLSEIZ-ADD-ASSET-P03 | ADMIN_ROLE holder | Registered asset; Core independently active/inactive and enabled/disabled | Admission succeeds without consuming an operational Core service | Membership added; lifecycle and positions unchanged | Covered: [test][test_givenCoreUnavailable_whenRegisteredAssetAdded] |
| BLSEIZ-ADD-ASSET-P04 | ADMIN_ROLE holder | Registered asset with originations disabled | Admission succeeds; existing loans remain manageable | Membership added; lifecycle and positions unchanged | Covered: [test][test_givenOriginationsDisabled_whenRegisteredAssetAdded] |

Co-located API assertions: `isAssetManaged`, `getAssets`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-ADD-ASSET-P02 | ADMIN_ROLE holder | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask); succeeds after reactivation | Registry unchanged on rejection | Covered: [test][test_givenInactiveTask_whenAssetAdded_reverts] |

## Test organization

[addAsset.t.sol](./addAsset.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.
[addAsset integration tests](./integration/addAsset.t.sol) retain the real dependency and accounting interactions.

[test_givenCoreUnavailable_whenRegisteredAssetAdded]: ./addAsset.t.sol#L113
[test_givenDuplicateAsset_whenAdded_reverts]: ./addAsset.t.sol#L38
[test_givenInactiveTask_whenAssetAdded_reverts]: ./addAsset.t.sol#L126
[test_givenOriginationsDisabled_whenRegisteredAssetAdded]: ./integration/addAsset.t.sol#L9
[test_whenAssetIsUnregistered_reverts]: ./addAsset.t.sol#L81
[test_whenAssetIsZero_reverts]: ./addAsset.t.sol#L69
[test_whenCallerIsUnauthorized_reverts]: ./addAsset.t.sol#L60
[test_whenLifecycleStatesSeeded_thenRegisteredAssetAdded]: ./addAsset.t.sol#L103
[test_whenUnregisteredAddressBoundaries_reverts]: ./addAsset.t.sol#L96

[test_givenEnabled_whenAdminAddsRegisteredAsset]: ./addAsset.t.sol#L19
[test_givenDisabled_whenAdminAddsRegisteredAsset]: ./addAsset.t.sol#L24
[test_givenReEnabled_whenAdminAddsRegisteredAsset]: ./addAsset.t.sol#L31
