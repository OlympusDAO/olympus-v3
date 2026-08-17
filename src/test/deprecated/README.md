# Deprecated Tests

Tests in this directory cover contracts that are no longer maintained or deployed as part of the
active protocol. They are kept for historical reference and so that refactors are still checked
against them at compile time.

## CI behaviour

These tests are **excluded from every CI workflow**. The exclusion is path-based and applied in
`package.json`:

| Script                          | Exclusion                                                               |
| ------------------------------- | ----------------------------------------------------------------------- |
| `test:unit`                     | `--no-match-path '{src/test/proposals/*.t.sol,src/test/deprecated/**}'` |
| `test:invariant`                | `--no-match-path '{src/test/proposals/*.t.sol,src/test/deprecated/**}'` |
| `test:fork`                     | `--no-match-path 'src/test/deprecated/**'`                              |
| `test:fork:loan-consolidator`   | `--no-match-path 'src/test/deprecated/**'`                              |
| `test:fork:boosted-liquidity`   | `--no-match-path 'src/test/deprecated/**'`                              |
| `test:fork:proposal-helpers`     | `--no-match-path 'src/test/deprecated/**'`                              |
| `test:fork:misc`                | `--no-match-path 'src/test/deprecated/**'`                              |
| `test:crosschainfork`           | `--no-match-path 'src/test/deprecated/**'`                              |

They are still compiled by `forge build`, so a change that breaks them fails CI at the build step.
This is deliberate: it flags the breakage without gating on assertions that depend on long-dead
on-chain state.

## Running them

```bash
pnpm run test:deprecated
```

This script is intentionally not wired into any workflow in `.github/workflows/`.

Some of these tests are expected to fail. See the notes at the top of each file.

## Adding to this directory

Move the test file (preserving its subpath under `src/test/`) into `src/test/deprecated/`. No
script or workflow changes are needed — the path-based exclusions above already cover it. Add a
note at the top of the file explaining why the contract is deprecated and, if the test fails,
why.

## Contents

- `policies/CrossChainBridge.t.sol` — LayerZero V1 bridge policy unit tests. Passing.
- `policies/CrossChainBridgeFork.t.sol` — LayerZero V1 bridge mainnet fork test. **Failing**:
  the V1 endpoint now routes through the V2 ULN, which rejects the empty adapter params the V1
  interface sends (`LZ_ULN_InvalidWorkerOptions`). Superseded by the LayerZero V2 gateway
  (`src/test/policies/bridge/LZBridgeGateway/`) and the CCIP token pool.
