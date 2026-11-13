# Burner Loans launch runbook

Use the approved [launch parameters](./burner_loans_launch_parameters.md). Commands simulate unless
`--broadcast true` is added after review. Use the configured `.env` and the mise-selected tools.

## 1. Deploy the components

The latest shared custody deployment is `olympus.policies.DepositManager` (v1.1). Preserve the
existing manager as `DepositManagerv1_0` and reuse ReceiptTokenManager. Existing v1.0 facilities
and their positions remain bound to the old manager. Record each confirmed deployment in
`src/scripts/env.json` before deploying its dependants.

| Order | Sequence in `src/scripts/deploy/savedDeployments/` | Deploys |
| --- | --- | --- |
| 1 | `backing_oracle.json` | BackingOracle and its configuration timelock |
| 2 | `deposit_manager_v1_1.json` | Shared DepositManager v1.1, using `deployDepositManager` |
| 3 | `price_cache.json` | USD PriceCache, 18 decimals |
| 4 | `revenue_distributor.json` | Distributor, configuration timelock and Heart task |
| 5 | `burner_loans.json` | FLOAN, lending contracts, timelocks, tasks, Auth, Lens and Activator |

```bash
./shell/deployV3.sh --sequence src/scripts/deploy/savedDeployments/backing_oracle.json --chain mainnet --account launch-deployer --env .env
```

Repeat for each sequence. Add `--broadcast true --verify true` only for the reviewed deployment.
The wrapper selects the `deploy` Foundry profile. Deployment does not activate or enable policies.
Auth deploys immediately after Core and is permanently bound to it and the trusted Kernel.
It is periphery, so it needs no Kernel policy activation, role or independent enable call.
OCG selects Auth on Core before enabling Core. Bundler deployment remains a TODO.
Oracle factories are not required: PriceCache reads PRICE directly.

## 2. Prepare Kernel membership

Use `KernelBatch` with the actual Kernel executor. If the executor is the OCG timelock, submit
these Kernel actions through governance. Create a reviewed args file, for example
`path/to/reviewed-kernel.json`, with ordered keys from the selected chain in `src/scripts/env.json`:

```json
{
  "functions": [
    {
      "name": "installModules",
      "args": {
        "targets": ["olympus.modules.OlympusFixedTermLoan"]
      }
    },
    {
      "name": "activatePolicies",
      "args": {
        "targets": [
          "olympus.policies.BackingOracle",
          "olympus.policies.BackingOracleConfigTimelock",
          "olympus.policies.DepositManager",
          "olympus.policies.RevenueDistributor",
          "olympus.policies.RevenueDistributorConfigTimelock",
          "olympus.policies.RevenueDistributorTask",
          "olympus.policies.BurnerLoansInventory",
          "olympus.policies.BurnerLoansPayout",
          "olympus.policies.BurnerLoansRisk",
          "olympus.policies.BurnerLoansCore",
          "olympus.policies.BurnerLoansConfig",
          "olympus.policies.BurnerLoansCollateral",
          "olympus.policies.BurnerLoansDebt",
          "olympus.policies.BurnerLoansSeize",
          "olympus.policies.BurnerLoansConfigTimelock",
          "olympus.policies.BurnerLoansRiskConfigTimelock",
          "olympus.policies.BurnerLoansPayoutConfigTimelock",
          "olympus.policies.BurnerLoansInventoryConfigTimelock",
          "olympus.policies.BurnerLoansSeizerTask",
          "olympus.policies.BurnerLoansYieldClaimerTask",
          "olympus.policies.PriceCache"
        ]
      }
    }
  ]
}
```

Every listed target is queued. Omit modules already installed and policies already active after
checking their addresses and state; duplicate or invalid operations fail Kernel simulation.
Use `upgradeModules` for reviewed module replacements and `deactivatePolicies` for policy removal.
The Kernel has no module-removal action.

For a Safe that is the current Kernel executor:

```bash
./shell/safeBatchV2.sh --contract KernelBatch --function installModules --chain mainnet --multisig true --ledger 5 --env .env --args path/to/reviewed-kernel.json
./shell/safeBatchV2.sh --contract KernelBatch --function activatePolicies --chain mainnet --multisig true --ledger 5 --env .env --args path/to/reviewed-kernel.json
```

