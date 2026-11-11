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

## 2. Prepare Kernel membership and backing

Use the actual Kernel executor for these independent setup batches. If the executor is the OCG
timelock, submit these Kernel actions through governance. Already-active policies are logged.

| Batch | Entry point | Prepares |
| --- | --- | --- |
| `BackingOracleSetupBatch` | `setupKernel` | Oracle and its queue |
| `DepositManagerSetupBatch` | `setupKernel` | Shared DepositManager v1.1 |
| `RevenueDistributorSetupBatch` | `setupKernel` | Distributor, queue and task |
| `BurnerLoansKernelSetupBatch` | `setupKernel` | FLOAN, fourteen Burner Loans policies and PriceCache |

For a Safe that is the current Kernel executor:

```bash
./shell/safeBatchV2.sh --contract DepositManagerSetupBatch --function setupKernel --chain mainnet --multisig true --ledger 5 --env .env
```

Repeat for the other setup contracts, review simulations including heartbeat validation, then add
`--broadcast true` to submit the approved Safe proposals. Execute and confirm these transactions.

The backing oracle is populated before the launch proposal. `BackingOracleBatch.initialize`
selects its deployed timelock, enables the oracle with `abi.encode(backing)`, and enables the queue.
It takes a reviewed positive `backing` value in 18 decimals from an args file and requires ADMIN.
Arrange this initial population through governance or an already-authorized administrator.
The launch proposal grants DAO `backing_admin`, so no separate operational role grant is needed.
Keep the remaining new launch policies active but never enabled until the proposal executes.
Heart and PriceConfigv2 must be active and enabled; PRICE must already support OHM and USDS.

### Timelock wiring checklist

All six queues are policies activated in the Kernel. Their immutable target and the target's
`configOperator` must agree. The backing queue is ready before OCG; the activator finishes the
other five bindings and enables those queues during OCG.

| Queue | Target | Deployment sequence | Kernel setup batch | Binding and enablement |
| --- | --- | --- | --- | --- |
| BurnerLoansConfigTimelock | BurnerLoansConfig | `burner_loans.json` | BurnerLoansKernelSetupBatch | Activator |
| BurnerLoansRiskConfigTimelock | BurnerLoansRisk | `burner_loans.json` | BurnerLoansKernelSetupBatch | Activator |
| BurnerLoansPayoutConfigTimelock | BurnerLoansPayout | `burner_loans.json` | BurnerLoansKernelSetupBatch | Activator |
| BurnerLoansInventoryConfigTimelock | BurnerLoansInventory | `burner_loans.json` | BurnerLoansKernelSetupBatch | Activator |
| RevenueDistributorConfigTimelock | RevenueDistributor | `revenue_distributor.json` | RevenueDistributorSetupBatch | Activator |
| BackingOracleConfigTimelock | BackingOracle | `backing_oracle.json` | BackingOracleSetupBatch | BackingOracleBatch.initialize before OCG |

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
Chainlink USDe/USD feed must be within the one-day freshness limit and the $1 +/-1% launch bounds
when this executes. No DAO PRICE preparation batch or USDe args file is required. sUSDe is the
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
The activator configures USDe PRICE admission, USDS/sUSDS and USDe/sUSDe custody, lending markets,
Auth selection and service/config-timelock bindings, revenue routes and Heart tasks. Confirm the
resulting action list fits the Governor's 15-action limit and confirm the proposal identifier before submission.

```bash
./src/scripts/proposals/submitProposal.sh --file src/proposals/BurnerLoansProposal.sol --contract BurnerLoansProposalScript --account governance-proposer --chain mainnet --env .env
```

Add `--broadcast true` after approval. Complete voting, queueing and execution through OCG.

## 4. Heart ordering

The mainnet fork at block **25,973,712** has the following six tasks. The new tasks are prepended:
seize defaults before collecting yield, then distribute the resulting receipts. Existing task
order and custom selectors are retained. Re-read the live list before approving deployment.

<!-- prettier-ignore -->
| Existing index | Launch index | Task | Address at the fork block | Call |
| --- | --- | --- | --- | --- |
| - | 0 | BurnerLoansSeizerTask | New deployment | `execute()` |
| - | 1 | BurnerLoansYieldClaimerTask | New deployment | `execute()` |
| - | 2 | RevenueDistributorTask | New deployment | `execute()` |
| 0 | 3 | ConvertibleDepositFacility | `0xEBDe552D851DD6Dfd3D360C596D3F4aF6e5F9678` | `execute()` |
| 1 | 4 | ReserveMigrator | `0x986b99579BEc7B990331474b66CcDB94Fa2419F5` | `migrate()` (`0x8fd3ab80`) |
| 2 | 5 | ReserveWrapper | `0xcA6cd4F0a0033f8C20cF68d6dF277E7001a386f9` | `execute()` |
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
