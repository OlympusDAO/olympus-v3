# Fixing a deployed bridge

`shell/lz-bridge-testnet/fix.sh` repairs live bridges. Pass only the chain — the gateway is read
from `deployments/<chain>.json`. Needs `ALCHEMY_API_KEY` in `.env`. Run from the repo root.

Step-by-step recovery of a stuck "Config error" message (current case: Sepolia -> Base, nonce 1,
1 OHM):

```bash
# 1. (optional) Inspect a chain: prints its delegate and remote peers (also reveals the other gateways).
./shell/lz-bridge-testnet/fix.sh --action discover --chain base-sepolia

# 2. Re-apply the corrected DVN/Executor config on the chains with wrong DVN addresses
#    (base-sepolia + arbitrum-sepolia; sepolia was already correct). Role: bridge_configurator.
./shell/lz-bridge-testnet/fix.sh --action reapply --chain base-sepolia     --account lz-testnet --broadcast true
./shell/lz-bridge-testnet/fix.sh --action reapply --chain arbitrum-sepolia --account lz-testnet --broadcast true

# 3. Skip the stuck inbound message on the destination (Base). Role: admin/bridge_admin.
./shell/lz-bridge-testnet/fix.sh --action skip --chain base-sepolia --src sepolia --nonce 1 --account lz-testnet --broadcast true

# 4. Correct the canonical bridged supply on Sepolia by the stuck amount (1 OHM = 1e9). Role: bridge_configurator.
./shell/lz-bridge-testnet/fix.sh --action correct --chain sepolia --amount 1000000000 --account lz-testnet --broadcast true
```

Then send a fresh message; it should verify and deliver.

"Config error" means the verifying DVNs do not match the receive config. Cause: a wrong DVN
address. Each provider has several deployments per chain; use the one that is `version 2`, not
`deprecated`.