Execute and confirm module installation before activating policies. Review simulations including
heartbeat validation, then add `--broadcast true` to submit the approved Safe proposals.

Keep all new launch policies, including BackingOracle and its queue, active but never enabled.
The OCG activator selects the backing queue, initializes the oracle to **$11.99 per OHM**
(`11_990_000_000_000_000_000`, 18 decimals), then enables the queue in the same transaction.
The DAO multisig has no ADMIN authority to call `enable` or `setConfigOperator`.
The proposal grants DAO `backing_admin` for delayed updates and grace-period recovery.
Heart and PriceConfigv2 must be active and enabled; PRICE must already support OHM and USDS.

### Timelock wiring checklist

All six queues are policies activated in the Kernel. Their immutable target and the target's
`configOperator` must agree. The activator selects and enables all six queues during OCG.

| Queue | Target | Deployment sequence | Kernel setup batch | Binding and enablement |
| --- | --- | --- | --- | --- |
| BurnerLoansConfigTimelock | BurnerLoansConfig | `burner_loans.json` | KernelBatch.activatePolicies | Activator |
| BurnerLoansRiskConfigTimelock | BurnerLoansRisk | `burner_loans.json` | KernelBatch.activatePolicies | Activator |
| BurnerLoansPayoutConfigTimelock | BurnerLoansPayout | `burner_loans.json` | KernelBatch.activatePolicies | Activator |
| BurnerLoansInventoryConfigTimelock | BurnerLoansInventory | `burner_loans.json` | KernelBatch.activatePolicies | Activator |
| RevenueDistributorConfigTimelock | RevenueDistributor | `revenue_distributor.json` | KernelBatch.activatePolicies | Activator |
| BackingOracleConfigTimelock | BackingOracle | `backing_oracle.json` | KernelBatch.activatePolicies | Activator |

OCG grants the DAO multisig `burner_loans_admin`, `backing_admin`,
`revenue_distributor_admin` and `burner_loans_inventory_provider`. The first three authorize
configuration queues and recovery; the provider role authorizes supplying/withdrawing OHM.
The DAO does not receive general `admin`; the activator's temporary `admin` is revoked before
proposal execution completes.

## 3. Review and execute OCG

Replace the zero-address entries for the new contracts in `src/proposals/addresses.json` with
reviewed deployment addresses. `olympus-policy-deposit-manager` is the new v1.1 manager;
`olympus-policy-deposit-manager-1_0` remains the old one. Check the activator's constructor
arguments against the deployment log and proposal addresses.

