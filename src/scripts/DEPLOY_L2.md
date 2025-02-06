# Deployment Instructions - L2

This file contains instructions for deploying the different components of the Olympus protocol on L2 chains.

## Deploy

A Bophades installation can be deployed by following these steps:

1. Create a `.env.<CHAIN>` file for the new chain using the `.env.L2.example` file as a reference
2. Set up an account with `cast wallet`
3. Run the deployment:

    ```bash
    ./shell/L2/deploy.sh --account <account> --env <env-file> --broadcast true --verify true
    ```

    - Set `--broadcast` to `false` to run in simulation mode (recommended)
4. Store the addresses of the contracts in the `src/scripts/env.json` file for the new chain

This will deploy the contracts and install them into the kernel.

## Grant Roles

The `grantRoles.sh` script can be used to grant the roles and ownership to facilitate initial setup.

```bash
./shell/L2/grantRoles.sh --account <account> --env <env-file> --broadcast true
```

## Bridge Setup

The new chain installation will have a CrossChainBridge contract deployed. For each chain that it needs to interact with, the `setupBridge.sh` script should be run to trust messages from the remote chain. However, this needs to be performed on both chains.

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

## Verification

The `verify.sh` script can be used to verify the deployment.

```bash
./shell/L2/verify.sh --env .env.optimism
```
