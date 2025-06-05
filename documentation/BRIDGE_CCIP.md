# CCIP Bridging Infrastructure

This document contains instructions on how to deploy and configure bridging infrastructure using CCIP for the Olympus protocol.

## Pre-requisites

- Chainlink must have proposed the deployer address as the admin for the OHM token on the respective chain.
- `cast` must be set up with your wallet.
- `.env.< chain >` with the required values.
- The DAO MS address filled in `env.json`: `< chain >.olympus.multisig.dao`

## Definitions

- Canonical Chain: the main chain on which the Olympus protocol operates, and new OHM supply is minted. Currently, this is `mainnet` (production) and `sepolia` (testnet).
- Non-Canonical Chain: all chains other than the canonical chain.

## Concepts

- Token Pool: a contract owned/controlled by the protocol that is responsible for burning/locking OHM when bridging out and minting/releasing OHM when bridging in. The specific type of Token Pool depends on whether the chain is canonical or not.
- Bridge: in particular, `CCIPCrossChainBridge`, is a convenience contract that makes it easy to bridge from an EVM chain to another chain (including SVM). It provides the following features:
    - Fee calculation in the native token
    - CCIP message construction
    - When receiving on an EVM chain: failure handling and retry functionality

## Deployment

For canonical chains (mainnet and sepolia), run the following:

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_bridge_mainnet.json --chain <CHAIN> --broadcast false --verify false
```

For non-canonical chains, run the following:

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_bridge_not_mainnet.json --chain <CHAIN> --broadcast false --verify false
```

This will simulate the deployment.

Flip the `--broadcast` and `--verify` flags to true in order to perform the deployments and verify the contracts.

## Configuration

### Admin Role

The deployer wallet must temporarily accept the admin role in order to configure the pool:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "acceptAdminRole(bool)()" false --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

### Linking Token Pool

Link the OHM token on a chain with a token pool:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "setPool(bool)()" false --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

### Configuring Token Pool

This script will configure the remote chains for a token pool. It uses the same `chains` key that is described in the next section.

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "configureAllRemoteChains(bool)()" false --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

### Configuring Token Bridge

Run this command to configure the trusted remotes for a bridge on a specific chain:

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "setAllTrustedRemotes(bool)()" false --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
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

### Gas Limit

EVM-EVM bridging uses programmable token transfers (in CCIP parlance), which requires setting a gas limit on the TokenPools. This is currently set at the same time as the [bridge is configured](#configuring-token-bridge). Should it be necessary to override this, there is a script.

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "setGasLimitEVM(bool,string,uint32)()" false <DEST CHAIN> <GAS LIMIT> --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

### Destination Gas Overhead

For destination chains where burning and minting is taking place (i.e. non-canonical chains), CCIP will need to set the destination gas overhead, which will cause the fees to be slightly higher. This is because there is gas consumed when minting on the destination chain.

This will need to be repeated for all non-canonical chains. A future update (CCIP 1.7) will allow this to be user-configurable.

The current value for this is 175,000 gas.

### Transfer Ownership of Token Administrator Role to DAO MS

The Token Pool ownership then should be transferred to the DAO MS (on production chains):

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "transferTokenPoolAdminRoleToDaoMS(string)()" --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

### Accept Ownership of Token Administrator Role

The DAO MS must then accept the proposal for it to be the token administrator:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "acceptAdminRole(bool)()" true --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

Note that the second argument, `true`, will create a batch to be signed by the Safe multi-sig.

### Transfer Ownership of Bridge to DAO MS

The ownership of the bridge must then be transferred to the DAO MS:

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "transferOwnership(bool)()" false --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

### Install and Enable Token Pool

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "install(bool)()" true --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

### Enable Bridge

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "enable(bool)()" true --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

It will also set trusted remotes at the same time as enabling.

## Bridging

For EVM -> EVM, use the `./shell/bridge_ccip_to_evm.sh`.

For EVM -> SVM, use the `./shell/bridge_ccip_to_svm.sh`.

For SVM -> EVM, follow the [SVM tutorial](https://docs.chain.link/ccip/tutorials/svm/source).

## Adding New Chains

TODO

## Emergency Shutdown

This section provides details on how to shut down the bridging infrastructure in an emergency.

### Token Pool - Canonical Chain

The Token Pool on the canonical chain is a `LockReleaseTokenPool`, which custodies the OHM that has been bridged from the canonical chain and establishes an upper limit for the OHM that can be bridged back.

In a scenario where the aim is to prevent bridging from other chains to the canonical chain (e.g. an infinite mint bug), this can be achieved by withdrawing the OHM custodied in the contract.

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "withdrawAllLiquidity(bool)()" true --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

This will perform a simulation. Append `--broadcast` in order to perform the actual transaction.

### Token Pool - All Chains

On a given chain, the Token Pool can be shut down by enabling the rate limiter and setting the capacity to be very low (e.g. 2 wei).

If the aim is to disable bridging to and from a particular chain, this function can be used:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "emergencyShutdown(bool,string)()" true < remote chain > --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

If the aim is to disable bridging to and from all chains, this function can be used:

```bash
forge script src/scripts/ops/batches/CCIPTokenPool.sol --sig "emergencyShutdownAll(bool)()" true --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

### Bridge

This function will disable the CCIPCrossChainBridge contract:

```bash
forge script src/scripts/ops/batches/CCIPBridge.sol --sig "disable(bool)()" true --rpc-url <CHAIN> --account < cast account > --slow -vvv --sender < account address >
```

Any messages received by the contract while disabled will be marked as a failure and can be retried at a later date.