The activator admits USDe through existing PriceConfigv2 if it is not approved already. The
Chainlink and RedStone USDe/USD feeds must be no older than one day; the API3 reader must be no
older than 25 hours. Each feed must meet the $1 +/-1% admission bounds. The strict deviation
strategy then averages at least two valid prices after excluding 1% deviations; see the
[asset configuration](./price.md#assets). No DAO PRICE preparation batch or USDe args file is required. sUSDe is the
withdrawal output and needs no separate PRICE admission.

Rehearse the proposal and initial-configuration happy paths:

```bash
FOUNDRY_PROFILE=deploy FOUNDRY_SRC=src/test/proposals/BurnerLoansProposal.t.sol FOUNDRY_TEST=src/test/proposals/BurnerLoansProposal forge test --match-contract 'BurnerLoans(Proposal|Lifecycle)ForkTest' -vv
```

Review the actual deployed-address proposal inputs:

```bash
FOUNDRY_PROFILE=deploy ./src/scripts/proposals/printInputs.sh --file src/proposals/BurnerLoansProposal.sol --contract BurnerLoansProposalScript --chain mainnet --env .env
```

The proposal grants custody, settlement and automation roles, delegates DAO operational roles,
grants temporary activator ADMIN, executes the fixed launch and revokes activator ADMIN.
The activator initializes BackingOracle and its queue, configures USDe PRICE admission, USDS/sUSDS and USDe/sUSDe custody, lending markets,
Auth selection and service/config-timelock bindings, revenue routes and Heart tasks. Confirm the
resulting action list fits the Governor's 15-action limit and confirm the proposal identifier before submission.

```bash
./src/scripts/proposals/submitProposal.sh --file src/proposals/BurnerLoansProposal.sol --contract BurnerLoansProposalScript --account governance-proposer --chain mainnet --env .env
```

Add `--broadcast true` after approval. Complete voting, queueing and execution through OCG.

## 4. Heart ordering

The mainnet fork at block **25,973,712** has the following six tasks. The three new tasks run
after ConvertibleDepositFacility, ReserveMigrator and ReserveWrapper, immediately before Operator:
seize defaults, collect yield, then distribute the resulting receipts. Existing task order and
custom selectors are retained. Re-read the live list before approving deployment.

The activator hard-codes the six reviewed mainnet identities and selectors shown below. It does
not accept a deployer-supplied baseline or adopt Heart's live list as its expectation. At execution,
before launch configuration or fixed-index insertions, it requires the full task list to match.
Missing, extra, preinserted, reordered or replaced tasks and changed selectors revert with
`BurnerLoansActivator_InvalidPrerequisite(heart)`. The entire OCG transaction, including role grants
and the one-use flag, rolls back. If the live baseline legitimately changes, review the revised launch
ordering and update the activator before deployment; do not bypass the check.

<!-- prettier-ignore -->
| Existing index | Launch index | Task | Address at the fork block | Call |
| --- | --- | --- | --- | --- |
| 0 | 0 | ConvertibleDepositFacility | `0xEBDe552D851DD6Dfd3D360C596D3F4aF6e5F9678` | `execute()` |
| 1 | 1 | ReserveMigrator | `0x986b99579BEc7B990331474b66CcDB94Fa2419F5` | `migrate()` (`0x8fd3ab80`) |
| 2 | 2 | ReserveWrapper | `0xcA6cd4F0a0033f8C20cF68d6dF277E7001a386f9` | `execute()` |
| - | 3 | BurnerLoansSeizerTask | New deployment | `execute()` |
| - | 4 | BurnerLoansYieldClaimerTask | New deployment | `execute()` |
| - | 5 | RevenueDistributorTask | New deployment | `execute()` |
| 3 | 6 | Operator | `0x6417F206a0a6628Da136C0Faa39026d0134D2b52` | `operate()` (`0x7159a618`) |
| 4 | 7 | YieldRepurchaseFacility | `0x271e35a8555a62F6bA76508E85dfD76D580B0692` | `endEpoch()` (`0x0b9663db`) |
| 5 | 8 | EmissionManager | `0xA61b846D5D8b757e3d541E0e4F80390E28f0B6Ff` | `execute()` |

Heart updates PRICE's moving average before periodic tasks. Operator continues to read that
PRICE target. Burner Loans refreshes its OHM/USDS and OHM/USDe cache pairs during price-dependent
transactions; read-only previews fall back to PRICE. No separate price-cache periodic task is needed.

## 5. Confirm launch and operate

Confirm helper ADMIN was revoked, both custody/market configurations match the approved settings,
required Core action roles are present, configuration timelocks are selected and enabled, and the
Heart list matches the recorded order. The lifecycle fork suite tests deposit, borrow, extend,
repay, withdraw, seize, provider funding and automation under the unmodified launch settings.

Use the [operations index](../src/scripts/ops/README.md#burner-loans-and-shared-services) for the
standalone batches. Create args files when needed. Queuing and execution are separate runs;
`executeQueuedAction` and `cancelQueuedAction` take the actual `actionId`. Backing updates have
one-day notice and a seven-day execution window; lending/distributor queues use one and three days.
Use `EnablerBatch.disable` and `EnablerBatch.reEnable` for reviewed target lists. For all fourteen
Burner Loans contracts, use these orders (names below omit the `BurnerLoans` prefix):

- Disable: YieldClaimerTask, SeizerTask, Debt, Collateral, Seize, InventoryConfigTimelock,
  PayoutConfigTimelock, RiskConfigTimelock, ConfigTimelock, Config, Core, Risk, Payout, Inventory.
- Re-enable: Inventory, Payout, Risk, Core, Config, Collateral, Debt, Seize, ConfigTimelock,
  RiskConfigTimelock, PayoutConfigTimelock, InventoryConfigTimelock, SeizerTask, YieldClaimerTask.

Supply the resolved deployment addresses in `targets`. Disable also takes matching empty hex
payloads in `data`; initial enable takes each target's required payload. Restore any unavailable
shared dependencies first. Shared custody, oracle, distributor, cache and Heart have separate roles
and can use the same generic batch with their respective authorized caller.
