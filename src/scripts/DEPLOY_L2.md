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

This will deploy the contracts, install them into the kernel, and set up the initial roles and ownership.

## Bridge Setup

The new chain installation will have a CrossChainBridge contract deployed. For each chain that it needs to interact with, the `setupBridge.sh` script should be run. However, this needs to be performed on both chains.

An example with Ethereum Mainnet and Optimism is shown below:

1. Setup the bridge on Optimism to trust messages from the Ethereum Mainnet CrossChainBridge. This should be run using the deployer account.

    ```bash
    ./shell/L2/setupBridge.sh --account MyAccount --localChain optimism --remoteChain mainnet --env .env.optimism
    ```

2. Setup the bridge on Ethereum Mainnet to trust messages from the Optimism CrossChainBridge. This should be run using an address with the `bridge_admin` role on Ethereum Mainnet. This is currently the DAO MS and OCG Timelock.

The `setupBridge.sh` script is not able to submit SAFE batches at the current time, so a batch will need to be submitted manually. The `CrossChainBridge.setTrustedRemoteAddress()` function will need to be called for each remote chain.

## Handoff

The last step in the deployment is to transfer the ownership of the installation to the DAO multisig. This is done by running the `handoff.sh` script.

```bash
./shell/L2/handoff.sh --account MyAccount --env .env.optimism --broadcast true
```

This should be run using the deployer account.
