# Single Sided Liquidity Vault Overview

This project aims to build the capability and framework for the Olympus Treasury to mint OHM directly into liquidity pairs against select, high quality assets.

# Single Sided Liquidity Vault Architecture

This system will be built as one base level abstract contract that each implementations (for a partner counter-asset) will inherit and add implementation specific logic for. The vaults will be built as non-tokenized vaults and use a similar rewards system as MasterChefV2 that has been extended to handle multiple assets as well as rewards received from external protocols.

# Single Sided Liquidity Vault Terminology

-   **Internal Reward Token**: An internal reward token is a token where the vault is the only source of rewards and the vault handles all accounting around how many reward tokens to distribute over time.
-   **External Reward Token**: An external reward token is a token where the primary accrual of reward tokens occurs outside the scope of this contract in a system like Convex or Aura. The vault is responsible for harvesting rewards back to the vault and then distributing them proportionally to users.

# Single Sided Liquidity Vault Security Considerations

### Permissioned Wallets

-   There is one permissioned role in the system: `liquidityvault_admin`
-   The `liquidityvault_admin` role will be held by an OlympusDAO multisig and is trusted

### Emergency Process

-   In the event of a bug or an integrated protocol pausing functionality there are steps that can be taken to mitigate the damage
-   Deactivate the contract through the `deactivate` function which prevents further deposits, withdrawals, or reward claims
-   Withdraw the LPs from any staking protocols through the associated rescue function on the implementation contract (`rescueFundsFromAura` in this case)
-   These LPs can be migrated to a new implementation contract and we can seed the `lpPositions` state through a combination of calling `getUsers` and then getting the `lpPositions` value for each user
-   Alternatively the DAO can manually unwind the LP positions and send the pair token side back to each user commensurate with their `lpPositions` value

### Tokens

-   Pair tokens should be high quality tokens like major liquid staking derivatives or stablecoins
    -   Initially this will be launching with wstETH
-   No internal reward token should also be an external reward token
-   No pair token should also be an external reward token
-   No pair, internal reward, or external reward tokens should be ERC777s or non-standard ERC20s

### Integrations

-   The vaults will integrate with major AMMs, predominantly Balancer
-   The vaults may integrate with LP staking protocols like Aura or Convex when available
-   Should an integrated protocol end up pausing the single-sided liquidity vaults would be in limbo until funds can be recovered

### Past Audits

-   LINK TO KEBABSEC AUDIT

# Single Sided Liquidity Vault Economic Brief

-   These vaults should dampen OHM volatility relative to the counter-asset. As OHM price increases relative to the counter-asset, OHM that was minted into the vault is released into circulation outside the control and purview of the protocol. This increases circulating supply and holding all else equal should push the OHM price back down. As OHM price decreases relative to the counter-asset, OHM that was previously circulating has now entered the liquidity pool where the protocol has a claim on the OHM side of the pool. This decreases circulating supply and holding all else equal should push the OHM price back up.
-   These vaults should behave as more efficient liquidity mining vehicles for partners. Initially Olympus will take no portion of the rewards provided by the partner protocol (and down the road will not take more than a small percentage). Thus the partner gets 2x TVL for its rewards relative to what it would get in a traditional liquidity mining system. Similarly, the depositor gets 2x rewards relative to what they would get in a traditional liquidity mining system. The depositor effectively receives 2x leverage on reward accumulation without 2x exposure to the underlying (and thus has no liquidation risk).
-   Users of these vaults will experience identicaly impermanent loss (in dollar terms) as if they had split their pair token deposit into 50% OHM - 50% pair token and LP'd.
