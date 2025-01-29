# Deploy

This file contains instructions for deploying the different components of the Olympus protocol. It is most relevant for deploying the protocol to a new chain.

## OHM

The [olympus-contracts](https://github.com/OlympusDAO/olympus-contracts) repository contains the contracts related to the OHM token.

To deploy, follow these steps in a checked-out copy of the repository:

1. Install the dependencies
1. Ensure that `hardhat.config.ts` contains the required chain and RPC configuration
1. Configure the `.env` file
1. Run the deploy script: `yarn hardhat deploy --network <network> --tags OlympusERC20Token`
    - This will deploy both the OlympusAuthority and the OlympusERC20Token contracts
1. Verify the contracts by running `yarn hardhat etherscan-verify --network <network>`
1. Store the addresses of the OlympusAuthority and the OlympusERC20Token contracts in the `src/scripts/env.json` file for the new chain

Ownership of the OlympusAuthority contract should then be transferred:

- guardian to DAO MS
- policy to DAO MS

## Bophades

Assign MINTR to be the vault for the OHM token

Set the governor on OlympusAuthority to be the DAO MS
