# Batch Scripts

This directory contains batch scripts for the Olympus DAO multisig.

## Fork Testing

To run the scripts on an anvil fork, provide the `--fork` flag to the `safeBatchV2.sh` script. This requires certain environment variables to be set, which are documented in the `batch.sh` file.

For example:

```bash
./shell/safeBatchV2.sh --contract ContractRegistryInstall --function function_name --broadcast true --fork true --env .env.testnet
```

## Ledger Device Support

When using `--multisig true` with a Ledger device (specified via `--ledger`), the batch script workflow requires a two-step process to avoid conflicts with Ledger signature generation.

### Issue with Previous Approach

The previous approach would fail because:

- The `safeBatchV2.sh` script would configure forge to use the Ledger device for signing
- This would prevent internal FFI calls in `Safe.sol` from generating signatures from the Ledger device
- The script would hang when trying to collect signatures internally

### New Two-Step Workflow

#### Step 1: Generate Signature Only

First, run the script with `--signonly true` to generate the signature data:

```bash
./shell/safeBatchV2.sh --contract YourContract --function function_name --signonly true --multisig true --ledger mnemonic_index
```

This will:

- Execute the batch script to generate the transaction data
- Use the Ledger device to sign the transaction
- Output the signature data to the console
- Not broadcast the transaction

#### Step 2: Submit with Generated Signature

Take the generated signature from Step 1 and submit it using the `--signature` flag:

```bash
./shell/safeBatchV2.sh --contract YourContract --function function_name --signature generated_signature --multisig true --ledger mnemonic_index
```

This will:

- Use the pre-generated signature to create the Safe transaction
- Submit the transaction through the Safe API
- Allow the multisig to execute the batch without requiring Ledger interaction during the API call

### Notes

- The `--signonly` flag should only be used when generating signatures for multisig transactions
- This workflow ensures that Ledger signing happens only once, during the signature generation step
