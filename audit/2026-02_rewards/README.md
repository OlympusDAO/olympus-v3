# Olympus Rewards Distribution Audit

## Purpose

The purpose of this audit is to review the contracts for the Rewards Distribution system.

These contracts will be installed in the Olympus V3 "Bophades" system, based on the [Default Framework](https://palm-cause-2bd.notion.site/Default-A-Design-Pattern-for-Better-Protocol-Development-7f8ace6d263c4303b108dc5f8c3055b1).

## Design

The Rewards Distribution system incentivises participation in protocol activities (CD deposits, conversions, governance voting, etc.) by distributing rewards through an epoch-based Merkle tree mechanism.

### Overview

Users earn "Drachma" points off-chain by engaging with the protocol. At the end of each epoch, accumulated points determine each user's share of a reward pool. An off-chain backend computes a Merkle tree of cumulative entitlements, and the root is posted on-chain. Users then submit Merkle proofs to claim their rewards.

The system currently supports one reward type:

| Reward Type | Distributor | Token | Mechanism |
|---|---|---|---|
| Convertible OHM Rewards | `RewardDistributorConvertible` | convOHM | Fixed-strike call options on OHM |

### Convertible OHM Rewards (convOHM)

Convertible OHM tokens are fixed-strike American-style call options on OHM. Each epoch produces a distinct convOHM token with specific parameters (quote token, strike price, eligibility window, expiry).

The lifecycle is:

1. **Deploy** -- When an epoch ends, an off-chain backend calculates token configuration params, the admin then sets the Merkle root and the `RewardDistributorConvertible` deploys a new convOHM token via the `ConvertibleOHMTeller`.
2. **Claim** -- Users submit Merkle proofs to the distributor, which mints convOHM to them via the teller.
3. **Exercise** -- Between the eligible date and expiry, convOHM holders can exercise their tokens: they pay `amount * strikePrice / 1e9` in the quote token (e.g. USDS), the convOHM is burned, and fresh OHM is minted to the user via the MINTR module.
4. **Expiry** -- Unexercised tokens expire worthless. There is no reclaim mechanism (unlike the Bond Protocol original, which pre-deposited collateral).

#### Token Naming

Each convOHM token is named with the format:

- **Name**: `<quoteSymbol>/OHM <price> <YYYYMMDD>` (e.g. `USDS/OHM 15.50 20260301` with the date marking the conversion eligibility period)
- **Symbol**: `convOHM-<YYYYMMDD>` (e.g. `convOHM-20260301`)

#### Forked from Bond Protocol

The `ConvertibleOHMTeller` and `ConvertibleOHMToken` contracts are forked from Bond Protocol's option-contracts (`FixedStrikeOptionTeller` and `FixedStrikeOptionToken`) at commit [b8ce2ca](https://github.com/Bond-Protocol/option-contracts/commit/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c), which have been [previously audited](https://github.com/Bond-Protocol/option-contracts/tree/master/audit) and battle-tested in production.

Key changes from the Bond Protocol originals:

| Change | Detail |
|---|---|
| Kernel integration | Replaced Solmate `Auth` with Bophades Policy framework (ROLES, MINTR, TRSRY modules) |
| OHM-only call options | Removed `payoutToken`, `receiver`, and `call/put` parameters |
| Mint-on-exercise model | OHM is minted via MINTR on exercise instead of pre-deposited collateral |
| Creator isolation | Token hash includes `creator` (deploying distributor) to prevent cross-distributor collisions |
| Removed features | `reclaim()`, protocol fees (`claimFees()`), collateral tracking |
| Mint cap management | Added MINTR approval management to control total OHM minting |
| Reentrancy guard | Upgraded from `ReentrancyGuard` to `ReentrancyGuardTransient` (gas optimized) |

The existing `CloneERC20` (in `src/external/clones/`, previously audited for convertible deposits) now inherits from a new `Clone` wrapper (`src/external/clones/Clone.sol`) that extends the `@clones-with-immutable-args` dependency with a `_getArgUint48` reader. EIP-2612 permit support is provided by `CloneERC20Permit` (`src/external/clones/CloneERC20Permit.sol`), a new extension of `CloneERC20` with permit logic adopted from Bond Protocol's [CloneERC20.sol](https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/lib/clones/CloneERC20.sol) (previously [audited](https://github.com/Bond-Protocol/option-contracts/tree/master/audit)). `ConvertibleOHMToken` inherits from `CloneERC20Permit`.

## Scope

### In-Scope Contracts

The contracts in scope for this audit are:

#### Reward Distribution Infrastructure

- [src/](../../src/)
    - [policies/](../../src/policies/)
        - [rewards/](../../src/policies/rewards/)
            - [BaseRewardDistributor.sol](../../src/policies/rewards/BaseRewardDistributor.sol)
            - [RewardDistributorConvertible.sol](../../src/policies/rewards/RewardDistributorConvertible.sol)
        - [interfaces/](../../src/policies/interfaces/)
            - [rewards/](../../src/policies/interfaces/rewards/)
                - [IRewardDistributor.sol](../../src/policies/interfaces/rewards/IRewardDistributor.sol)
                - [IRewardDistributorConvertible.sol](../../src/policies/interfaces/rewards/IRewardDistributorConvertible.sol)

#### Convertible Token System (Forked from Bond Protocol)

- [src/](../../src/)
    - [policies/](../../src/policies/)
        - [rewards/](../../src/policies/rewards/)
            - [convertible/](../../src/policies/rewards/convertible/)
                - [ConvertibleOHMTeller.sol](../../src/policies/rewards/convertible/ConvertibleOHMTeller.sol)
                - [ConvertibleOHMToken.sol](../../src/policies/rewards/convertible/ConvertibleOHMToken.sol)
                - [interfaces/](../../src/policies/rewards/convertible/interfaces/)
                    - [IConvertibleOHMTeller.sol](../../src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol)
    - [external/](../../src/external/)
        - [clones/](../../src/external/clones/)
            - [Clone.sol](../../src/external/clones/Clone.sol)
            - [CloneERC20.sol](../../src/external/clones/CloneERC20.sol)
            - [CloneERC20Permit.sol](../../src/external/clones/CloneERC20Permit.sol)

### Audit Priority

Given the Bond Protocol fork, the audit effort should be weighted as follows:

| Priority | Contracts | Rationale |
|---|---|---|
| **High** | `BaseRewardDistributor`, `RewardDistributorConvertible` | Entirely new code; Merkle tree logic, claim flows |
| **High** | `ConvertibleOHMTeller` (deltas from Bond Protocol) | Kernel integration, MINTR minting model, removed features, creator isolation |
| **Medium** | `ConvertibleOHMToken` (deltas from Bond Protocol) | Reduced immutable layout, added creator field, renamed mint/burn |
| **Low** | `Clone.sol` | Thin wrapper over `@clones-with-immutable-args` dependency, adds only `_getArgUint48` |
| **Low** | `CloneERC20.sol` | Previously audited; only change is metadata visibility (`external` → `public`) |
| **Low** | `CloneERC20Permit.sol` | EIP-2612 permit logic adopted from audited Bond Protocol code |
| **Low** | Interface files | Type definitions, events, errors (no logic) |

## Architecture

### Inheritance Hierarchy

```text
Policy (Bophades)
  |
  +-- BaseRewardDistributor (abstract)
  |     |   implements IRewardDistributor, IVersioned, PolicyEnabler
  |     |   provides: epoch management, Merkle verification, claim tracking
  |     |
  |     +-- RewardDistributorConvertible (concrete)
  |           implements IRewardDistributorConvertible
  |           provides: convOHM token deployment and minting via Teller
  |
  +-- ConvertibleOHMTeller (concrete)
        implements IConvertibleOHMTeller, IVersioned, PolicyEnabler, ReentrancyGuardTransient
        provides: token deployment, minting, exercise, mint cap management

Clone (extends @clones-with-immutable-args, adds _getArgUint48)
  |
  +-- CloneERC20 (src/external/clones/, previously audited)
        |
        +-- CloneERC20Permit (EIP-2612 permit extension)
              |
              +-- ConvertibleOHMToken
                    provides: immutable-args ERC20 with permit, mint/burn gated to teller
```

### System Overview

```mermaid
flowchart TD
    subgraph Off-Chain
        Backend["Rewards Backend"]
        Backend -->|"computes Merkle trees"| MerkleRoot["Merkle Root"]
    end

    subgraph Bophades Kernel
        Kernel["Kernel"]
        ROLES["ROLES Module"]
        MINTR["MINTR Module"]
        TRSRY["TRSRY Module"]
    end

    subgraph Reward Distributors
        DistConv["RewardDistributorConvertible"]
    end

    subgraph Convertible Token System
        Teller["ConvertibleOHMTeller"]
        ConvToken["convOHM Tokens\n(cloned per epoch)"]
    end

    Admin((rewards_manager)) -->|"endEpoch()"| DistConv

    DistConv -->|"deploy(), create()"| Teller
    Teller -->|"clone()"| ConvToken

    User((User)) -->|"claim() with proof"| DistConv
    User -->|"exercise()"| Teller

    Teller -->|"mintOhm()"| MINTR
    Teller -->|"quote tokens"| TRSRY

    DistConv -.->|"role check"| ROLES
    Teller -.->|"role check"| ROLES
```

### Access Control

| Role | Holder | Permissions |
|---|---|---|
| `rewards_manager` | Off-chain backend / multisig | Call `endEpoch()` on distributors |
| `convertible_distributor` | `RewardDistributorConvertible` | Call `deploy()` and `create()` on `ConvertibleOHMTeller` |
| `convertible_admin` | Multisig / governance | Call `setMintCap()` on `ConvertibleOHMTeller` |
| Admin role (PolicyEnabler) | Multisig / governance | Enable/disable distributors and teller, `setMintCap()`, `setMinDuration()` on `ConvertibleOHMTeller` |
| Emergency role (PolicyEnabler) | Emergency multisig | Disable distributors and teller |

### Module Dependencies

| Contract | ROLES | MINTR | TRSRY |
|---|---|---|---|
| `BaseRewardDistributor` | Yes (via derived) | - | - |
| `RewardDistributorConvertible` | Yes | - | - |
| `ConvertibleOHMTeller` | Yes | Yes | Yes |

## Processes

### Ending an Epoch (Convertible Rewards)

When an epoch ends, the admin posts the Merkle root and deploys a new convOHM token for the epoch via the teller.

```mermaid
sequenceDiagram
    participant Admin as rewards_manager
    participant DistConv as RewardDistributorConvertible
    participant Teller as ConvertibleOHMTeller
    participant ConvToken as convOHM Token (clone)

    Admin->>DistConv: endEpoch(epochEndDate, merkleRoot, params)
    Note over DistConv: params = abi.encode(quoteToken, eligible, expiry, strikePrice)
    DistConv->>DistConv: validate epoch, set merkle root
    DistConv->>Teller: deploy(quoteToken, eligible, expiry, strikePrice)
    Teller->>Teller: validate parameters, truncate timestamps to UTC day
    Teller->>Teller: compute token hash(quoteToken, creator, eligible, expiry, strikePrice)
    alt Token does not exist
        Teller->>ConvToken: clone with immutable args (name, symbol, decimals, quote, eligible, expiry, teller, creator, strike)
        Teller->>ConvToken: updateDomainSeparator()
    end
    Teller-->>DistConv: token address
    DistConv->>DistConv: store epochConvertibleTokens[epochEndDate] = token
    DistConv->>DistConv: emit MerkleRootSet, EpochEnded
```

### Claiming Convertible Rewards

```mermaid
sequenceDiagram
    participant User
    participant DistConv as RewardDistributorConvertible
    participant Teller as ConvertibleOHMTeller
    participant ConvToken as convOHM Token

    User->>DistConv: claim(epochEndDates, amounts, proofs)
    loop For each epoch
        DistConv->>DistConv: look up epochConvertibleTokens[epoch]
        DistConv->>DistConv: verify Merkle proof, mark claimed
        DistConv->>Teller: create(token, user, amount)
        Teller->>Teller: validate token exists, not expired, msg.sender == creator
        Teller->>ConvToken: mintFor(user, amount)
        Teller->>Teller: emit ConvertibleTokenMinted(token, user, amount)
    end
    DistConv->>DistConv: emit ConvertibleTokensClaimed per epoch
```

### Exercising convOHM

```mermaid
sequenceDiagram
    participant User
    participant Teller as ConvertibleOHMTeller
    participant ConvToken as convOHM Token
    participant MINTR
    participant TRSRY
    participant QuoteToken as Quote Token (e.g. USDS)

    User->>Teller: exercise(token, amount)
    Teller->>Teller: validate token exists
    Teller->>Teller: check eligible <= block.timestamp < expiry
    Teller->>Teller: quoteAmount = mulDivUp(amount, strikePrice, 1e9)
    Teller->>ConvToken: burnFrom(user, amount)
    Teller->>MINTR: mintOhm(user, amount)
    Note over User: Receives freshly minted OHM
    Teller->>QuoteToken: safeTransferFrom(user, TRSRY, quoteAmount)
    Note over TRSRY: Receives quote tokens
    Teller->>Teller: emit ConvertibleTokenExercised(token, user, amount, quoteAmount)
```

### Activation and Deactivation

All distributors and the teller use the `PolicyEnabler` pattern for lifecycle management.

```mermaid
flowchart TD
    admin((admin)) -->|"enable()"| DistConv["RewardDistributorConvertible"]
    admin -->|"enable()"| Teller["ConvertibleOHMTeller"]
    emergency((emergency)) -->|"disable()"| DistConv
    emergency -->|"disable()"| Teller

    subgraph Policies
        DistConv
        Teller
    end
```

### Mint Cap Management

The `ConvertibleOHMTeller` manages its own MINTR approval to enforce a protocol-wide cap on OHM minting through convOHM exercise.

```mermaid
sequenceDiagram
    participant Admin as admin / convertible_admin
    participant Teller as ConvertibleOHMTeller
    participant MINTR

    Admin->>Teller: setMintCap(newCap)
    Teller->>MINTR: mintApproval(address(this))
    Note over Teller: currentApproval = existing approval

    alt newCap > currentApproval
        Teller->>MINTR: increaseMintApproval(address(this), newCap - currentApproval)
    else newCap < currentApproval
        Teller->>MINTR: decreaseMintApproval(address(this), currentApproval - newCap)
    end

    Teller->>MINTR: mintApproval(address(this))
    Note over Teller: newApproval = actual approval stored in MINTR after change
    Teller->>Teller: emit MintCapUpdated(newApproval)
```
