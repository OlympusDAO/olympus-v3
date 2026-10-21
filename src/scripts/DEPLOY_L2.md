# Deployment Instructions - L2

This file contains instructions for deploying the different components of the Olympus protocol on L2 chains.

## Deploy

A Bophades installation can be deployed by following these steps:

1. Configure a Foundry RPC alias and the chain's DAO and emergency multisigs in `src/scripts/env.json`.
   Set `current.<chain>.external.ccip.RMN` and `Router` to the confirmed Chainlink infrastructure addresses.
   The script checks both entries before it starts deploying contracts.
   Set `olympus.config.CCIPTokenPoolConfig.gracePeriod` and `timelockDelay` in seconds.
2. Export the RPC credentials, or use the normal `.env`. A chain-specific `--env <file>` is optional.
3. Use a `cast wallet` account with `--account <account>`, or a Ledger with `--ledger <mnemonic-index>`.
4. Run the deployment:

    ```bash
    ./shell/L2/deploy.sh --chain <rpc-alias> --account <account> --ohm true --broadcast true --verify true
    ```

    - Omit `--broadcast true` to preview without sending transactions.
    - `--ohm true` deploys both Authority and OHM. `--ohm false` reuses their registry addresses.
    - The deployment creates the core, `CCIPBurnMintTokenPool`, `CCIPCrossChainBridge`, `CCIPTokenPoolConfig`, and `CCIPTokenPoolConfigTimelock`.
    - The pool, config policy, and timelock are activated in the Kernel. All four CCIP contracts remain disabled until configured.
    - `--verify true` submits source verification to both Etherscan and Sourcify after deployment.
    - Set `ETHERSCAN_API_KEY` (or `ETHERSCAN_KEY`). Select one provider with `--verifier etherscan` or `--verifier sourcify`; the default is `both`.

5. After a successful broadcast, the wrapper records the deployed addresses in `src/scripts/env.json`.
   Solidity records each deployed address with its registry key in the broadcast return value.
   After Forge succeeds, the wrapper saves these values through `write_deployment.sh`, then formats and checks the timestamped broadcast artifact and `env.json` with Prettier.
   Review those files before running the role scripts. Previews leave `env.json` unchanged.

This will deploy the contracts and install them into the kernel.

All three wrappers use `FOUNDRY_PROFILE=deploy` and accept the same `--chain`, `--account`/`--ledger`, and optional `--env` arguments.
The legacy `CHAIN` and `RPC_URL` environment variables remain supported when `--chain` is omitted.

### Robinhood deployment

The `robinhood` RPC alias uses `ALCHEMY_API_KEY`. The chain ID is **4663**.
Use Ledger mnemonic index **5**:

```bash
# Preview: no transactions or explorer submissions.
./shell/L2/deploy.sh --chain robinhood --ledger 5 --ohm true

# Deploy core and CCIP contracts, install modules and policies, and verify sources on both providers.
./shell/L2/deploy.sh --chain robinhood --ledger 5 --ohm true --broadcast true --verify true
```

Both providers are attempted even if one fails. Sourcify-only verification requires no Etherscan API key.
Etherscan uses its V2 endpoint with `chainid=4663` for Robinhood.
No separate `.env.robinhood` is required. No staking, Distributor, sOHM, or gOHM deployment is required.
The core creates Authority, OHM, Kernel, MINTR, ROLES, TRSRY, RolesAdmin, Emergency, and TreasuryCustodian.
The same command also creates the four CCIP contracts, for **thirteen contracts** in total.
Robinhood's existing configuration uses a 259200-second re-enable grace period and an 86400-second timelock delay.
It does not deploy the legacy LayerZero bridge or a canonical lock/release pool.

