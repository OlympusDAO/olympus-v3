# Dropping the Nethermind DVN (fix2.sh)

`fix2.sh` re-applies that set on all three chains in one run.

```bash
# 1. Re-apply the 2-DVN config on sepolia, base-sepolia and arbitrum-sepolia. Role: bridge_configurator.
./shell/lz-bridge-testnet/fix2.sh --account lz-testnet --broadcast true

# 2. Check the stuck message: it becomes deliverable, since the two remaining DVNs already verified it.
./shell/lz-bridge-testnet/message_status.sh --tx 0xdf98c1b9ca0322b5b5663f8397e8d9f229ec38d660b7a4e012b04f3ebbb430a1

# 3. Fallback, only if it still does not deliver: skip it and correct the canonical supply.
./shell/lz-bridge-testnet/fix2.sh --account lz-testnet --broadcast true --skip true --dst base-sepolia --src sepolia --nonce 2
./shell/lz-bridge-testnet/fix.sh --action correct --chain sepolia --amount 1000000000 --account lz-testnet --broadcast true
```
