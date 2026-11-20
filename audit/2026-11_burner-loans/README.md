# Burner Loans Audit

## Purpose

Review the new Burner Loans system and its supporting custody, funding, pricing, revenue distribution, and configuration contracts. PriceCache, the oracle factories, DepositManager V1.0, and several shared abstractions have previous audit history.

Burner Loans accepts collateral (custodied in the DepositManager) and lends OHM against that collateral for a fixed term. Borrowers pay upfront fees rather than ongoing interest. Positions become seizable at maturity or when collateral no longer satisfies the health requirement. Vault yield belongs to the protocol and does not increase borrower collateral credit.

## Source And Comparison Baseline

| Reference | Value |
| --- | --- |
| Source branch | `feat/burner-loans` |
| Comparison branch | `develop` |
| Comparison commit | [`d8ec9bd5a93ae09fee8d3cc9f3c5b6c0a79498a1`](https://github.com/OlympusDAO/olympus-v3/commit/d8ec9bd5a93ae09fee8d3cc9f3c5b6c0a79498a1) |
| Package branch | `feat/burner-loans-audit` |
| Package date | 2026-11-10 |

From the checkout under review, compare the source with the fixed `develop` baseline:

```sh
git diff --find-renames d8ec9bd5a93ae09fee8d3cc9f3c5b6c0a79498a1 HEAD -- src
```

The scope includes the scoped-authorization implementation and the OCG launch proposal. [BurnerLoansProposal](../../src/proposals/BurnerLoansProposal.sol), [BurnerLoansActivator](../../src/proposals/BurnerLoansActivator.sol), and [IBurnerLoansActivator](../../src/proposals/interfaces/IBurnerLoansActivator.sol) are in scope. Deployment scripts and operations batch files remain excluded.

## Recommended Reading

| Document | What it explains |
| --- | --- |
| [Burner Loans](../../documentation/burner_loans.md) | Architecture, loan lifecycle, health calculations, fees, servicing, replacement, and activation order |
| [Burner Loans access control](../../documentation/burner_loans_access_control.md) | Settlement roles, user authorization, governance, lifecycle gates, and independent controllers |
| [Operator authorization](../../documentation/operator_auth.md) | Scoped grants, EOA/ERC-1271 signatures, transaction-local authority, epochs, and protected settlement |
| [FLOAN](../../documentation/floan.md) | Canonical markets and positions, debt episodes, indexes, aggregates, and export boundaries |
| [Inventory](../../documentation/burner_loans_inventory.md) | Provider claims, idle funding, principal, MINTR approval, and replacement limits |
| [DepositManager](../../documentation/deposit_manager.md) and [access control](../../documentation/deposit_manager_access_control.md) | V1.1 changes, custody modes, underlying/share denominations, caps, yield, and recovery |
| [Backing oracle](../../documentation/backing_oracle.md) | USD backing value, update bounds, notice period, and operator replacement |
| [PriceCache](../../documentation/price_cache.md) and [PriceCacherTask](../../documentation/price_cacher_task_access_control.md) | Pair snapshots, freshness, lifecycle, consumer fallback, and Heart warming |
| [RevenueDistributor](../../documentation/revenue_distributor.md) and [access control](../../documentation/revenue_distributor_access_control.md) | Token routes, pending obligations, payout retries, rescue, and automation |
| [Configuration queues](../../documentation/config_timelock_batch_queue.md) | Typed actions, conflict keys, state commitments, execution windows, and cancellation |
| [Launch parameters](../../documentation/burner_loans_launch_parameters.md) | Proposed asset settings and economic examples, subject to governance approval |
| [Launch runbook](../../documentation/burner_loans_launch_runbook.md) | Deployment prerequisites, proposal execution, activator bindings, and the actual Heart task order |
| [Role registry](../../ROLES.md) | Protocol-wide roles and intended holders |

The source defines behavior if a document differs from implementation. Tests and scenario documents are available as supporting material but are outside audit scope.

## Design And Contract Map

| Component | Entry points and responsibilities |
| --- | --- |
| [FLOAN](../../src/modules/FLOAN/) | Generic fixed-term loan ledger. Records markets, positions, debt, collateral, default totals, and indexes. It does not custody tokens or calculate product health. |
| [Core](../../src/policies/burnerloans/BurnerLoansCore.sol) | Permanent facility and DepositManager operator. Owns Auth selection/global epoch, the asset registry, service pointers, custody settlement, and canonical resulting-position checks. |
| [Collateral](../../src/policies/burnerloans/BurnerLoansCollateral.sol), [Debt](../../src/policies/burnerloans/BurnerLoansDebt.sol), and [Seize](../../src/policies/burnerloans/BurnerLoansSeize.sol) | Public action validation, previews, and execution. Debt handles borrowing, repayment, and extension. Actions call Core through operation-specific settlement roles. |
| [Risk](../../src/policies/burnerloans/BurnerLoansRisk.sol) | Prices, backing-floor health, market health, utilization fees, referral configuration, and keeper rewards. |
| [Inventory](../../src/policies/burnerloans/BurnerLoansInventory.sol) | Supplies OHM from idle provider funding and MINTR. Reconciles repayments, defaults, provider claims, and global debt capacity. |
| [Payout](../../src/policies/burnerloans/BurnerLoansPayout.sol) | Receives fees and seizure proceeds. Reserves liabilities before optional transfers, tracks deferred obligations, and selects fee/yield recipients. |
| [Config](../../src/policies/burnerloans/BurnerLoansConfig.sol) and the four Burner Loans configuration timelocks | Configure markets and separate Risk, Payout, and Inventory authorities. Concrete queues validate typed proposals and live execution state. |
| [Lens](../../src/policies/burnerloans/BurnerLoansLens.sol), [SeizerTask](../../src/policies/burnerloans/BurnerLoansSeizerTask.sol), and [YieldClaimerTask](../../src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol) | Position views, bounded liquidation scans, periodic seizure, and yield claims. |
| [Auth](../../src/policies/burnerloans/BurnerLoansAuth.sol), [OperatorAuth](../../src/policies/utils/OperatorAuth.sol), and [LoanActions](../../src/policies/burnerloans/libraries/LoanActions.sol) | Core-bound grant storage and validation, signatures, action masks, account/operator epochs, and delegated position limits. Auth has no independent Policy lifecycle or custody. |
| [DepositManager](../../src/policies/deposits/DepositManager.sol) and [its timelock](../../src/policies/deposits/DepositManagerConfigTimelock.sol) | Shared custody, receipt liabilities, vault shares, borrowing accounting, and delayed configuration. |
| [BackingOracle](../../src/policies/BackingOracle.sol), [its timelock](../../src/policies/BackingOracleConfigTimelock.sol), [PriceCache](../../src/policies/price/PriceCache.sol), and [PriceCacherTask](../../src/policies/PriceCacherTask.sol) | Backing storage and bounded updates, reusable price snapshots, and periodic warming. |
| [RevenueDistributor](../../src/policies/RevenueDistributor.sol), [its timelock](../../src/policies/RevenueDistributorConfigTimelock.sol), and [its task](../../src/policies/RevenueDistributorTask.sol) | Allocation of received tokens to repurchase/configured recipients and Treasury, delayed route changes, and periodic settlement. |
| [Proposal](../../src/proposals/BurnerLoansProposal.sol) and [Activator](../../src/proposals/BurnerLoansActivator.sol) | Governance role grants, one-use atomic launch, initial configuration, Heart insertion order, and temporary ADMIN revocation. |

Core authenticates settlement roles and trusts reviewed action contracts to forward the actual operator and apply economic checks. Auth validates scoped grants, and Core enforces resulting-position bounds under its shared settlement guard. Replacing an action preserves the facility, custody namespace, and grants on the selected Auth.

ADMIN retains direct authority alongside delegated configuration operators. The queues delay delegated changes, but they do not impose a delay on ADMIN itself. Core, Risk, Payout, Inventory, DepositManager, the backing oracle, and RevenueDistributor have distinct authority boundaries.

### Authorization And Launch

Auth owns grants and local cancellation epochs. Core owns the selected Auth and global epoch. Public actions capture that selection and the original grant stamp before external preparation. Core validates the same authority before and after settlement, then checks canonical FLOAN results.

Grants select deposit, borrow, withdraw, and extend actions with independent asset, recipient, and resulting-position limits. Accounts approve directly or sign EIP-712 grants for their designated operator to accept. Contract accounts use ERC-1271 on the signed path. Temporary grants last only for the accepting transaction. Reusable grants remain subject to inclusive deadlines, cancellation, and selection epochs. Auth replacement advances the global epoch and invalidates previous contexts.

The proposal grants permanent custody, action, automation, and DAO operational roles. It then grants the constructor-bound activator temporary ADMIN, calls its one-use launch, and revokes ADMIN in the same governance execution. The activator checks the immutable deployment graph, Kernel membership, fresh disabled state, backing, and required roles. It admits USDe to PRICE if absent and configures custody, Auth/services, markets, independent queues, revenue routes, and Heart tasks.

The launch prepends SeizerTask, YieldClaimerTask, and RevenueDistributorTask in that order, preserving the order of existing tasks. PriceCacherTask remains in review scope as a generic optional warmer, but this proposal does not install it in Heart. Price-dependent lending actions refresh the configured cache themselves.

## Scope

[scopefile.txt](./scopefile.txt) is the machine-readable list. It contains **92 Solidity files: 77 new files and 15 modified files**. Interfaces and libraries are included explicitly. Imports do not expand the list.

### New Files: Full Review

All 77 new files are in scope in full, including their integration with existing contracts:

- The three files under `src/modules/FLOAN/`.
- All Burner Loans policies, actions, tasks, timelocks, the action base, and libraries under `src/policies/burnerloans/`.
- Their interfaces under `src/policies/interfaces/burnerloans/`.
- `BurnerLoansAuth.sol`, `IBurnerLoansAuth.sol`, `IBurnerLoansAuthTarget.sol`, and `LoanActions.sol`.
- `BackingOracle.sol`, `BackingOracleConfigTimelock.sol`, and their interfaces.
- `PriceCacherTask.sol` and `IPriceCacherTask.sol`.
- `RevenueDistributor.sol`, `RevenueDistributorConfigTimelock.sol`, `RevenueDistributorTask.sol`, and their interfaces, including `IRevenueDistributorRescue` and `IYieldRepurchaseRecipient`.
- `DepositManagerConfigTimelock.sol`, `IDepositManagerConfigTimelock.sol`, `IDepositManagerV1_1.sol`, and `IAssetManagerV1_1.sol`.
- `OperatorAuth.sol`, `IOperatorAuth.sol`, `IKernel.sol`, `PolicyDependency.sol`, `SafeCallDecoder.sol`, and `SafeERC20Exact.sol`.
- `BurnerLoansProposal.sol`, `BurnerLoansActivator.sol`, and `IBurnerLoansActivator.sol`.

### Existing Files: Changes And Affected Integrations

The following 15 files are listed for review of changes relative to the pinned `develop` commit. Review the affected paths in context. Their inclusion does not request a complete repeat audit of unchanged code.

| Files | Changes to review |
| --- | --- |
| [BaseAssetManager.sol](../../src/bases/BaseAssetManager.sol) | Shared cap utilization across operators, exact incoming assets and vault shares, ERC-7575 share discovery, ERC-7540 capability handling, share withdrawals, immutable custody identities, and conversion behavior. |
| [DepositManager.sol](../../src/policies/deposits/DepositManager.sol) | V1.1 withdrawals and previews with explicit output assets. Reconciliation of liabilities, borrowing, and caps. Reentrancy protection, stricter operator setup, delegated configuration, recovery, and lifecycle changes. |
| [IDepositReceiptToken.sol](../../src/interfaces/IDepositReceiptToken.sol) | Removal of IERC20 inheritance. Receipt metadata and ERC-20 functionality now use separate interface surfaces. |
| [PriceCache.sol](../../src/policies/price/PriceCache.sol) and [IPriceCache.sol](../../src/interfaces/IPriceCache.sol) | The cache changes described in the next section. |
| [BaseOracleFactory.sol](../../src/policies/price/BaseOracleFactory.sol) and [ERC7726OracleFactory.sol](../../src/policies/price/ERC7726OracleFactory.sol) | Kernel-active mutation gates, guard ordering, rejection of unchanged cache pointers, shared canonical Kernel validation, and OpenZeppelin reentrancy-guard replacement. |
| [ChainlinkOracleFactory.sol](../../src/policies/price/ChainlinkOracleFactory.sol) and [MorphoOracleFactory.sol](../../src/policies/price/MorphoOracleFactory.sol) | Name construction uses OpenZeppelin `Strings` and `string.concat` instead of Solmate string conversion and packed encoding. Check immutable clone-data compatibility. |
| [ChainlinkOracleCloneable.sol](../../src/policies/price/ChainlinkOracleCloneable.sol), [MorphoOracleCloneable.sol](../../src/policies/price/MorphoOracleCloneable.sol), and [ERC7726OracleCloneable.sol](../../src/policies/price/ERC7726OracleCloneable.sol) | Checked `uint48` conversion for encoded max-age values, direct bytes32 name decoding, and OpenZeppelin 5.7.0 imports. Check unchanged pricing and freshness semantics. |
| [IOracleFactory.sol](../../src/policies/interfaces/price/IOracleFactory.sol) and [IERC7726OracleFactory.sol](../../src/policies/interfaces/price/IERC7726OracleFactory.sol) | New unchanged-pointer errors and removal of unused module-interface errors. |
| [RoleDefinitions.sol](../../src/policies/utils/RoleDefinitions.sol) | New Burner Loans, Inventory provider, DepositManager, RevenueDistributor, and backing-administration roles. |

### PriceCache Changes Since The Previous Audit

The PRICE v1.2 remediation tag provides the prior cache/factory snapshot. Between that tag and the pinned `develop` revision, these files differ only in their pragma declarations. The `develop` comparison therefore isolates the substantive Burner Loans integration changes.

- Replace `PolicyEnabler` with `PolicyEnablerV2` and `ReEnablerGracePeriod`. Add a seven-day initial recovery window, ADMIN-controlled grace changes, transition history, and empty lifecycle payload requirements.
- Require Kernel activity for metadata changes as well as cache operations. Enable and re-enable require membership, while disable remains available during Kernel inactivity.
- Add permissionless `validateAssetPair(asset, quote)`, independent of active/enabled state. It validates pair support and decimal metadata without reading or storing a price.
- Return the selected `CachedPrice` from `cachePriceIfNecessary`. Reuse the loaded snapshot for the stale check and return newly captured values directly after refresh.
- Preserve the exact constructor symbol length, including embedded zero bytes. Replace assembly packing with byte-wise packing and length-aware decoding.
- Refactor pair-key construction and update interface support, casts, and imports. Review preservation of pair orientation, epochs, invalidation, round IDs, timestamps, and freshness boundaries.

`PriceCacherTask` is new and is in scope in full. Consumer admission and fallback in BurnerLoansRisk are also new review work.

### Exclusions And Existing Dependencies

Tests, mocks, scenario documents, gas snapshots, simulations, CI, deployment tooling, and operations batch files are outside audit scope. This includes `DeployV3.s.sol`, saved deployment sequences, and the setup/operations batches under `src/scripts/`.

The proposal and its on-chain activator are included despite their deployment purpose. The [proposal address registry](../../src/proposals/addresses.json) and launch runbook supply reference inputs. Review their correspondence with the activator's immutable bindings and proposal actions. The registry is not a Solidity metrics input.

The former `BurnerLoansComposites.sol` and its interface were removed from the merged source and are absent from this scope. Bundler/adapter integration is separate work.

The following changed files have no product-logic edits and are excluded from the counted scope:

| Files | Diff classification |
| --- | --- |
| `src/Kernel.sol` | Interface extraction of `Actions` and `Keycode`, plus lint comments. No Kernel behavior changes. |
| `src/libraries/SafeCall.sol`, `src/policies/utils/PolicyAdminOptimized.sol`, `src/policies/interfaces/deposits/IDepositManager.sol` | Documentation or lint comments only |
| `src/policies/interfaces/utils/IConfigOperator.sol`, `src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol`, `src/policies/utils/ConfigTimelockBatchQueue.sol`, `src/policies/utils/ConfigTimelockKeyLib.sol` | Pragma changes only |
| `src/policies/utils/ConfigOperatorSingleStep.sol` | Pragma and lint-comment changes |
| `src/bases/EnablerV2.sol`, `src/bases/Rescueable.sol`, `src/policies/utils/TimelockBatchQueue.sol` | ERC165 dependency import changes, plus lint comments where present |
| `src/libraries/TransferHelper.sol` | Versioned import spelling, documentation, and lint comments |

Existing ROLES, MINTR, PRICE, TRSRY, receipt-token infrastructure, lifecycle/queue bases, and third-party libraries remain dependencies rather than separate full-review targets. Their use by the new code, concrete hook overrides, permissions, interface assumptions, and dependency-version compatibility are in scope. The Solidity dependency versions and remappings are recorded in `soldeer.lock` and `remappings.txt`.

## Previous Audits

| Audit | Relevance and source |
| --- | --- |
| PRICE v1.2, Guardian, May 2026 | Prior factory/oracle review and remediation review involving PriceCache. [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-05_Olympus_Price_Feed_Updates_Report.pdf), [audit package](../2026-03_price-feed-improvements/README.md). |
| Convertible Deposits, Guardian, September 2025 | Prior DepositManager and asset-management/custody code. [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2025-09_Convertible_Deposits-Guardian.pdf), [scope](../2025-09_convertible-deposits/scopefile.txt). |
| Convertible Deposits, Trust, October 2025 | Additional review of the existing deposit system. [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2025-10_Convertible_Deposits-Trust.pdf). |
| LayerZero bridge, Guardian, June 2026 | Shared lifecycle/re-enable abstractions. [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-06-Bridge.pdf), [audit package](../2026-03_lz-bridge-upgrade/README.md). |
| CCIP configuration and timelock, Cyfrin, October 2026 | Shared configuration-operator, conflict-key, and batch-queue abstractions. [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-10-16-cyfrin-olympus-ccip-exp-v2.0.pdf), [audit package](../2026-09_ccip-token-pool-config/README.md). |

The [protocol audit index](https://docs.olympusdao.finance/main/security/audits) contains the older Default Framework, PRICE, lending, and governance reports. The [2023 PRICE package](../2023-11_price-v2/README.md) records the earlier PRICE architecture reviews.

### PRICE Audit Tags

The local annotated tags resolve to the report's review commits. Their peeled revisions also match the remote tags:

| Tag | Commit |
| --- | --- |
| `audit-price-feed-resilience` | [`1b03f97fa84538c11d42bc4dceab577081cdd8e6`](https://github.com/OlympusDAO/olympus-v3/tree/1b03f97fa84538c11d42bc4dceab577081cdd8e6) |
| `audit-price-feed-resilience-fix` | [`ee1b8330d39a2829c975341187795a39ee8a195b`](https://github.com/OlympusDAO/olympus-v3/tree/ee1b8330d39a2829c975341187795a39ee8a195b) |

The report distinguishes main-review findings from remediation-review findings. It states that Guardian did not review fixes to findings uncovered during the remediation review. A remediation tag does not establish independent review of every later fix.

The Convertible Deposits tags provide additional historical comparison points: `audit-convertible-deposits`, `audit-convertible-deposits-remediations`, `audit-convertible-deposits-2`, and `audit-convertible-deposits-2-remediations`.

## Areas Requiring Particular Attention

1. **Settlement and ledger consistency.** Reconcile FLOAN positions and aggregates with DepositManager credit and custody, Inventory principal, and Payout obligations after every operation. Review rollback across failures and same-block borrow/repay restrictions.
2. **Custody and token denominations.** Review exact receipt, underlying credit versus vault-share output, rounding to zero, ERC-7575 external shares, and ERC-7540 redemption changes. Preserve operator isolation, cap utilization, and protection of managed assets during rescue.
3. **Health and fees.** Check decimal scales, overflow, rounding direction, market/backing requirement selection, utilization-based fees, referral splits, and keeper rewards. Compare previews with execution at the same state, including captured-price snapshots and debt-free paths.
4. **User and action authorization.** Review action-mask and canonical permission admission, resulting-position bounds, actual operator/recipient binding, EIP-712 hashing, and EOA/ERC-1271 signatures. Check accepting-transaction grants versus reusable grants, account/pair/global epochs, cancellation, Auth rotation, and immutable Core/Kernel binding. Verify original-context capture and revalidation across callbacks, including owner paths and final FLOAN-state checks.
5. **Lifecycle and servicing.** Distinguish local pause, Kernel inactivity, and asset origination closure. Review enable/reEnable prerequisites, grace boundaries, exits during wind-down, authorization revocation, and recovery from replaced services.
6. **Dependency identity and pricing.** Check same-Kernel/Core/OHM binding, supported interfaces and versions, canonical ABI decoding, cache admission/fallback, and backing availability. Review PRICE upgrade behavior, cached source age, metadata invalidation, and the prior report's acknowledged cache/freshness assumptions.
7. **Configuration timelocks.** Review typed selector/payload admission, authority, immutable destinations, conflict keys, committed pre-state, operator rotation, atomic batches, cancellation, and exact execution/expiry boundaries. Direct ADMIN changes can invalidate pending actions.
8. **Inventory funding and loss.** Review provider claims, idle-funding priority, global cap and mint approval, defaults, repayment burns, and failure recovery. Donations must not create provider claims or lending capacity.
9. **Fees, seizure proceeds, and revenue.** Review reserve solvency, failed optional transfers, recipient overlap, fixed versus current destinations, retries, route retirement, and authorized liability rescue. Old Payout instances retain their obligations after replacement.
10. **Backing updates.** Review initial values, bounded updates, tiny-value rounding, upper-bound overflow, repeated changes, the fixed notice period, and emergency cancellation. Risk interprets backing as 18-decimal USD per OHM.
11. **Automation and replacement.** Review Heart ordering, gas reserves, bounded scans, borrower-list compaction, cursor progress, and isolation of failures. Check action replacement and Config's atomic market-manager handoff. Nonzero Inventory replacement requires a separately reviewed migration procedure.
12. **OCG proposal and activator.** Review deployment identities, one-use activation, fresh-state prerequisites, authority, initial custody/market settings, and independent controller bindings. Check atomic temporary ADMIN grant/revocation, USDe PRICE admission, Governor action limits, and exact Heart insertion order. Include Auth selection before Core enablement, deployed PRICE compatibility, and continued isolation of existing DepositManager V1.0 facilities.

## nSLOC Report

[solidity-metrics.html](./solidity-metrics.html) is generated by **SCC 4.1.0 through the repository's current metrics adapter**. The filename follows the existing audit-package convention. The deprecated Solidity Metrics generator is not used.

| Review category | Files | Whole-file nSLOC |
| --- | --- | --- |
| New files, full review | 77 | 10,370 |
| Existing files, changes and affected integrations | 15 | 2,299 |
| Total | 92 | 12,669 |

The adapter normalizes each function declaration to one line, including interface declarations. SCC excludes blank and comment-only lines. Constructors and modifiers retain their formatting. The report's `Code`/`SLOC` values represent nSLOC under this method. See [METRICS.md](../../documentation/METRICS.md) for the counting rules.

The report counts every listed file in full, including the 15 change-only review targets. Its total is therefore a whole-file count for the selected scope, not the number of newly written or modified lines. Tests, transitive imports, deployment scripts, and operations batch files are not counted. The proposal, activator, and activator interface are counted.

With the repository dependencies installed, Node.js 24+, the pinned pnpm version, and SCC 4.1.0 on PATH, run:

```sh
pnpm metrics --scope audit/2026-11_burner-loans/scopefile.txt --output audit/2026-11_burner-loans/solidity-metrics.html
```

The equivalent adapter invocation is:

```sh
node shell/metrics.js --scope audit/2026-11_burner-loans/scopefile.txt --output audit/2026-11_burner-loans/solidity-metrics.html
```

## Final Scope Freeze

- [x] Compare Burner Loans with the fixed `develop` baseline.
- [x] Record prior audit reports and verify the PRICE audit tags.
- [x] Separate full-review files, change-only targets, and mechanical exclusions.
- [x] Exclude tests, deployment scripts, and operations batch files.
- [x] Generate the SCC nSLOC report from the explicit scope.
- [x] Include the merged authorization implementation, OCG proposal, activator, and required interfaces.
- [x] Remove the deleted Composites implementation and interface.
- [x] Regenerate nSLOC from the reconciled scope.
