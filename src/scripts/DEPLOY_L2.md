# Deployment Instructions - L2

This file contains instructions for deploying the different components of the Olympus protocol on L2 chains.

## Deploy

A Bophades installation can be deployed by following these steps:

1. Configure a Foundry RPC alias and the chain's DAO and emergency multisigs in `src/scripts/env.json`.
2. Export the RPC credentials, or use the normal `.env`. A chain-specific `--env <file>` is optional.
3. Use a `cast wallet` account with `--account <account>`, or a Ledger with `--ledger <mnemonic-index>`.
4. Run the deployment:

    ```bash
    ./shell/L2/deploy.sh --chain <rpc-alias> --account <account> --ohm true --broadcast true --verify true
    ```

    - Omit `--broadcast true` to preview without sending transactions.
    - `--ohm true` deploys both Authority and OHM. `--ohm false` reuses their registry addresses.
    - The deployment creates the Bophades core. Bridge deployment is a separate operation.
    - `--verify true` submits source verification during deployment. Separate verification commands are unnecessary after success.
    - Verification explicitly selects Sourcify and requires no Etherscan API key.
5. Store the confirmed contract addresses in `src/scripts/env.json` before running the role scripts.

This will deploy the contracts and install them into the kernel.

All three wrappers use `FOUNDRY_PROFILE=deploy` and accept the same `--chain`, `--account`/`--ledger`, and optional `--env` arguments.
The legacy `CHAIN` and `RPC_URL` environment variables remain supported when `--chain` is omitted.

### Robinhood core

The `robinhood` RPC alias uses `ALCHEMY_API_KEY`. The chain ID is **4663**.
Use Ledger mnemonic index **5**:

```bash
# Preview: no transactions or explorer submissions.
./shell/L2/deploy.sh --chain robinhood --ledger 5 --ohm true

# Deploy, install modules, activate policies, and verify sources on Sourcify.
./shell/L2/deploy.sh --chain robinhood --ledger 5 --ohm true --broadcast true --verify true
```

All deployment wrappers pass `--verifier sourcify` when verification is enabled, including when an Etherscan key exists in the environment.
No separate `.env.robinhood` is required. No staking, Distributor, sOHM, or gOHM deployment is required.
The core creates Authority, OHM, Kernel, MINTR, ROLES, TRSRY, RolesAdmin, Emergency, and TreasuryCustodian.

Record all nine confirmed addresses in `current.robinhood.olympus` before continuing.
Leave `policies.CrossChainBridge` absent or zero; the role scripts skip its grants and transfers in that case.
Preserve the deployment manifest in `broadcast/L2Deploy.s.sol/4663/` before running another entrypoint from this script.

```bash
./shell/L2/grantRoles.sh --chain robinhood --ledger 5 --broadcast true
./shell/L2/handoff.sh --chain robinhood --ledger 5 --broadcast true
```

Complete the DAO Safe acceptance described under Handoff below.
The existing role script gives both `emergency_shutdown` and `emergency_restart` to the configured Emergency Safe.

If source verification fails after successful transactions, preserve the deployment manifest, confirm every receipt, and retry
the same deployment command with `--resume true`. Foundry requires `--broadcast true` with `--verify true`.
Resume processes the saved transaction sequence; confirmed transactions are not sent again. Do not start a fresh deployment to retry verification.

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

The DAO multisig must then call `RolesAdmin.pullNewAdmin()` to accept administration.
Use a Safe **Call** to the confirmed RolesAdmin address, with value **0** and calldata from:

```bash
cast calldata 'pullNewAdmin()'
```

The legacy `ops/batches/PullRolesAdmin.sol` helper does not support Robinhood. Use the direct Safe call there.
Authority role transfers are immediate and need no acceptance calls.

## Verification

Source verification on Sourcify is handled by `deploy.sh --verify true`.
Sourcify also forwards verification to supported explorers. Check RobinScan afterward; Etherscan's forwarding quota can prevent some submissions.
Use direct Etherscan verification only for contracts that remain unverified there.
Final state checks remain necessary: confirm the DAO Kernel executor, accepted RolesAdmin admin, Authority holders,
MINTR vault, emergency and custodian roles, installed modules, active policies, and zero initial OHM supply.

`shell/L2/verify.sh` contains historical Berachain/mainnet bridge checks. It is not a general deployment verifier;
do not run it for a Robinhood core deployment.
