# OlympusDAO RBS v2 Audit

## Purpose

The purpose of this audit is to review an upgraded Range-Bound Stability system that that requires no manual intervention. This is aligned with the progressive automation and decentralization of the Olympus protocol.

These contracts will be installed in the Olympus V3 "Bophades" system, based on the [Default Framework](https://palm-cause-2bd.notion.site/Default-A-Design-Pattern-for-Better-Protocol-Development-7f8ace6d263c4303b108dc5f8c3055b1).

## Scope

The contracts in-scope for this audit are:

```ml
```

The in-scope contracts depend on or are dependencies for these previously audited contracts:

```ml
```

Several external interfaces and libraries are used to interact with other protocols including Uniswap V2, Uniswap V3, Chainlink, and Balancer V2. These dependencies are stored locally in the following folders:

- `src/external`
- `src/libraries`
- `src/interfaces`

Additionally, the contracts use various base contracts from `solmate` and `openzeppelin`.

## Previous Audits

TODO previous audits

## System Overview

### Components

TODO architecture diagram

The upgraded system includes the following:

- TRSRY v1.1 (module)
  - Features:
    - Add/remove assets to be managed and tracked
    - Add/remove assets to/from categories
    - Add/remove locations to track asset balances in
    - Category groups containing mutually-exclusive categories (e.g. liquid and illiquid)
- PRICEv2 (module)
  - An upgraded PRICE module that standardizes and simplifies the consumption of oracle price feeds across the Olympus protocol
  - Features:
    - The vast majority of this module has already undergone an audit
- SPPLY (module)
  - A new module to track OHM supply across different locations and categories
  - Features:
    - Add/remove categories of supply
    - Add/remove locations to categories
    - Calculate OHM supply per category
    - Calculate reserves per category
    - Calculate supply metrics (e.g. backed OHM supply)
    - Submodules to enable different sources to be used to determine supply (e.g. protocol-owned liquidity in a Uniswap V3 position)
- CrossChainBridge (policy)
  - Adds a variable to track the net quantity of OHM that has been bridged. This is used by SPPLY
- Appraiser (policy)
  - A new policy that provides high-level metrics, often combining values from TRSRY, PRICE and SPPLY
  - Features:
    - Calculate the value of asset holdings
    - Calculate the value of asset holdings in a category
    - Calculate metrics (e.g. liquid backing per backed OHM)
- BookKeeper (policy)
  - A new policy to provide convenient configuration of TRSRY, PRICE and SPPLY
- BunniManager (policy)
  - A new policy that enables Uniswap V3 positions to be managed by the Bophades system, using the [Bunni contracts](https://github.com/ZeframLou/bunni)
  - Features:
    - Create an ERC20-compatible LP token for a given Uniswap V3 pool
    - Deposit/withdraw liquidity into the pool's position
    - Harvest and re-invest fees from the position back into the pool
    - Register an existing Bunni LP token with the policy, to be used when migrating policy versions
- Operator (policy)
  - Features:
    - Utilises the liquid backing per backed OHM metric from Appraiser as the target price, instead of a manual value

#### TRSRY (Module)

#### PRICE (Module)

#### SPPLY (Module)

#### Cross-Chain Bridge (Policy)

#### Appraiser (Policy)

#### BookKeeper (Policy)

#### BunniManager (Policy)

#### Operator (Policy)

## Frequent Questions

## Getting Started

This repository uses Foundry as its development and testing environment. You must first [install Foundry](https://getfoundry.sh/) to build the contracts and run the test suite.

### Clone the repository into a local directory

```sh
git clone https://github.com/OlympusDAO/bophades
```

### Install dependencies

```sh
cd bophades
git checkout price-v2
pnpm run install # install npm modules for linting and doc generation
forge build # installs git submodule dependencies when contracts are compiled
```

### Build

Compile the contracts with `forge build`.

### Tests

Run the full test suite with `pnpm run test`. However, there are some Fork tests for other parts of the protocol that can run into RPC rate limit issues. It is recommended to run the test suite without the fork tests for this audit. Specifically, you can run `pnpm run test:unit`.

Fuzz tests have been written to cover a range of inputs. Default number of runs is 256, more were used when troubleshooting edge cases.

### Linting

Pre-configured `solhint` and `prettier-plugin-solidity`. Can be run by

```sh
pnpm run lint
```
