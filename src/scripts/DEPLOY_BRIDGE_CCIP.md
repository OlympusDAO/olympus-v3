# Deploying a CCIP Bridge

This document contains instructions on how to deploy and configure a CCIP Bridge for the Olympus protocol.

## Pre-requisites

- Chainlink must have proposed the deployer address as the admin for the OHM token on the respective chain.
- `cast` must be set up with your deployer wallet.
- `.env.< chain >` with the required values.
- The DAO MS address filled in `env.json`: `< chain >.olympus.multisig.dao`

## Deployment

For canonical chains (mainnet and sepolia), run the following:

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_bridge_mainnet.json --env .env.< chain > --broadcast false --verify false
```

For non-canonical chains, run the following:

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_bridge_not_mainnet.json --env .env.< chain > --broadcast false --verify false
```

This will simulate the deployment.

Flip the `--broadcast` and `--verify` flags to true in order to perform the deployments and verify the contracts.

## Admin Role

The deployer wallet must temporarily accept the admin role in order to configure the pool:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "acceptAdminRole(string,bool)()" < chain > true --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Linking Token Pool

Link the OHM token on a chain with a token pool:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "setPool(string,bool)()" < chain > true --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Configuring Token Pool

This particular script will configure the token pool on Sepolia to be able to bridge to Solana Devnet:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "configureRemoteChainSVM(string,bool,string)()" < chain > true solana-devnet --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Configuring Token Bridge

Run this command to configure the trusted remotes for a bridge on a specific chain:

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "setAllTrustedRemotes(string,bool)()" < chain > true --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

The `env.json` file specifies the remote chains that are configured for each local chain. The following example would allow for bridging (using the `CCIPCrossChainBridge` contract) from sepolia to solana-devnet. Allowing bridging from solana-devnet to sepolia would require a corresponding entry in the `current.solana-devnet.olympus.config.CCIPCrossChainBridge.chains` key.

```json
{
    "current": {
        "sepolia": {
            "olympus": {
                "config": {
                    "CCIPCrossChainBridge": {
                        "chains": ["solana-devnet"]
                    }
                }
            }
        }
    }
}
```

The `setAllTrustedRemotes()` function operates in a declarative manner: it will add any new trusted remotes, update outdated trusted remotes, remove redundant trusted remotes and skip the rest.

## Transfer Ownership of Token Pool

The Token Pool ownership then should be transferred to the DAO MS (on production chains):

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "transferTokenPoolAdminRole(string)()" < chain > --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Install and Enable Token Pool

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "install(string,bool)()" < chain > true --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

## Enable Bridge

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "enable(string,bool)()" < chain > true --rpc-url < RPC URL > --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

It will also set trusted remotes at the same time as enabling.