Robinhood's CCIP Router, RMN proxy, chain selector, and TokenAdminRegistry are populated in `env.json`
from the [official Chainlink directory](https://docs.chain.link/ccip/directory/mainnet/chain/robinhood-mainnet).
The wrapper records all thirteen confirmed addresses in `current.robinhood.olympus` before returning.
It stores the pool at `policies.CCIPBurnMintTokenPool` and the bridge at `periphery.CCIPCrossChainBridge`.
It stores the configuration contracts at `policies.CCIPTokenPoolConfig` and `policies.CCIPTokenPoolConfigTimelock`.
Leave `policies.CrossChainBridge` absent or zero; the role scripts skip its grants and transfers in that case.
Preserve the deployment manifest in `broadcast/L2Deploy.s.sol/4663/` before running another entrypoint from this script.

```bash
./shell/L2/grantRoles.sh --chain robinhood --ledger 5 --broadcast true
./shell/L2/handoff.sh --chain robinhood --ledger 5 --broadcast true
```

Confirm and execute the acceptance proposal created by `handoff.sh`, as described under Handoff below.
The existing role script gives both `emergency_shutdown` and `emergency_restart` to the configured Emergency Safe.
When a CCIP pool is recorded, it also grants `admin` to the DAO Safe and `emergency` to the Emergency Safe.
These shared roles control the pool's enabled state. The periphery bridge uses its owner for enabling and disabling.

The handoff script transfers the CCIP periphery bridge to the DAO Safe and proposes the DAO Safe as pool owner.
The DAO accepts pool ownership during the initial handoff. The deployer then retains no direct administrative access.
Before the CCIP readiness gate, the DAO nominates the configuration policy as pool owner.
The later `CCIPNonEthereumSetupBatch.setup` accepts that ownership through the configuration policy and binds its timelock.
CCIP registration, remote routes, rate limits, and enabling remain separate setup work; deployment alone does not enable bridging.
Follow [the CCIP runbook](../../documentation/bridge/ccip/RUNBOOK.md) and [Robinhood checklist](../../documentation/bridge/ccip/ROBINHOOD_PENDING.md).
The setup batch skips policies already active in the Kernel. Do not run a second CCIP deployment sequence after this command.

If source verification fails after successful transactions, preserve the deployment manifest and retry
the same deployment command with `--resume true --verifier etherscan` or `--resume true --verifier sourcify`.
Omit `--verifier` to retry both. The wrapper requires `--broadcast true` with `--verify true`.
Resume processes the saved transaction sequence; confirmed transactions are not sent again. After success, the wrapper records addresses and formats the artifacts.
Do not start a fresh deployment to retry verification.
Direct calls to the Solidity entrypoint bypass this wrapper step. Use `shell/L2/deploy.sh` for automatic recording and formatting.

## Grant Roles

The `grantRoles.sh` script can be used to grant the roles and ownership to facilitate initial setup.

```bash
./shell/L2/grantRoles.sh --account <account> --env <env-file> --broadcast true
```

## Legacy Bridge Setup

This section and Bridge Testing apply to existing legacy bridge installations, separately from core deployment.
Run `setupBridge.sh` for each remote chain the existing CrossChainBridge should trust. Perform this on both chains.

An example with Base and Optimism is shown below:

1. Setup the bridge on Optimism to trust messages from the Base CrossChainBridge. This should be run using the deployer account.

    ```bash
    ./shell/L2/setupBridge.sh --account MyAccount --localChain optimism --remoteChain base --env .env.optimism
    ```

2. Setup the bridge on Base to trust messages from the Optimism CrossChainBridge. This should be run using an address with the `bridge_admin` role on Base (likely the deployer account).

    ```bash
    ./shell/L2/setupBridge.sh --account MyAccount --localChain base --remoteChain optimism --env .env.base
    ```

In a situation where the "bridge_admin" role has been assigned to a multisig, the `setupBridge.sh` script will not be able to submit SAFE batches at the current time. The `CrossChainBridge.setTrustedRemoteAddress()` function will need to be called for each remote chain. An example of this is in [TrustBerachainBridge.s.sol](ops/batches/TrustBerachainBridge.sol).

## Bridge Testing

Once the bridges have been set up, actions can be performed to test the bridge.

1. Obtain some OHM on the source chain
    - If the source chain is a testnet, the `./shell/mint/mint.sh` script can be used to mint OHM.
2. Send the OHM to the destination chain

    ```bash
    ./shell/bridge.sh --fromChain base --toChain optimism --to <recipient-address> --amount <amount> --account <account> --broadcast true --env .env.base
    ```

3. Send the OHM back to the source chain

    ```bash
    ./shell/bridge.sh --fromChain optimism --toChain base --to <recipient-address> --amount <amount> --account <account> --broadcast true --env .env.optimism
    ```

While the transactions are in flight, the transaction hash that is output can be inserted into LayerZero Scan to view the progress of the bridging transaction.

## Handoff

The last step in the deployment is to transfer the ownership of the installation to the DAO multisig. This is done by running the `handoff.sh` script.

```bash
./shell/L2/handoff.sh --account MyAccount --env .env.optimism --broadcast true
```

This should be run using the deployer account.

After a successful broadcast, `handoff.sh` runs `L2HandoffBatch.acceptHandoff` through the existing Safe batch wrapper.
It simulates, signs, and proposes one Safe transaction containing `RolesAdmin.pullNewAdmin()` and `CCIPBurnMintTokenPool.acceptOwnership()`.
The signing wallet must also be a DAO Safe owner. Ledger and `cast wallet` accounts are supported.
Confirm and execute that proposal in the DAO Safe. Proposing alone does not transfer ownership.
The batch checks accepted ownership during simulation and skips transfers already accepted by the DAO.
A handoff preview creates no Safe proposal because the pending transfers have not been broadcast.

To preview or retry only the acceptance proposal, use:

```bash
./shell/safeBatchV2.sh --contract L2HandoffBatch --function acceptHandoff --chain robinhood --multisig true --ledger 5
./shell/safeBatchV2.sh --contract L2HandoffBatch --function acceptHandoff --chain robinhood --multisig true --ledger 5 --broadcast true
```

Use `--account <account>` instead of `--ledger 5` for a Cast account.
The deployer remains RolesAdmin administrator and pool owner until the DAO executes the proposal.
Authority role transfers and CCIP periphery bridge ownership transfer are immediate and need no acceptance calls.

Before the CCIP readiness gate, nominate the configuration policy from the DAO Safe:

```bash
./shell/safeBatchV2.sh --contract CCIPTokenPoolBatch --function transferTokenPoolOwnershipToConfig --chain robinhood --multisig true --ledger 5 --broadcast true
```

Execute that Safe proposal before building `CCIPNonEthereumSetupBatch.setup`.
The setup batch accepts pool ownership through `CCIPTokenPoolConfig.acceptPoolOwnership()`.
The DAO remains pool owner until that acceptance. The deployer is not needed for either step.

## Verification

Source verification on both Etherscan and Sourcify is handled by `deploy.sh --verify true`.
The providers are called directly; successful forwarding from Sourcify is not required.
To retry Robinhood verification on Etherscan after a Sourcify limit, use:

```bash
./shell/L2/deploy.sh --chain robinhood --ledger 5 --ohm true --broadcast true --verify true --resume true --verifier etherscan
```

Use `--verifier sourcify` to retry Sourcify alone, or omit the flag to run both.
The deployment addresses are recorded before verification, so a verifier failure does not leave the registry empty.

Final state checks remain necessary: confirm the DAO Kernel executor, accepted RolesAdmin admin, Authority holders,
MINTR vault, emergency and custodian roles, installed modules, active policies, and zero initial OHM supply.
Also confirm the pool, config policy, and timelock are active Kernel policies, the periphery bridge owner is the DAO Safe,
and the DAO owns the pool after initial acceptance. Before setup, the DAO nominates the configuration policy as its successor.
All four CCIP contracts remain disabled before setup.

After the DAO executes both acceptance calls, run the read-only ownership verifier:

```bash
./shell/L2/verify.sh --chain robinhood
```

The verifier reads contract and multisig addresses from `env.json`.
It uses the saved broadcast only to identify the deployer and ROLES creation block.
The default is `broadcast/L2Deploy.s.sol/<chain-id>/deploy-latest.json`.
Use `--deployment <timestamped-run.json>` to select a committed broadcast instead.
The broadcast must match the RPC chain and the ROLES address in `env.json`, with a successful creation receipt.
The creation block bounds the role-history scan: ROLES can check a named role but cannot enumerate all roles held by an address.
No wallet or Ledger is needed. This checks live state; the acceptance batch checks its simulated outcome.

The report shows `[PASS]` and `[FAIL]` for each ownership check and exits nonzero on an incomplete handoff.
It checks Kernel execution, current and pending RolesAdmin and Authority assignments, pool ownership and rate-limit administration,
periphery ownership, the configuration operator, and current and pending TokenAdminRegistry administration.
It checks every role ever granted to the deployer since ROLES creation, including unexpected roles, against current role membership.
A missing ROLES creation receipt or an RPC error prevents a passing report.

The pool can be owned by the DAO, pending to the configuration policy, or owned by the configuration policy.
Run the verifier again after CCIP setup and finalization. A passing report proves the checked state at its printed RPC block.
It does not prevent a later governance transaction from granting new access.
A deployer can remain one of the Safe signers. The check rejects direct administrative authority, not membership in a threshold Safe.

Commit the timestamped broadcast artifacts and the updated `env.json` after deployment.
