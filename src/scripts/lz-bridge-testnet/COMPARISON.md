# Production vs testnet setup

Same bridge **contracts** and the same wiring **sequence**; what changes is the network data, the security/limit parameters, and who drives the configuration.

## Same in both

- Contracts: `LZBridgeGateway`, `LZEndpointDelegate`, `LZCrossChainBridge`, `LZBridgeAndDelegateConfig` (identical code).
- Message: LayerZero V2, msgType `MSG_BRIDGE_OHM`, payload `(to, amount)`.
- Enforced options: Type 3, `lzReceive`, 200k gas.
- Executor `maxMessageSize`: 10000.
- ULN `optionalDVNCount`: NIL sentinel (`type(uint8).max`); 0 optional DVNs.
- Rate-limit window: 1 day.
- Wiring order: setDelegate -> pin send/recv libs -> ULN+Executor config -> peers -> enforced options -> out/in rate limits -> enable delegate, gateway, periphery.
- Topology shape: full mesh (every chain peers with every other).
- DVN config symmetry: a route's send DVN set on chain A matches the receive DVN set on chain B.

## Different

| Parameter | Production | Testnet setup |
| --- | --- | --- |
| Chains | mainnet, arbitrum, optimism, base, berachain (5) | sepolia, base-sepolia, arbitrum-sepolia (3) |
| LZ endpoint | `0x1a44...728c` (berachain `0x6F47...`) | `0x6EDCE6...f10f` |
| EIDs | 30101 / 30110 / 30111 / 30184 / 30362 | 40161 / 40245 / 40231 |
| Send/Recv libs, Executor, DVNs | mainnet addresses | testnet addresses |
| Required DVNs | 4 (LZ Labs, Canary, Nethermind, Google Cloud or Horizen) | 2 (LZ Labs, Horizen) |
| Confirmations | per chain (15 / 20 / 10 / 20 / 20) | 2 on every route (fast delivery) |
| Rate limits | per route (canon out 100k / in 55k OHM; L2->ETH 50k; L2->L2 100k; L2 in 110k) | 1,000,000 OHM both directions on every route (effectively unthrottled) |
| `bridge_configurator` holder | `LZBridgeAndDelegateConfig` policy (timelock-gated) | deployer EOA, direct (config policy is deployed but bypassed) |
| Privileged auth | Kernel executor / RolesAdmin admin / DAO MS are distinct multisigs | all three are the same deployer EOA |
| Activation path | OCG proposal `LZBridgeActivator` (canonical) + 5-step MS batch `LZBridgeGatewayL2Batch` (L2), split by caller | one EOA runs `deploy` then `configure`, no timelock / MS / OCG |
| Underlying stack | real production Kernel + modules everywhere | real on sepolia / base-sepolia; minimal mock stack on arbitrum-sepolia |
| Bridged supply | seeded via `initializeBridgedSupply` (migrating existing OHM) | starts at 0; built up by the first canonical (sepolia) send |

## Why these are safe to differ for testing

- Fewer DVNs / lower confirmations: only the verifying testnet DVNs are pinned and faster finality speeds up test cycles; the security model is otherwise identical.
- Generous rate limits: avoids throttling during testing.
- Single EOA, no timelock: removes the multisig/governance ceremony that is not meaningful on a testnet; the on-chain wiring produced is the same as production's.
