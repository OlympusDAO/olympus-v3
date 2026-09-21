# Contract ABIs

This folder has the ABI of each deployed Olympus contract. Protocol-visualizer and other consumers may use it to decode calls to the deployed addresses. This file is the source of truth for how the export works.

## Layout

```text
abis/
  manifest.json            the catalog: one entry for each deployment
  <chain>/<label>.json     the ABI of one deployment, for example mainnet/RolesAdmin.json
```

`<label>` is the last part of the deployment path in `src/scripts/env.json`. For example, the
label of `mainnet.olympus.policies.RolesAdmin` is `RolesAdmin`. Labels are unique in each chain.
Do not edit the ABI files manually.

## Scope

The export includes each nonzero address in `env.current.<chain>.olympus`, but not these:

- The `config` and `multisig` sections.
- The `legacy` section, except the contracts that are still live: `OHM`, `gOHM`, `sOHM`,
    `Staking`, and `OlympusAuthority`.
- The retired chains `goerli` and `berachain-bartio`, and the non-EVM chains.
- Deployments that `shell/abis/config.json` excludes with a reason.

The export has only current deployments. `extraDeployments` in `shell/abis/config.json` adds
current deployments that `env.json` does not list, for example an older policy that the Kernel
still has installed. The manifest marks them with `extra: true`.

## How the export gets each ABI

`shell/abis/config.json` records two values for each deployment:

- `abiHash`: the hash of the deployed ABI. This hash changes only when the deployment changes.
- `source`: the repository contract of the deployment, for example
    `src/policies/RolesAdmin.sol:RolesAdmin`. If the repository does not have the source,
    `noSource` gives the reason.

The exporter compiles each source locally with `forge inspect` and compares the hashes:

| Status        | Condition                                             | ABI file                  |
| ------------- | ----------------------------------------------------- | ------------------------- |
| `exact`       | The local ABI hash is the same as `abiHash`.          | The exporter writes it.   |
| `drifted`     | The source changed after the deployment.              | The committed file stays. |
| `interface`   | The source is an interface that the deployment has.   | The committed file stays. |
| `unavailable` | The repository does not have the source (`noSource`). | The committed file stays. |

The exporter never writes a file whose content does not match `abiHash`. Only
`gen:abis:verify --write` changes `abiHash`, and it gets the ABI from Etherscan.

## Commands

| Command                                          | Purpose                                          | Network   |
| ------------------------------------------------ | ------------------------------------------------ | --------- |
| `pnpm run gen:abis`                              | Write the ABI files and the manifest.            | None      |
| `pnpm run gen:abis:check`                        | Compare the committed files. Write nothing.      | None      |
| `pnpm run test:abis`                             | Test the exporter.                               | None      |
| `pnpm run gen:abis:verify [--chain <c>] [--write]` | Compare with Etherscan. See below for `--write`. | Etherscan |

Omit `--chain` to verify all chains. `--write` pins new, changed, and mismatched deployments in
`config.json` and writes their Etherscan ABI files. Then it runs `gen:abis`, so one command
completes the pin.

## Deploy a contract

Do these steps in the pull request that updates `src/scripts/env.json`:

1. Update `src/scripts/env.json` with the new address.
2. If the label is new, add a mapping to `shell/abis/config.json`. The key is the path in
   `env.current.<chain>.olympus`. Use a shared key to link the source on all chains, or a
   `<chain>.` key for one chain:

   ```json
   "policies.NewPolicy": {"source": "src/policies/NewPolicy.sol:NewPolicy"}
   ```

   If the repository does not have the source, use `"noSource": "<reason>"`. If the source is an
   interface, add `"sourceKind": "interface"`.

3. If the new contract replaces a contract that the Kernel still has installed, add the old
   address to `extraDeployments.<chain>` in `config.json` with a new label, for example
   `"policies.NewPolicyV1_0": "0x…"`. Add a mapping for that label as in step 2.
4. Pin the ABI and generate the export. This step needs the Etherscan API key:

   ```sh
   pnpm run gen:abis:verify --chain <chain> --write
   ```

5. Commit `src/scripts/env.json`, `shell/abis/config.json`, and `abis/` together.

Do not write `address`, `abiHash`, `contractName`, or `sourceUrl` manually. Step 4 writes them.

## Other changes

| Change                                         | Action                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------- |
| The change does not change an ABI.             | Nothing.                                                            |
| You edit a linked source file, and its compiled ABI changes (the deployed ABI stays the same). | Run `gen:abis`. The status changes to `drifted`. Commit the result. |
| A linked source file moves or is renamed.      | Correct `source` in `config.json`. Run `gen:abis`.                  |
| A contract is removed from the Kernel.        | Add `"exclude": "<reason>"` to its `<chain>.` mapping, or remove it from `extraDeployments`. Run `gen:abis`. |

Only a deployment change needs an Etherscan API key. Set `ETHERSCAN_API_KEY` in the environment or
in `.env`. CI never needs the key.

## Continuous integration

The **ABIs** workflow runs `test:abis` and `gen:abis:check` only on pull requests from `develop` to
`master`. It compiles locally and makes no network calls. It does not commit files. Before you
open a pull request to `develop`, run `gen:abis:check` locally to find a stale export early.

## Manifest fields

Each entry in `deployments` has these fields:

- `chain`, `chainId`, `path`, `address`, and `extra` for a deployment from `extraDeployments`.
- `abi`: the ABI file relative to `abis/`, for example `mainnet/RolesAdmin.json`.
- `abiHash`: the hash of the deployed ABI.
- `source`: `contract` and `status`, or `status: unavailable` and `reason`.
- `verification`: `contractName` and `sourceUrl` from Etherscan.

`exclusions` lists the excluded deployments and chains with their reasons.

## Consumers

1. Fetch `manifest.json` and the ABI files at one pinned commit or release of this repository.
2. Find the deployment by chain ID and address. The address compare is case-insensitive.
3. Decode with the ABI file. It has functions, events, and custom errors.
4. Use `source.contract` to find the code. If the status is `drifted`, the source is newer than the
   deployment.

The ABI hash ignores parameter names, declaration order, `internalType`, and constructors. The same
hash shows the same callable ABI. It does not show the same bytecode.
