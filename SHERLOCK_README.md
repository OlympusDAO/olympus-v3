# OlympusDAO Sherlock Audit (02/2023)

The purpose of this audit is to review the security of a new OlympusDAO product: Single Sided Liquidity Vaults (SSLV), and some additional contracts to allow minting and burning of OHM by the DAO MS in order to implement governance proposals for pilot programs and other product tests.

These contracts will be installed in the Olympus V3 "Bophades" system, based on the Default Framework. Olympus V3 was audited multiple times prior to launch in November, 2022. The currently deployed Olympus V3 contracts can be found on [GitHub](https://github.com/OlympusDAO/olympus-v3).
You can reference these audits here:

-   Code4rena Olympus V3 Audit (08/2022)
    -   [Repo](https://github.com/code-423n4/2022-08-olympus)
    -   [Findings](https://github.com/code-423n4/2022-08-olympus-findings)
-   Kebabsec Olympus V3 Remediation and Follow-up Audits (10/2022 - 11/2022)
    -   [Remediation Audit Phase 1 Report](https://hackmd.io/tJdujc0gSICv06p_9GgeFQ)
    -   [Remediation Audit Phase 2 Report](https://hackmd.io/@12og4u7y8i/rk5PeIiEs)
    -   [Follow-on Audit Report](https://hackmd.io/@12og4u7y8i/Sk56otcBs)
-   Kebabsec SSLV Audit (02/2023)
    -   [Audit Report](https://hackmd.io/@12og4u7y8i/HJVAPMlno)

The contracts in-scope for this audit are:

```ml
src
├─ policies
|   ├─ lending
|   |   ├─ WstethLiquidityVault.sol
|   |   ├─ abstracts
|   |   |   ├─ SingleSidedLiquidityVault.sol
|   ├─ Minter.sol
|   ├─ Burner.sol
├─ modules
|   ├─ LQREG
|   |   ├─ LQREG.v1.sol
|   |   ├─ OlympusLiquidityRegistry.sol
```

The in-scope contracts depend on these previously audited and external contracts:

```ml
src
├─ Kernel.sol
├─ policies
|   ├─ lending
|   |   ├─ interfaces
|   |   |   ├─ IAura.sol
|   |   |   ├─ IBalancer.sol
|   |   |   ├─ ILido.sol
├─ modules
|   ├─ MINTR
|   |   ├─ MINTR.v1.sol
|   |   ├─ OlympusMinter.sol
|   ├─ TRSRY
|   |   ├─ TRSRY.v1.sol
|   |   ├─ OlympusTreasury.sol
|   ├─ ROLES
|   |   ├─ ROLES.v1.sol
|   |   ├─ OlympusRoles.sol
├─ interfaces
|   ├─ AggregatorV2V3Interface.sol
├─ libraries
|   ├─ TransferHelper.sol
├─ external
|   ├─ OlympusERC20.sol
lib
├─ solmate
|   ├─ tokens
|   |   ├─ ERC20.sol
|   ├─ utils
|   |   ├─ ReentrancyGuard.sol
```

## Single Sided Liquidity Vault (SSLV) Overview

This project aims to build the capability and framework for the Olympus Treasury to mint OHM directly into liquidity pairs against select, high quality assets.

### Architecture

The SSLV system will be built as one base level abstract contract that each implementations (for a partner counter-asset) will inherit and add implementation specific logic for. The vaults will be built as non-tokenized vaults and use a similar rewards system as MasterChefV2 that has been extended to handle multiple assets as well as rewards received from external protocols.

### Terminology

-   **Internal Reward Token**: An internal reward token is a token where the vault is the only source of rewards and the vault handles all accounting around how many reward tokens to distribute over time.
-   **External Reward Token**: An external reward token is a token where the primary accrual of reward tokens occurs outside the scope of this contract in a system like Convex or Aura. The vault is responsible for harvesting rewards back to the vault and then distributing them proportionally to users.

### Single Sided Liquidity Vault Security Considerations

#### Permissioned Wallets

-   There is one permissioned role in the system: `liquidityvault_admin`
-   The `liquidityvault_admin` role will be held by an OlympusDAO multisig and is trusted

#### Emergency Process

-   In the event of a bug or an integrated protocol pausing functionality there are steps that can be taken to mitigate the damage
-   Deactivate the contract through the `deactivate` function which prevents further deposits, withdrawals, or reward claims
-   Withdraw the LPs from any staking protocols through the associated rescue function on the implementation contract (`rescueFundsFromAura` in this case)
-   These LPs can be migrated to a new implementation contract and we can seed the `lpPositions` state through a combination of calling `getUsers` and then getting the `lpPositions` value for each user
-   Alternatively the DAO can manually unwind the LP positions and send the pair token side back to each user commensurate with their `lpPositions` value

#### Tokens

-   Pair tokens should be high quality tokens like major liquid staking derivatives or stablecoins
    -   Initially this will be launching with wstETH
-   No internal reward token should also be an external reward token
-   No pair token should also be an external reward token
-   No pair, internal reward, or external reward tokens should be ERC777s or non-standard ERC20s

#### Integrations

-   The vaults will integrate with major AMMs, predominantly Balancer
-   The vaults may integrate with LP staking protocols like Aura or Convex when available
-   Should an integrated protocol end up pausing the single-sided liquidity vaults would be in limbo until funds can be recovered

### Economic Brief

-   SSLVs should dampen OHM volatility relative to the counter-asset. As OHM price increases relative to the counter-asset, OHM that was minted into the vault is released into circulation outside the control and purview of the protocol. This increases circulating supply and holding all else equal should push the OHM price back down. As OHM price decreases relative to the counter-asset, OHM that was previously circulating has now entered the liquidity pool where the protocol has a claim on the OHM side of the pool. This decreases circulating supply and holding all else equal should push the OHM price back up.
-   SSLVs should behave as more efficient liquidity mining vehicles for partners. Initially Olympus will take no portion of the rewards provided by the partner protocol (and down the road will not take more than a small percentage). Thus the partner gets 2x TVL for its rewards relative to what it would get in a traditional liquidity mining system. Similarly, the depositor gets 2x rewards relative to what they would get in a traditional liquidity mining system. The depositor effectively receives 2x leverage on reward accumulation without 2x exposure to the underlying (and thus has no liquidation risk).
-   Users of SSLVs will experience identicaly impermanent loss (in dollar terms) as if they had split their pair token deposit into 50% OHM - 50% pair token and LP'd.

## Minter and Burner Policies Contracts

The Minter and Burner Policies enable OlympusDAO to mint and burn OHM outside of the automated RBS system for specific purposes related to testing new products as required by DAO governance decisions. These contracts are not meant to be part of a finalized protocol system, but function as a stop gap prior to implementing automated systems that serve new use cases. The policies have permissioned functions that will be assigned to the DAO Multisig(s) in order to execute mint and burn operations decided on by governance. Examples of this include minting OHM to deposit into lending markets that the DAO wishes to test as an offering for holders and burning OHM received by holders from OHM bonds to avoid additional supply expansion. Previously, these actions required the DAO to use old contracts and alter permissions within the system. Specifically these policies allow:

#### Burner

-   Withdrawing OHM from the Treasury and burning it.
-   Burning OHM from an address that calls the contract (address must approve the Burner for the amount).
-   Burning OHM in the Burner contract (allows sending OHM to the Burner directly and then burning it).

#### Minter

-   Minting OHM to an address

### Security Considerations

#### Permissioned Wallets

All functionality in both the Minter and Burner contracts are gated by the OlympusV3 role-based access controls (see OlympusRoles.sol). Specifically, an address must have the `minter_admin` role to execute transactions on the Minter contract and the `burner_admin` role to execute transactions on the Burner contract.

#### Tokens

The only token that the Minter and Burner contracts interact with is OHM, which is provided as a constructor argument to Burner. Minter interacts with it indirectly through the MINTR module. Minter does not transfer or custody OHM. Burner does transfer and custody OHM.

#### Emergency Procedures

The MINTR module has an emergency `deactivate` function which stops all minting and burning. If called, it would freeze the ability of these contracts to do either. Executing this is handled by a separate Emergency policy contract.

#### Integrations

The policy contracts do not have any external integrations.
