# Olympus V3

Olympus V3, aka Bophades, is the latest iteration of the Olympus protocol. It is a foundation for the future of the protocol, utilizing the [Default Framework](https://github.com/fullyallocated/Default) to allow extensibility at the base layer via fully onchain governance mechanisms.

Use `pnpm run build` to refresh deps.

Set up a foundry config in foundry.toml.

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

Copy the `.env.deploy.example` file into one file per chain, e.g. `.env_deploy_goerli` and set the appropriate variables. This chain-specific environment file can then be called during deployment, e.g. `env $(cat .env_deploy_goerli | xargs) PRIVATE_KEY=<PRIVATE KEY> ./shell/deploy.sh`

## Deployment

See [DEPLOY.md](src/scripts/DEPLOY.md) and [DEPLOY_L2.md](src/scripts/DEPLOY_L2.md) for more detailed steps.

## Boosted Liquidity Vault Setup

- Deploy any dependencies (if on testnet)
- Deploy BLV contracts
- Activate BLV contracts with the BLV registry (using an olymsig script)
