# Contents

What each file in this folder is:

- `LZTestnetConfig.sol` — testnet LayerZero addresses (endpoint, Uln302 libs, executor, DVNs), V2 EIDs, the 2-DVN route helper, confirmations, rate limits, and the 3-chain mesh helpers.
- `LZTestnetMockStack.sol` — library that deploys a minimal real Kernel stack (Kernel + ROLES + RolesAdmin + MINTR + OHM) on a chain that has none (arbitrum-sepolia).
- `LZBridgeTestnetBase.sol` — shared base: resolve the active chain from `block.chainid`, read/write the per-chain deployment files, assert the caller.
- `LZBridgeTestnetDeploy.s.sol` — script with `deploy()`, `configure()`, `status()`.
- `LZBridgeTestnetSend.s.sol` — script with `send(dstChain, to, amount)`.
- `LZBridgeTestnetOps.s.sol` — operational recovery script: `skipInbound(srcChain, nonce)`, `correctBridgedSupply(amount)`, `discover()`.
- `README.md` — step-by-step deployment and usage guide.
- `COMPARISON.md` — how this setup differs from production config.
- `CONTENTS.md` — this file.
- `deployments/` — per-chain address files (`<chain>.json`) and `messages.json`, written at runtime by the scripts.

Shell wrappers live in `shell/lz-bridge-testnet/`: `deploy.sh`, `configure.sh`, `status.sh`, `send.sh`, `message_status.sh`, `ops.sh`.
