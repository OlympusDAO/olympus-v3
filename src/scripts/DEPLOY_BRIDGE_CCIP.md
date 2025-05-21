# Deploying a CCIP Bridge

This document contains instructions on how to deploy and configure a CCIP Bridge for the Olympus protocol.

## Pre-requisites

- Chainlink must have proposed the deployer address as the admin for the OHM token on the respective chain.
- `cast` must be set up with your deployer wallet.
- `.env.< chain >` with the required values.
- The DAO MS address filled in `env.json`

## Configuration

- For mainnet/sepolia: amend the `ccip_bridge_mainnet.json` deployment sequence file to set the appropriate value for the initial bridged supply.
- On testnets (except sepolia), the initial bridged supply value will be ignored.

## Deployment

Run the following command:

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_bridge.json --env .env.< chain > --broadcast false --verify false
```

This will simulate the deployment.

Flip the `--broadcast` and `--verify` flags to true in order to perform the deployments and verify the contracts.

## Admin Role

The deployer wallet must temporarily accept the admin role in order to configure the pool:

```bash
forge script src/scripts/ops/ConfigureCCIPTokenPool.s.sol --sig "acceptAdminRole()()" --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < deployer address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Linking Token Pool

Link the OHM token on a chain with a token pool:

```bash
forge script src/scripts/ops/ConfigureCCIPTokenPool.s.sol --sig "setPool()()" --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < deployer address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Configuring Token Pool

This particular script will configure the token pool on Sepolia to be able to bridge to Solana Devnet:

```bash
forge script src/scripts/ops/ConfigureCCIPTokenPool.s.sol --sig "configureRemotePoolSolanaDevnet()()" --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < deployer address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Transfer Ownership of Token Pool

The Token Pool ownership then should be transferred to the DAO MS (on production chains):

```bash
forge script src/scripts/ops/ConfigureCCIPTokenPool.s.sol --sig "transferTokenPoolAdminRole()()" --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < deployer address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Install and Enable Token Pool

The CCIPMintBurnTokenPool contract is a policy and must be activated in the Kernel. It is also disabled by default. The owner (DAO MS) must enable it.

```bash
./shell/safeBatch.sh --contract ConfigureCCIPTokenPool --batch run --broadcast false --testnet false --env .env.< chain > --account < cast account >
```
