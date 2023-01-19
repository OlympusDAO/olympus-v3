// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import "src/Kernel.sol";
import {SingleSidedLiquidityVault} from "policies/lending/abstracts/SingleSidedLiquidityVault.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {JoinPoolRequest, ExitPoolRequest, IVault, IBasePool} from "policies/lending/interfaces/IBalancer.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus stETH Single-Sided Liquidity Vault
contract StethLiquidityVault is SingleSidedLiquidityVault {
    // ========= DATA STRUCTURES ========= //

    struct OracleFeed {
        AggregatorV3Interface feed;
        uint48 updateThreshold;
    }

    struct AuraPool {
        uint256 pid;
        IAuraBooster booster;
        IAuraRewardPool rewardsPool;
    }

    // ========= STATE ========= //

    // Balancer Contracts
    IVault public vault;

    // Aura Pool Info
    AuraPool public auraPool;

    // Price Feeds
    OracleFeed public ohmEthPriceFeed;
    OracleFeed public ethUsdPriceFeed;
    OracleFeed public stethUsdPriceFeed;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address steth_,
        address vault_,
        address liquidityPool_,
        OracleFeed memory ohmEthPriceFeed_,
        OracleFeed memory ethUsdPriceFeed_,
        OracleFeed memory stethUsdPriceFeed_,
        AuraPool memory auraPool_
    ) SingleSidedLiquidityVault(kernel_, ohm_, steth_, liquidityPool_) {
        // Set Balancer vault
        vault = IVault(vault_);

        // Set price feeds
        ohmEthPriceFeed = ohmEthPriceFeed_;
        ethUsdPriceFeed = ethUsdPriceFeed_;
        stethUsdPriceFeed = stethUsdPriceFeed_;

        // Set Aura pool info
        auraPool = auraPool_;
    }

    //============================================================================================//
    //                                   BASE OVERRIDE FUNCTIONS                                  //
    //============================================================================================//

    // ========= CORE FUNCTIONS ========= //

    /// @notice                 Deposits OHM and stETH into the Balancer pool. Deposits the received BPT into Aura to accrue rewards
    /// @param ohmAmount_       Amount of OHM to deposit
    /// @param pairAmount_      Amount of stETH to deposit
    /// @param minLpAmount_     Minimum amount of BPT to receive (prior to staking into Aura)
    /// @return uint256         Amount of BPT received
    function _deposit(
        uint256 ohmAmount_,
        uint256 pairAmount_,
        uint256 minLpAmount_
    ) internal override returns (uint256) {
        // Cast pool address from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        // OHM-stETH BPT before
        uint256 bptBefore = pool.balanceOf(address(this));

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmAmount_;
        maxAmountsIn[1] = pairAmount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, minLpAmount_),
            fromInternalBalance: false
        });

        // Join Balancer pool
        ohm.approve(address(vault), ohmAmount_);
        pairToken.approve(address(vault), pairAmount_);
        vault.joinPool(pool.getPoolId(), address(this), address(this), joinPoolRequest);

        // OHM-PAIR BPT after
        uint256 lpAmountOut = pool.balanceOf(address(this)) - bptBefore;

        // Stake into Aura
        pool.approve(address(auraPool.booster), lpAmountOut);
        auraPool.booster.deposit(auraPool.pid, lpAmountOut, true);

        return lpAmountOut;
    }

    /// @notice                 Withdraws BPT from Aura. Exchanges BPT for OHM and stETH to leave the Balancer pool
    /// @param lpAmount_        Amount of BPT to withdraw
    /// @param minTokenAmounts_ Minimum amounts of OHM and stETH to receive ([OHM, stETH])
    /// @return uint256         Amount of OHM received
    /// @return uint256         Amount of stETH received
    function _withdraw(uint256 lpAmount_, uint256[] calldata minTokenAmounts_)
        internal
        override
        returns (uint256, uint256)
    {
        // Cast pool adress from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        // OHM and pair token amounts before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 pairTokenBefore = pairToken.balanceOf(address(this));

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        ExitPoolRequest memory exitPoolRequest = ExitPoolRequest({
            assets: assets,
            minAmountsOut: minTokenAmounts_,
            userData: abi.encode(1, lpAmount_),
            toInternalBalance: false
        });

        // Unstake from Aura
        auraPool.rewardsPool.withdrawAndUnwrap(lpAmount_, false);

        // Exit Balancer pool
        pool.approve(address(vault), lpAmount_);
        vault.exitPool(pool.getPoolId(), address(this), payable(address(this)), exitPoolRequest);

        // OHM and pair token amounts received
        uint256 ohmReceived = ohm.balanceOf(address(this)) - ohmBefore;
        uint256 pairTokenReceived = pairToken.balanceOf(address(this)) - pairTokenBefore;

        return (ohmReceived, pairTokenReceived);
    }

    // ========= REWARDS FUNCTIONS ========= //

    /// @notice                 Harvests rewards from Aura
    /// @return uint256[]       Amounts of each reward token harvested
    function _accumulateExternalRewards() internal override returns (uint256[] memory) {
        uint256 numExternalRewards = externalRewardTokens.length;
        uint256[] memory balancesBefore = new uint256[](numExternalRewards);
        for (uint256 i; i < numExternalRewards; ) {
            balancesBefore[i] = ERC20(externalRewardTokens[i].token).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }

        auraPool.rewardsPool.getReward(address(this), true);

        uint256[] memory rewards = new uint256[](numExternalRewards);
        for (uint256 i; i < numExternalRewards; ) {
            rewards[i] =
                ERC20(externalRewardTokens[i].token).balanceOf(address(this)) -
                balancesBefore[i];

            unchecked {
                ++i;
            }
        }
        return rewards;
    }

    // ========= UTILITY FUNCTIONS ========= //

    /// @notice                 Calculates the OHM equivalent quantity for the stETH deposit
    /// @param amount_          Amount of stETH to calculate OHM equivalent for
    /// @return uint256         OHM equivalent quantity
    function _valueCollateral(uint256 amount_) internal view override returns (uint256) {
        // This is returned in 18 decimals and represents ETH per OHM
        uint256 ohmEth = _validatePrice(
            address(ohmEthPriceFeed.feed),
            uint256(ohmEthPriceFeed.updateThreshold)
        );

        // This is returned in 8 decimals and represents USD per ETH
        uint256 ethUsd = _validatePrice(
            address(ethUsdPriceFeed.feed),
            uint256(ethUsdPriceFeed.updateThreshold)
        );

        // This is returned in 18 decimals and represents USD per stETH
        uint256 stethUsd = _validatePrice(
            address(stethUsdPriceFeed.feed),
            uint256(stethUsdPriceFeed.updateThreshold)
        );

        // Get decimals for the denominator of the OHM per stETH calculation
        // Should be 26 decimals
        uint256 usdPerOhmDecimals = uint256(
            ohmEthPriceFeed.feed.decimals() + ethUsdPriceFeed.feed.decimals()
        );

        // ohmEth * ethUsd = USD per OHM in 18 + 8 = 26 decimals
        // steth * 1e26 / (ohmEth * ethUsd) = OHM per stETH in 18 decimals
        uint256 ohmPerSteth = (stethUsd * 10**usdPerOhmDecimals) / (ohmEth * ethUsd);

        // amount_ is a stETH value which should have 18 decimals
        // This should give the OHM equivalent (9 decimals)
        return (amount_ * ohmPerSteth) / 1e27;
    }

    /// @notice                 Calculates the prevailing OHM/stETH ratio of the Balancer pool
    /// @return uint256         OHM/stETH ratio
    function _getPoolPrice() internal view override returns (uint256) {
        (, uint256[] memory balances_, ) = vault.getPoolTokens(
            IBasePool(liquidityPool).getPoolId()
        );

        // In Balancer pools the tokens are listed in alphabetical order (numbers before letters)
        // OHM is listed first, stETH is listed second so this calculates OHM/stETH which is then
        // used to compare against the oracle calculation OHM/stETH price
        return (balances_[0] * 1e18) / balances_[1];
    }

    /// @notice                 Calculates the vault's claim on OHM in the Balancer pool
    /// @return uint256         OHM claim
    function _getPoolOhmShare() internal view override returns (uint256) {
        // Cast pool address from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        (, uint256[] memory balances_, ) = vault.getPoolTokens(pool.getPoolId());
        uint256 bptTotalSupply = pool.totalSupply();

        if (totalLP == 0) return 0;
        else return (balances_[0] * totalLP) / bptTotalSupply;
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @notice Updates the minimum update frequency for each price feed needed for it to not be considered stale
    function changeUpdateThresholds(
        uint48 ohmEthPriceFeedUpdateThreshold_,
        uint48 ethUsdPriceFeedUpdateThreshold_,
        uint48 stethUsdPriceFeedUpdateThreshold_
    ) external onlyRole("liquidityvault_admin") {
        ohmEthPriceFeed.updateThreshold = ohmEthPriceFeedUpdateThreshold_;
        ethUsdPriceFeed.updateThreshold = ethUsdPriceFeedUpdateThreshold_;
        stethUsdPriceFeed.updateThreshold = stethUsdPriceFeedUpdateThreshold_;
    }
}
