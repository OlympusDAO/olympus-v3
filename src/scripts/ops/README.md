# Batch Scripts

This directory contains batch scripts for the Olympus DAO multisig.

## Fork Testing

To run the scripts on an anvil fork, provide the `--fork` flag to the `safeBatchV2.sh` script. This requires certain environment variables to be set, which are documented in the `batch.sh` file.

For example:

```bash
./shell/safeBatchV2.sh --contract ContractRegistryInstall --function function_name --broadcast true --fork true --env .env.testnet
```

## Signing and proposing Safe batches

Use `--multisig true` and choose one signer: `--ledger` or `--account`.
The script simulates and validates the batch before signing it.
Add `--broadcast true` to sign and submit the proposal to the Safe transaction service.
Other Safe owners then approve and execute the transaction in Safe.

With Ledger mnemonic index 5:

```bash
./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function setup --chain robinhood --multisig true --ledger 5 --broadcast true
```

With an imported Cast wallet account:

```bash
./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function setup --chain robinhood --multisig true --account dao-signer --broadcast true
```

Run these commands only after the setup prerequisites in the CCIP runbook are complete.
Omit `--broadcast true` to simulate without signing or submitting a proposal.
Use `--nonce N` to select a Safe nonce; otherwise the script uses the on-chain Safe nonce.
Pending proposals do not advance the on-chain nonce, so choose an unused nonce when queueing multiple batches.

For Ledger Safe proposals, the wrapper reads the signer address, then starts Forge without its Ledger flags.
The batch signs through the existing `safe-utils` FFI call to `cast wallet sign --ledger --data`.
The signature passes directly to the Safe API call in the same run.
For Cast accounts, Forge unlocks the account and the batch signs through `vm.sign`.

Batch entry points take `(bool useDaoMS, string argsFile, string ledgerDerivationPath)`.
The wrapper supplies these arguments; operators do not need to provide a signature.
The former `--signonly` and `--signature` options have been removed.
Without `--multisig true`, EOA transactions continue to use Forge's selected wallet for signing.
