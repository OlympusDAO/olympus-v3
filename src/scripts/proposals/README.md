# OCG Proposals

This directory contains scripts for submitting proposals to the Olympus Governor.

## Fork Testing

It is possible to test proposal submission (and execution) on a forked chain. To do so, follow these steps:

1. Create a fork of the chain you wish to test on. Tenderly will be used in the examples.
2. Create an environment file (e.g., `.env.tenderly`) and set the `RPC_URL` environment variable to your fork's RPC URL.
3. Configure a wallet with `cast wallet`
4. Fund your chosen wallet with gOHM
    - On Tenderly, this can be done using the "Fund Account" button in the dashboard.
5. Delegate your gOHM voting power to your wallet address.
    - This can be done by running `./delegate.sh` with the appropriate arguments, or through the Tenderly dashboard.
6. Submit your proposal by running `./submitProposal.sh` with the appropriate arguments.

## Mainnet

1. Configure a wallet with `cast wallet`
2. Delegate your gOHM voting power to your wallet address.
    - This can be done by running `./delegate.sh` with the appropriate arguments, or through the Tenderly dashboard.
3. Submit your proposal by running `./submitProposal.sh` with the appropriate arguments.
