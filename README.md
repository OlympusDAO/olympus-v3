# Olympus V3

Olympus V3, aka Bophades, is the latest iteration of the Olympus protocol. It is a foundation for the future of the protocol, utilizing the [Default Framework](https://github.com/fullyallocated/Default) to allow extensibility at the base layer via fully onchain governance mechanisms.

Prerequisites:

- Node.js >=24
- pnpm 10.33.0

Run `pnpm install` to install all dependencies.
Run `pnpm build` or `forge build` to run a build.

Configure foundry settings in foundry.toml.

## SRC Directory Structure

```ml
├─ external - "External contracts needed for core functionality"
├─ interfaces - "Standard interfaces"
├─ libraries - "Libraries"
├─ modules - "Default framework modules"
│  ├─ AUTHR
│  ├─ INSTR
│  ├─ MINTR
│  ├─ PRICE
│  ├─ RANGE
│  ├─ TRSRY
│  ├─ BLREG
├─ policies - "Default framework policies"
├─ test - "General test utilities and mocks/larps"
```

## Deployments

Up-to-date addresses of all the deployments can be found in:

- the olymsig repos: [mainnet](https://github.com/OlympusDAO/olymsig) and [testnet](https://github.com/OlympusDAO/olymsig-testnet)
- [the official docs](https://docs.olympusdao.finance/main/contracts/addresses)

### Privileged Testnet Accounts (Multi-sigs)

- Executor - 0x84C0C005cF574D0e5C602EA7b366aE9c707381E0
- Guardian - 0x84C0C005cF574D0e5C602EA7b366aE9c707381E0
- Policy - 0x3dC18017cf8d8F4219dB7A8B93315fEC2d15B8a7
- Emergency - 0x3dC18017cf8d8F4219dB7A8B93315fEC2d15B8a7

## Setup

Add `FORK_TEST_RPC_URL` to the .env file in order to run fork tests

Copy `.env.example` to `.env` and set the variables required by the scripts you run. Use `--env .env` to load it in deployment scripts. L2 scripts also load `.env` automatically and select the chain with `--chain <rpc-alias>`.

## Deployment

See [DEPLOY.md](src/scripts/DEPLOY.md) and [DEPLOY_L2.md](src/scripts/DEPLOY_L2.md) for more detailed steps.

## Boosted Liquidity Vault Setup

- Deploy any dependencies (if on testnet)
- Deploy BLV contracts
- Activate BLV contracts with the BLV registry (using an olymsig script)

## Cooler V2

- Deploy the `cooler_v2.json` sequence
- Set the deployed addresses in `src/scripts/env.json`
- Run the governance proposal to activate the Cooler V2 contracts. This should also set the treasury borrower.
- Deploy the `cooler_v2_periphery.json` sequence
