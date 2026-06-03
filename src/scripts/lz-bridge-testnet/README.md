# LayerZero OHM bridge — testnet deployment

Deploys and wires the full LayerZero V2 OHM bridge across three testnets so you can test
cross-chain OHM transfers end to end:

- **Ethereum Sepolia** (canonical)
- **Base Sepolia**
- **Arbitrum Sepolia**

The stack on each chain is: `LZBridgeGateway`, `LZEndpointDelegate`, `LZCrossChainBridge`
(periphery), and `LZBridgeAndDelegateConfig`. The three chains are wired into a full mesh
(every chain peers with the other two), using the three DVNs available on all of them:
LayerZero Labs, Nethermind and Horizen.

See `CONTENTS.md` for the file list and `COMPARISON.md` for how this differs from production.

## What you need before you start

1. **An RPC key.** Put `ALCHEMY_API_KEY=...` in the repo's `.env` file. The `sepolia`,
   `base-sepolia` and `arbitrum-sepolia` RPC aliases in `foundry.toml` use it.

2. **The deployer account.** Use a single account for everything. On Sepolia and Base Sepolia
   it **must** be the address that is already the Kernel executor and the RolesAdmin admin:
   `0x1A5309F208f161a393E8b5A253de8Ab894A67188`. The scripts check this and revert with
   `LZTestnet_WrongCaller` if you use a different account. On Arbitrum Sepolia there is no
   Kernel yet, so `deploy` builds a minimal one (Kernel + ROLES + MINTR + RolesAdmin + a
   mintable OHM token) owned by your account automatically.

   Register the account once as a cast wallet:

   ```bash
   cast wallet import lz-testnet --interactive
   ```

   (Or pass `--ledger <index>` instead of `--account lz-testnet`.)

3. **A little native gas** on each of the three testnets for the deployer account.

4. **Tooling:** `forge`, `cast`, `jq`, `curl`.

## Step 1 — Deploy on all three chains

`deploy` writes the addresses to `deployments/<chain>.json`. Run it once per chain:

```bash
./shell/lz-bridge-testnet/deploy.sh --chain sepolia          --account lz-testnet --broadcast true
./shell/lz-bridge-testnet/deploy.sh --chain base-sepolia     --account lz-testnet --broadcast true
./shell/lz-bridge-testnet/deploy.sh --chain arbitrum-sepolia --account lz-testnet --broadcast true
```

## Step 2 — Configure on all three chains

Do this **after** all three chains are deployed: each chain points its peers at the gateway
addresses recorded in step 1. `configure` grants the bootstrap roles to your account, configures
the LZ endpoint (libraries, ULN/Executor, the three DVNs), sets peers, enforced options and rate
limits, then enables the delegate, the gateway and the periphery.

```bash
./shell/lz-bridge-testnet/configure.sh --chain sepolia          --account lz-testnet --broadcast true
./shell/lz-bridge-testnet/configure.sh --chain base-sepolia     --account lz-testnet --broadcast true
./shell/lz-bridge-testnet/configure.sh --chain arbitrum-sepolia --account lz-testnet --broadcast true
```

## Step 3 — Check the wired state (read-only)

```bash
./shell/lz-bridge-testnet/status.sh --chain sepolia
```

Prints whether the gateway, delegate and periphery are enabled and whether each peer is set.

## Step 4 — Send OHM and track the message

Bridge `amount` OHM (9 decimals; 1 OHM == `1000000000`) from the source chain (`--chain`) to a
destination chain (`--dst`). The caller must already hold the OHM and enough native gas for the
LayerZero fee (quoted automatically). The message is appended to `deployments/messages.json`.

```bash
./shell/lz-bridge-testnet/send.sh \
  --chain sepolia --dst base-sepolia \
  --amount 1000000000 \
  --account lz-testnet
# optional: --recipient <address>   (defaults to the sender)
```

Then track delivery (queries the LayerZero Scan testnet API by source tx hash):

```bash
# all recorded messages:
./shell/lz-bridge-testnet/message_status.sh
# a single hash (also works for any external testnet bridge tx):
./shell/lz-bridge-testnet/message_status.sh --tx 0x<sourceTxHash>
```

## Order and rules so a message does not fail

- **Deploy all three chains, then configure all three, before sending.** A send to a chain that
  has not been configured yet will fail on delivery (no peer / no receive config).
- **The first transfer must originate from Sepolia (the canonical chain).** Sepolia only mints
  OHM on receipt up to the amount previously sent out from it (`bridgedSupply` accounting), so
  `Sepolia -> L2` must happen before any `L2 -> Sepolia`. `L2 -> L2` is unrestricted.
- **OHM appears on Arbitrum Sepolia only after a transfer is bridged in** (there is no minter in
  the mock stack). Bridge `Sepolia -> Arbitrum Sepolia` first, then you can send onward from it.

## Repairing a deployed bridge

To repair live bridges (re-apply DVN config, skip a stuck message, correct bridged supply), see
`FIX.md` and `shell/lz-bridge-testnet/fix.sh`.

## Notes

- Testnet-only flow, driven by one EOA. It skips the timelock / multisig / OCG governance
  ceremony used in production (`LZBridgeActivator`, `LZBridgeGatewayL2Batch`). See `COMPARISON.md`.
- LZ addresses (endpoint, libraries, executor, DVNs, EIDs) are pinned in `LZTestnetConfig.sol`.
- `foundry.toml` must grant write access to the deployments dir (already added to this repo):
  `{ access = "read-write", path = "./src/scripts/lz-bridge-testnet/deployments/" }` under
  `fs_permissions`. Without it `deploy` reverts with `vm.writeJson: ... not allowed`.
- To wire a different set of testnets, add their addresses to `LZTestnetConfig.sol` and update
  the chain id mapping in `_resolveChain()` in `LZBridgeTestnetBase.sol`.
