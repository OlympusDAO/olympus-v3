# Batch Scripts

This directory contains batch scripts for the Olympus DAO multisig.

## Fork Testing

To run the scripts on a testnet/forked chain, provide the `--testnet` flag to the `batch.sh` script. This requires certain environment variables to be set, which are documented in the `batch.sh` file.

For example:

```bash
./batch.sh --contract ContractRegistryInstall --batch script1_install --broadcast true --testnet true --env .env.testnet
```
