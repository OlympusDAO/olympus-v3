// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import "src/Kernel.sol";
import {SingleSidedLiquidityVault} from "policies/lending/abstracts/SingleSidedLiquidityVault.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {JoinPoolRequest, ExitPoolRequest, IVault, IBasePool, IBalancerHelper} from "policies/lending/interfaces/IBalancer.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";
import {IWsteth} from "policies/lending/interfaces/ILido.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus wstETH Single-Sided Liquidity Vault
contract WstethLiquidityVault is SingleSidedLiquidityVault {
    // ========= EVENTS ========= //

    event LiquidityVault_ExternalAccumulationError(address token);

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
    IBalancerHelper public balancerHelper;

    // Aura Pool Info
    AuraPool public auraPool;

    // Price Feeds
    OracleFeed public ohmEthPriceFeed;
    OracleFeed public ethUsdPriceFeed;
    OracleFeed public stethUsdPriceFeed;

    // Price Feed Decimals
    uint32 public immutable ohmEthPriceFeedDecimals;
    uint32 public immutable ethUsdPriceFeedDecimals;
    uint32 public immutable stethUsdPriceFeedDecimals;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address wsteth_,
        address vault_,
        address balancerHelper_,
        address liquidityPool_,
        OracleFeed memory ohmEthPriceFeed_,
        OracleFeed memory ethUsdPriceFeed_,
        OracleFeed memory stethUsdPriceFeed_,
        AuraPool memory auraPool_
    ) SingleSidedLiquidityVault(kernel_, ohm_, wsteth_, liquidityPool_) {
        // Set Balancer vault
        vault = IVault(vault_);
        balancerHelper = IBalancerHelper(balancerHelper_);

        // Set price feeds
        ohmEthPriceFeed = ohmEthPriceFeed_;
        ethUsdPriceFeed = ethUsdPriceFeed_;
        stethUsdPriceFeed = stethUsdPriceFeed_;

        // Set price feed decimals
        ohmEthPriceFeedDecimals = ohmEthPriceFeed_.feed.decimals();
        ethUsdPriceFeedDecimals = ethUsdPriceFeed_.feed.decimals();
        stethUsdPriceFeedDecimals = stethUsdPriceFeed_.feed.decimals();

        // Set Aura pool info
        auraPool = auraPool_;

        // Set exchange name
        EXCHANGE = "Balancer";
    }

    //============================================================================================//
    //                                   BASE OVERRIDE FUNCTIONS                                  //
    //============================================================================================//

    // ========= CORE FUNCTIONS ========= //

    /// @notice                 Deposits OHM and wstETH into the Balancer pool. Deposits the received BPT into Aura to accrue rewards
    /// @param ohmAmount_       Amount of OHM to deposit
    /// @param pairAmount_      Amount of wstETH to deposit
    /// @param slippageParam_   Minimum amount of BPT to receive (prior to staking into Aura)
    /// @return uint256         Amount of BPT received
    function _deposit(
        uint256 ohmAmount_,
        uint256 pairAmount_,
        uint256 slippageParam_
    ) internal override returns (uint256) {
        // Cast pool address from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        // OHM-wstETH BPT before
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
            userData: abi.encode(1, maxAmountsIn, slippageParam_),
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

    /// @notice                 Withdraws BPT from Aura. Exchanges BPT for OHM and wstETH to leave the Balancer pool
    /// @param lpAmount_        Amount of BPT to withdraw
    /// @param minTokenAmounts_ Minimum amounts of OHM and wstETH to receive ([OHM, wstETH])
    /// @return uint256         Amount of OHM received
    /// @return uint256         Amount of wstETH received
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

        auraPool.rewardsPool.getReward(address(this), true);

        uint256[] memory rewards = new uint256[](numExternalRewards);
        for (uint256 i; i < numExternalRewards; ) {
            ExternalRewardToken storage rewardToken = externalRewardTokens[i];
            uint256 newBalance = ERC20(rewardToken.token).balanceOf(address(this));

            // This shouldn't happen but adding a sanity check in case
            if (newBalance < rewardToken.lastBalance) {
                emit LiquidityVault_ExternalAccumulationError(rewardToken.token);
                continue;
            }

            rewards[i] = newBalance - rewardToken.lastBalance;
            rewardToken.lastBalance = newBalance;

            unchecked {
                ++i;
            }
        }
        return rewards;
    }

    // ========= UTILITY FUNCTIONS ========= //

    /// @notice                 Calculates the OHM equivalent quantity for the wstETH deposit
    /// @param amount_          Amount of wstETH to calculate OHM equivalent for
    /// @return uint256         OHM equivalent quantity
    function _valueCollateral(uint256 amount_) public view override returns (uint256) {
        uint256 stethPerWsteth = IWsteth(address(pairToken)).stEthPerToken();

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

        // This is returned in 8 decimals and represents USD per stETH
        uint256 stethUsd = _validatePrice(
            address(stethUsdPriceFeed.feed),
            uint256(stethUsdPriceFeed.updateThreshold)
        );

        // Amount is 18 decimals in the case of wstETH and OHM has 9 decimals so to get a result with 9
        // decimals we need to use this decimal adjustment
        uint8 ohmDecimals = 9;
        uint256 decimalAdjustment = 10 **
            (ohmEthPriceFeedDecimals +
                ethUsdPriceFeedDecimals +
                ohmDecimals -
                stethUsdPriceFeedDecimals -
                pairTokenDecimals);

        return (amount_ * stethPerWsteth * stethUsd * decimalAdjustment) / (ohmEth * ethUsd * 1e18);
    }

    /// @notice                 Calculates the prevailing OHM/wstETH ratio of the Balancer pool
    /// @return uint256         OHM/wstETH ratio
    function _getPoolPrice() internal view override returns (uint256) {
        (, uint256[] memory balances_, ) = vault.getPoolTokens(
            IBasePool(liquidityPool).getPoolId()
        );

        // In Balancer pools the tokens are listed in alphabetical order (numbers before letters)
        // OHM is listed first, wstETH is listed second so this calculates OHM/wstETH which is then
        // used to compare against the oracle calculation OHM/wstETH price
        // Hard coding decimals is fine here because it is a specific implementation and we know the
        // decimals of the tokens in the pool
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
    //                                      VIEW FUNCTIONS                                        //
    //============================================================================================//

    /// @notice                 Calculates the expected amount of Balancer Pool Tokens that would be received
    ///                         for depositing a certain amount of wstETH
    /// @param amount_          Amount of wstETH to calculate BPT for
    /// @return bptAmount       Amount of BPT that would be received
    /// @dev                    This function is not meant to be called within a transaction and it will always revert.
    ///                         It is meant to be called off-chain (by the frontend) using a call request.
    function getExpectedLPAmount(uint256 amount_) public override returns (uint256 bptAmount) {
        // Cast pool address from abstract to Balancer Base pool
        IBasePool pool = IBasePool(liquidityPool);

        // Get amount of OHM that would be borrowed
        uint256 ohmAmount = _valueCollateral(amount_);

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmAmount;
        maxAmountsIn[1] = amount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, 0),
            fromInternalBalance: false
        });

        (bptAmount, ) = balancerHelper.queryJoin(
            pool.getPoolId(),
            address(this),
            address(this),
            joinPoolRequest
        );
    }

    function getUserWstethShare(address user_) internal view returns (uint256) {
        // Cast pool address from abstract to Balancer Base pool
        IBasePool pool = IBasePool(liquidityPool);

        // Get user's LP balance
        uint256 userLpBalance = lpPositions[user_];

        (, uint256[] memory balances_, ) = vault.getPoolTokens(pool.getPoolId());
        uint256 bptTotalSupply = pool.totalSupply();
        return (balances_[1] * userLpBalance) / bptTotalSupply;
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                 Updates the minimum update frequency for each price feed needed for it to not be considered stale
    function changeUpdateThresholds(
        uint48 ohmEthPriceFeedUpdateThreshold_,
        uint48 ethUsdPriceFeedUpdateThreshold_,
        uint48 stethUsdPriceFeedUpdateThreshold_
    ) external onlyRole("liquidityvault_admin") {
        ohmEthPriceFeed.updateThreshold = ohmEthPriceFeedUpdateThreshold_;
        ethUsdPriceFeed.updateThreshold = ethUsdPriceFeedUpdateThreshold_;
        stethUsdPriceFeed.updateThreshold = stethUsdPriceFeedUpdateThreshold_;
    }

    /// @notice                 Rescue funds from Aura in the event the contract was shut off due to a bug
    /// @dev                    This function can only be accessed by the liquidityvault_admin role and only when
    ///                         the vault is deactivated. This acts as an emergency migration function in the event
    ///                         that the vault is compromised.
    function rescueFundsFromAura() external onlyRole("liquidityvault_admin") {
        if (isVaultActive) revert LiquidityVault_StillActive();

        uint256 auraBalance = auraPool.rewardsPool.balanceOf(address(this));
        auraPool.rewardsPool.withdrawAndUnwrap(auraBalance, false);
    }
}
