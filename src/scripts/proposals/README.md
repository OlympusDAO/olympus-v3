# OCG Proposals

This directory contains scripts for submitting proposals to the Olympus Governor.

## Environment

The following are required:

- `bash` shell
- A [foundry](https://getfoundry.sh/) installation
- A `.env` file with the following environment variables:
    - `ALCHEMY_API_KEY`: The API key for the Alchemy RPC endpoint.

## Creating a Proposal Script

The OCG proposal must have a separate contract that inherits from `ProposalScript`. See the `ContractRegistryProposal` for an example.

## Fork Testing

It is possible to test proposal submission (and execution) on a forked chain. Two options are available: Tenderly VNet or local Anvil fork.

### Tenderly VNet

1. Create a fork of the chain you wish to test on using Tenderly.
2. Create an environment file (e.g., `.env.tenderly`) and set the environment variables.
    - `RPC_URL`: Your fork's RPC URL.
    - `TENDERLY_ACCOUNT_SLUG`: Your Tenderly account slug.
    - `TENDERLY_PROJECT_SLUG`: Your Tenderly project slug.
    - `TENDERLY_VNET_ID`: Your Tenderly vNet ID. This is the random string in the URL of the testnet in the Tenderly dashboard. It is NOT the same as the random string in the `RPC_URL`. e.g. `https://dashboard.tenderly.co/{TENDERLY_ACCOUNT_SLUG}/{TENDERLY_PROJECT_SLUG}/testnet/{TENDERLY_VNET_ID}`
    - `TENDERLY_ACCESS_KEY`: Your Tenderly access key.
3. Configure a wallet with `cast wallet`
4. Fund your chosen wallet with gOHM
    - On Tenderly, this can be done using the "Fund Account" button in the dashboard.
5. Delegate your gOHM voting power to your wallet address.
    - This can be done by running `./delegate.sh` with the appropriate arguments, or through the Tenderly dashboard.
6. Submit your proposal by running `./submitProposal.sh` with the appropriate arguments.
    - Use `--chain <rpc-url>` to specify the fork's RPC URL.
7. Alternatively, you can execute the proposal (as if the proposal has passed) by running `./executeOnTenderly.sh` with the appropriate arguments.

### Local Anvil Fork

1. Start an Anvil fork:

    ```bash
    pnpm run anvil:fork
    ```

2. Create an environment file (e.g., `.env.anvil`) with:
    - `RPC_URL`: `http://localhost:8545` (or omit to use the default)
3. Deal gOHM to your wallet and set up voting checkpoint:

    ```bash
    ./shell/anvil/deal_gohm.sh <your_wallet_address>
    ```

4. Submit your proposal by running `./submitProposal.sh` with the appropriate arguments.
    - Use `--chain http://localhost:8545` to specify the local Anvil RPC.
5. Execute the proposal by running `./executeOnAnvilFork.sh` with the appropriate arguments.

## Submitting a Proposal

1. Configure a wallet with `cast wallet`
2. Delegate your gOHM voting power to your wallet address.
    - This can be done by running `./delegate.sh` with the appropriate arguments, or through the Tenderly dashboard.
3. Submit your proposal by running `./submitProposal.sh` with the appropriate arguments.
    - Using a cast wallet:

        ```bash
        ./src/scripts/proposals/submitProposal.sh \
            --file src/proposals/ContractRegistryProposal.sol \
            --contract ContractRegistryProposalScript \
            --account my_wallet \
            --chain mainnet \
            --broadcast true \
            --env .env
        ```

    - Using a Ledger:

        ```bash
        ./src/scripts/proposals/submitProposal.sh \
            --file src/proposals/ContractRegistryProposal.sol \
            --contract ContractRegistryProposalScript \
            --ledger 0 \
            --chain mainnet \
            --broadcast true \
            --env .env
        ```
