# BurnerLoansConfig.setAssetWithdrawAsShares coverage plan

Source: [setAssetWithdrawAsShares](../../../policies/burnerloans/BurnerLoansConfig.sol#L315). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-WITHDRAW-SHARES` identifies this contract/function.

Implemented same-value rule: unchanged parameters return without setter writes/events after the concrete checks before equality. Changing-value rows exclude the current value; downstream checks reached only after equality are tested separately.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Fuzz permitted configuration caller: independently fuzz a nonzero address as ADMIN_ROLE holder, current selected configOperator without ADMIN_ROLE, or both. Guarantee ADMIN-only, operator-only and overlapping seeds. Caller choice is independent of lifecycle flags, inputs and dependency failures. Unauthorized fuzzing excludes all ADMIN_ROLE holders and the selected nonzero configOperator.

ADMIN or configOperator, Config enabled. asset must be configured; bool field `withdrawAsShares` changes through canonical FLOAN config plus Core compact mode sync. No grandfathering.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

All body inputs and component bindings are compatible unless the row states otherwise. Use the equivalent permitted-caller family above for each applicable row.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Core active: true; Core enabled: true.

The only permitted identities are every ADMIN_ROLE holder and the current nonzero configOperator. Fuzz the denied caller over EOAs and contracts excluding exactly those identities; retain zero unless it holds ADMIN. Seed a former operator, a BURNER_LOANS_ADMIN_ROLE-only holder, a borrower and an unrelated contract. All inputs are valid and changed, so authorization is the only varying condition.

| ID | Caller | Inputs / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-WITHDRAW-SHARES-A01 | Fuzz ADMIN-only, selected nonzero configOperator-only and overlap holders; guarantee each class | Valid changed setting; local/dependency admission satisfied | Success | Exact function-specific canonical update and event; preserve unrelated configuration and accounting | Covered: [test][test_givenAuthorizedCaller_whenSharesEnabled], [test][test_whenPermittedCallerClassesSeeded] |
| BLCFG-WITHDRAW-SHARES-A02 | Fuzz caller lacking ADMIN_ROLE and unequal to the selected nonzero configOperator | Same otherwise-valid request | NotAuthorised() before input validation or writes | Unchanged; no setter event, Core/FLOAN mutation or token movement | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle

Use a changed valid setting for this table. Same-value originations/withdraw-mode returns are tested separately with Config active, and do not require a downstream Core call. Proposed Core.registerMarket own-activity admission rejects Core inactivity after FLOAN writes; the whole transaction must roll back. Core local disablement rejects a changed mode through registerMarket; the complete transaction rolls back.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-WITHDRAW-SHARES-L01 | Fuzz permitted configuration caller | true | true | true | false | NotEnabled() from Core.registerMarket; earlier FLOAN writes roll back | Covered: [test][test_givenCoreDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L02 | Fuzz permitted configuration caller | true | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) from Core.registerMarket; earlier FLOAN writes roll back | Covered: [test][test_givenCoreInactive_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L03 | Fuzz permitted configuration caller | true | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) from Core.registerMarket; earlier FLOAN writes roll back | Covered: [test][test_givenCoreInactive_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L04 | Fuzz permitted configuration caller | true | false | true | true | NotEnabled() | Covered: [test][test_givenConfigActiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L05 | Fuzz permitted configuration caller | true | false | true | false | NotEnabled() | Covered: [test][test_givenConfigActiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L06 | Fuzz permitted configuration caller | true | false | false | true | NotEnabled() | Covered: [test][test_givenConfigActiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L07 | Fuzz permitted configuration caller | true | false | false | false | NotEnabled() | Covered: [test][test_givenConfigActiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L08 | Fuzz permitted configuration caller | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveEnabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L09 | Fuzz permitted configuration caller | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveEnabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L10 | Fuzz permitted configuration caller | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveEnabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L11 | Fuzz permitted configuration caller | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveEnabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L12 | Fuzz permitted configuration caller | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L13 | Fuzz permitted configuration caller | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L14 | Fuzz permitted configuration caller | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveDisabled_whenSharesChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-L15 | Fuzz permitted configuration caller | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveDisabled_whenSharesChanged_reverts] |

Unauthorized fuzz callers exclude ADMIN holders and the selected nonzero configOperator. The local enablement modifier precedes caller authorization. Assert unchanged state for rejection; re-enable/reactivate before retry and verify canonical positions survive. These Core lifecycle rows keep selected Inventory/Custody and required module permissions operational; their separate live failures are tested in the body.

## Withdrawal-mode validation

Config/Core active; Config enabled; configured asset. Use a changed mode except explicit unchanged rows. DM.getAssetConfiguration and validation use the actual selected vault; other market fields and existing positions are snapshotted.

| ID | Caller | DM custody mode | Old mode | Requested shares | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-WITHDRAW-SHARES-P01 | Fuzz permitted configuration caller | Direct custody; vault=0 | false | true | AssetManager_VaultRequired(asset) | Unchanged | Covered: [test][test_givenDirectCustody_whenSharesRequested_reverts] |
| BLCFG-WITHDRAW-SHARES-P02 | Fuzz permitted configuration caller | Synchronous redeemable vault | false | true | Success | FLOAN and Core both record shares; positions/principal unchanged | Covered: [test][test_givenAuthorizedCaller_whenSharesEnabled] |
| BLCFG-WITHDRAW-SHARES-P03 | Fuzz permitted configuration caller | Synchronous redeemable vault | true | false | Success | Both registries record underlying; existing loans use new exit mode | Covered: [test][test_givenSynchronousVaultInShareMode_whenUnderlyingRequested] |
| BLCFG-WITHDRAW-SHARES-P04 | Fuzz permitted configuration caller | Asynchronous redeem requires shares | false | true | Success | Both registries record shares | Covered: [test][test_givenVaultBecomesAsynchronous_whenSharesRequested] |
| BLCFG-WITHDRAW-SHARES-P05 | Fuzz permitted configuration caller | Asynchronous redeem requires shares | true | false | AssetManager_RequiresWithdrawAsShares(asset,vault) | Old share mode retained; no writes/events | Covered: [test][test_givenAsyncShareMode_whenUnderlyingRequested_reverts] |
| BLCFG-WITHDRAW-SHARES-P06 | Fuzz permitted configuration caller | Synchronous vault explicitly requires shares | false | true | Success | Both registries record shares | Covered: [test][test_givenExplicitShareRequirement_whenSharesEnabled] |
| BLCFG-WITHDRAW-SHARES-P07 | Fuzz permitted configuration caller | Vault explicitly requires shares | true | false | AssetManager_RequiresWithdrawAsShares(asset,vault) | Unchanged | Covered: [test][test_givenExplicitShareRequirement_whenUnderlyingRequested_reverts] |
| BLCFG-WITHDRAW-SHARES-P08 | Fuzz permitted configuration caller | DM asset configuration removed after listing | false | true | AssetManager_NotConfigured() | Unchanged | Covered: [test][test_givenDepositManagerAssetRemoved_whenModeChanged_reverts] |
| BLCFG-WITHDRAW-SHARES-P09 | Fuzz permitted configuration caller | DM dependencies later broken | false | false | Idempotent return before DM validation | No DM validation, module writes, registry writes or event; Config own admission still required | Covered: [test][test_givenBrokenDepositManagerAndSameUnderlying_whenModeSet] |
| BLCFG-WITHDRAW-SHARES-P10 | Fuzz permitted configuration caller | DM dependencies later broken | true | true | Idempotent return before DM validation | Same no-effect assertions | Covered: [test][test_givenBrokenDepositManagerAndSameShares_whenModeSet] |
| BLCFG-WITHDRAW-SHARES-P11 | Fuzz permitted configuration caller | Previously asynchronous vault now synchronous, no explicit share requirement | true | false | Success | Current DM capability determines exit mode; debt/collateral unchanged | Covered: [test][test_givenAsyncVaultBecomesSynchronous_whenUnderlyingRequested] |

## Invalid asset and downstream failures

| ID | Caller | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-WITHDRAW-SHARES-I01 | Fuzz permitted configuration caller | Unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | Unchanged | Covered: [test][test_whenAssetUnregistered_reverts] |
| BLCFG-WITHDRAW-SHARES-I02 | Fuzz permitted configuration caller | DM accepts mode; Core.registerMarket fails after FLOAN writes | Exact injected Core rejection | FLOAN/Core mode and events roll back together; positions unchanged | Covered: [test][test_givenRegistryWriteFails_whenModeChanged] |

## Shared assertions

Check getAssetConfig.withdrawAsShares and the compact Core market withdrawal mode independently after success; other fee/risk/term/cap fields unchanged. With populated loans, exercise an actual later withdrawal to confirm the selected return token/mode. Do not silently preserve the legacy same-value validation: current source returns before DM checks.

## Equality versus downstream admission

Config must be active/enabled and caller permitted in every case. A valid unchanged value returns before FLOAN writes and Core.registerMarket, so it can be a no-op while Core is inactive or disabled; a changed value still reaches Core own-activity admission. Do not copy the changed-value rejection into the no-op case. The numeric/struct validators explicitly run before equality for debt-cap, fee and risk setters; unchanged originations/withdrawal-mode values return before their mode-specific dependency checks. Keep existing valid struct/cap constraints and assert no writes/events on the equality path.

## Targeted writes and preservation

Config active/enabled; permitted ADMIN/configOperator caller; changed valid input. Seed unrelated fields to distinct nondefault values so a full-market replay or clobbered packed field is detectable.

| ID | Caller | Expected external writes | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLCFG-WITHDRAW-SHARES-D01 | Fuzz permitted configuration caller | FLOAN.setMarketConfigData for withdrawal mode, then Core.registerMarket with the same market ID and requested mode; reject every other FLOAN setter and every Core mutator except this registry synchronization if called | Success; exact canonical getter/event; preserve Other packed data, risk/fee/cap/originations, borrower positions and Inventory/Payout ledgers | Covered: [test][test_whenModeChanged] |

[test_givenAuthorizedCaller_whenSharesEnabled]: ./setAssetWithdrawAsShares.t.sol#L70
[test_whenCallerIsUnauthorized_reverts]: ./setAssetWithdrawAsShares.t.sol#L80
[test_givenCoreDisabled_whenSharesChanged_reverts]: ./setAssetWithdrawAsShares.t.sol#L90
[test_givenCoreInactive_whenSharesChanged_reverts]: ./setAssetWithdrawAsShares.t.sol#L104
[test_givenConfigActiveDisabled_whenSharesChanged_reverts]: ./setAssetWithdrawAsShares.t.sol#L120
[test_givenConfigInactiveEnabled_whenSharesChanged_reverts]: ./setAssetWithdrawAsShares.t.sol#L137
[test_givenConfigInactiveDisabled_whenSharesChanged_reverts]: ./setAssetWithdrawAsShares.t.sol#L154
[test_givenDirectCustody_whenSharesRequested_reverts]: ./setAssetWithdrawAsShares.t.sol#L172
[test_givenSynchronousVaultInShareMode_whenUnderlyingRequested]: ./setAssetWithdrawAsShares.t.sol#L188
[test_givenExplicitShareRequirement_whenSharesEnabled]: ./setAssetWithdrawAsShares.t.sol#L198
[test_givenExplicitShareRequirement_whenUnderlyingRequested_reverts]: ./setAssetWithdrawAsShares.t.sol#L210
[test_givenVaultBecomesAsynchronous_whenSharesRequested]: ./setAssetWithdrawAsShares.t.sol#L235
[test_givenAsyncShareMode_whenUnderlyingRequested_reverts]: ./setAssetWithdrawAsShares.t.sol#L253
[test_givenAsyncVaultBecomesSynchronous_whenUnderlyingRequested]: ./setAssetWithdrawAsShares.t.sol#L272
[test_givenDepositManagerAssetRemoved_whenModeChanged_reverts]: ./setAssetWithdrawAsShares.t.sol#L289
[test_givenBrokenDepositManagerAndSameUnderlying_whenModeSet]: ./setAssetWithdrawAsShares.t.sol#L311
[test_givenBrokenDepositManagerAndSameShares_whenModeSet]: ./setAssetWithdrawAsShares.t.sol#L334
[test_whenAssetUnregistered_reverts]: ./setAssetWithdrawAsShares.t.sol#L358
[test_givenRegistryWriteFails_whenModeChanged]: ./setAssetWithdrawAsShares.t.sol#L374
[test_whenModeChanged]: ./setAssetWithdrawAsShares.t.sol#L399
[test_whenPermittedCallerClassesSeeded]: ./setAssetWithdrawAsShares.t.sol#L428
