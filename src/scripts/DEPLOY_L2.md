# Deployment Instructions - L2

This file contains instructions for deploying the different components of the Olympus protocol on L2 chains.

## Bophades

A Bophades installation can be deployed by following these steps:

1. Create a deployment sequence file in the `src/scripts/deploy/savedDeployments/<network>/` directory
    - This should contain the names of the required contract deployments, in order. See other sequence files or `DeployV2.sol` for examples.
1. Configure a `.env` file for the new chain
1. Run the deployment in simulation: `./shell/deploy.sh --sequence <sequence-file> --broadcast false --verify false --env <env-file>`
1. Run and broadcast the deployment: `./shell/deploy.sh --sequence <sequence-file> --broadcast true --verify false --env <env-file>`
1. Store the addresses of the contracts in the `src/scripts/env.json` file for the new chain

Ownership and roles should then be set:

1. MINTR to be the vault for the OHM token
1. Set the governor on OlympusAuthority to be the DAO MS
1. Assign the "emergency_shutdown" and "emergency_restart" roles to the Emergency MS
1. Assign the "custodian" and "bridge_admin" roles to the DAO MS
1. Set the admin on RolesAdmin to be the DAO MS
1. Set the kernel executor to be the DAO MS

Ownership of the OlympusAuthority contract should then be transferred:

- guardian to DAO MS
- policy to DAO MS

## Bridging
