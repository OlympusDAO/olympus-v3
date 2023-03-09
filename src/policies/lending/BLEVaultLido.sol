// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import external dependencies
import {AggregatorV3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {JoinPoolRequest, ExitPoolRequest, IVault, IBasePool, IBalancerHelper} from "policies/lending/interfaces/IBalancer.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";
import {IWsteth} from "policies/lending/interfaces/ILido.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import types
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

contract BLEVaultLido is ReentrancyGuard, Clone {
    using TransferHelper for ERC20;
    using FullMath for uint256;

    // ========= ERRORS ========= //

    error BLEVaultLido_AlreadyInitialized();
    error BLEVaultLido_OnlyOwner();
    error BLEVaultLido_Inactive();

    // ========= EVENTS ========= //

    event Deposit(uint256 ohmAmount, uint256 wstethAmount);
    event Withdraw(uint256 ohmAmount, uint256 wstethAmount);
    event RewardsClaimed(address indexed rewardsToken, uint256 amount);

    // ========= DATA STRUCTURES ========= //

    struct OracleFeed {
        AggregatorV3Interface feed;
        uint48 updateThreshold;
    }

    // ========= STATE VARIABLES ========= //

    // Modules
    address public TRSRY;

    // Tokens
    OlympusERC20Token public ohm;
    ERC20 public wsteth;
    ERC20 public aura;
    ERC20 public bal;

    // Balancer Info
    IVault public vault;
    IBasePool public liquidityPool;
    IBalancerHelper public balancerHelper;

    // Aura Info
    uint256 public pid;
    IAuraBooster public auraBooster;
    IAuraRewardPool public auraRewardPool;

    // Oracle Info
    OracleFeed public ohmEthPriceFeed;
    OracleFeed public stethEthPriceFeed;
    uint32 public immutable ohmEthPriceFeedDecimals;
    uint32 public immutable ethUsdPriceFeedDecimals;

    // Vault Info
    bool isInitialized;

    // ========= CONSTRUCTOR ========= //

    constructor() {}

    // ========= STATE INITIALIZER ========= //

    function initializeState(
        address TRSRY_,
        address ohm_,
        address wsteth_,
        address aura_,
        address bal_,
        address vault_,
        address liquidityPool_,
        address balancerHelper_,
        uint256 pid_,
        address auraBooster_,
        address auraRewardPool_,
        OracleFeed memory ohmEthPriceFeed_,
        OracleFeed memory stethEthPriceFeed_
    ) external {
        if (isInitialized) revert BLEVaultLido_AlreadyInitialized();

        // Set as initialized
        isInitialized = true;

        // Set modules
        TRSRY = TRSRY_;

        // Set tokens
        ohm = OlympusERC20Token(ohm_);
        wsteth = ERC20(wsteth_);
        aura = ERC20(aura_);
        bal = ERC20(bal_);

        // Set Balancer Info
        vault = IVault(vault_);
        liquidityPool = IBasePool(liquidityPool_);
        balancerHelper = IBalancerHelper(balancerHelper_);

        // Set Aura Info
        pid = pid_;
        auraBooster = IAuraBooster(auraBooster_);
        auraRewardPool = IAuraRewardPool(auraRewardPool_);

        // Set Oracle Info
        ohmEthPriceFeed = ohmEthPriceFeed_;
        stethEthPriceFeed = stethEthPriceFeed_;
        ohmEthPriceFeedDecimals = uint32(ohmEthPriceFeed_.feed.decimals());
        ethUsdPriceFeedDecimals = uint32(ohmEthPriceFeed_.feed.decimals());
    }

    // ========= IMMUTABLE CLONE ARGS ========= //

    function owner() public pure override returns (address) {
        return _getArgAddress(0);
    }

    function manager() public pure override returns (BLEVaultManagerLido) {
        return BLEVaultManagerLido(_getArgAddress(20));
    }

    function fee() public pure override returns (uint32) {
        return _getArgUint32(40);
    }

    // ========= MODIFIERS ========= //

    modifier onlyOwner() {
        if (msg.sender != owner()) revert BLEVaultLido_OnlyOwner();
        _;
    }

    modifier onlyWhileActive() {
        if (!manager().isActive()) revert BLEVaultLido_Inactive();
        _;
    }

    //============================================================================================//
    //                                      LIQUIDITY FUNCTIONS                                   //
    //============================================================================================//

    function deposit(
        uint256 amount_,
        uint256 minLPAmount_
    ) external onlyWhileActive onlyOwner nonReentrant returns (uint256 lpAmountOut) {
        // Calculate OHM amount to mint
        uint256 ohmTknPrice = _getOhmTknPrice();
        uint256 ohmMintAmount = (amount_ * ohmTknPrice) / 1e18;

        // Cache OHM-wstETH BPT before
        uint256 bptBefore = liquidityPool.balanceOf(address(this));

        // Mint OHM
        manager().mintOHM(ohmMintAmount);

        // Transfer in wstETH
        wsteth.transferFrom(msg.sender, address(this), amount_);

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(wsteth);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmMintAmount;
        maxAmountsIn[1] = amount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, minLPAmount_),
            fromInternalBalance: false
        });

        // Join pool
        ohm.increaseAllowance(address(vault), ohmAmount_);
        pairToken.approve(address(vault), pairAmount_);
        vault.joinPool(pool.getPoolId(), address(this), address(this), joinPoolRequest);

        // OHM-PAIR BPT after
        uint256 lpAmountOut = pool.balanceOf(address(this)) - bptBefore;

        // Stake into Aura
        pool.approve(address(auraPool.booster), lpAmountOut);
        auraPool.booster.deposit(auraPool.pid, lpAmountOut, true);

        // Return unused tokens
        uint256 unusedOHM = ohmMintAmount - ohm.balanceOf(address(this));
        uint256 unusedWsteth = amount_ - wsteth.balanceOf(address(this));

        if (unusedOHM > 0) {
            ohm.increaseAllowance(address(manager()), unusedOHM);
            manager().burnOHM(unusedOHM);
        }

        if (unusedWsteth > 0) {
            wsteth.transfer(msg.sender, unusedWsteth);
        }

        // Emit event
        emit Deposit(ohmMintAmount - unusedOHM, amount_ - unusedWsteth);

        return lpAmountOut;
    }

    function withdraw(
        uint256 lpAmount_,
        uint256[] calldata minTokenAmounts_
    ) external onlyWhileActive onlyOwner nonReentrant returns (uint256, uint256) {
        // Cache OHM and wstETH balances before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 wstethBefore = wsteth.balanceOf(address(this));

        // Unstake from Aura
        auraPool.withdrawAndUnwrap(lpAmount_, true);

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

        // Exit Balancer pool
        pool.approve(address(vault), lpAmount_);
        vault.exitPool(pool.getPoolId(), address(this), payable(address(this)), exitPoolRequest);

        // Calculate OHM and wstETH amounts received
        uint256 ohmAmountOut = ohm.balanceOf(address(this)) - ohmBefore;
        uint256 wstethAmountOut = wsteth.balanceOf(address(this)) - wstethBefore;

        // Calculate oracle expexted wstETH received amount
        uint256 tknOhmPrice = _getTknOhmPrice();
        uint256 expectedWstethAmountOut = (ohmAmountOut * tknOhmPrice) / 1e9;

        uint256 wstethToReturn = wstethAmountOut > expectedWstethAmountOut
            ? expectedWstethAmountOut
            : wstethAmountOut;
        if (wstethAmountOut > wstethToReturn)
            wsteth.transfer(address(TRSRY), wstethAmountOut - wstethToReturn);

        // Burn OHM
        ohm.increaseAllowance(address(manager()), ohmAmountOut);
        manager().burnOHM(ohmAmountOut);

        // Return wstETH to owner
        wsteth.transfer(msg.sender, wstethToReturn);

        // Return rewards to owner
        _sendRewards();

        // Emit event
        emit Withdraw(ohmAmountOut, wstethToReturn);

        return (ohmAmountOut, wstethToReturn);
    }

    //============================================================================================//
    //                                       REWARDS FUNCTIONS                                    //
    //============================================================================================//

    function claimRewards() external onlyWhileActive onlyOwner nonReentrant {
        // Claim rewards from Aura
        auraPool.getReward(owner(), true);

        // Send rewards to owner
        _sendRewards();
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

    function _sendRewards() internal {
        // Send Bal rewards to owner
        uint256 balRewards = bal.balanceOf(address(this));
        if (balRewards > 0) {
            bal.transfer(owner(), balRewards);
            emit RewardsClaimed(address(bal), balRewards);
        }

        // Send Aura rewards to owner
        uint256 auraRewards = aura.balanceOf(address(this));
        if (auraRewards > 0) {
            aura.transfer(owner(), auraRewards);
            emit RewardsClaimed(address(aura), auraRewards);
        }

        // Send extra rewards to owner
        uint256 numExtraRewards = auraPool.rewardsPool.extraRewardsLength();
        for (uint256 i; i < numExtraRewards; ) {
            IAuraRewardPool extraRewardPool = IAuraRewardPool(auraPool.extraRewards(i));
            ERC20 extraRewardToken = ERC20(extraRewardPool.rewardToken());

            uint256 extraRewardAmount = extraRewardToken.balanceOf(address(this));
            if (extraRewardAmount > 0) {
                extraRewardToken.transfer(owner(), extraRewardAmount);
                emit RewardsClaimed(address(extraRewardToken), extraRewardAmount);
            }
        }
    }

    //============================================================================================//
    //                                       PRICING FUNCTIONS                                    //
    //============================================================================================//

    function _getOhmTknPrice() internal view returns (uint256) {
        // Get stETH per wstETH (18 Decimals)
        uint256 stethPerWsteth = IWsteth(address(wsteth)).stEthPerToken();

        // Get ETH per OHM (18 Decimals)
        uin256 ethPerOhm = _validatePrice(ohmEthPriceFeed.feed, ohmEthPriceFeed.updateThreshold);

        // Get stETH per ETH (18 Decimals)
        uint256 stethPerEth = _validatePrice(
            stethEthPriceFeed.feed,
            stethEthPriceFeed.updateThreshold
        );

        // Calculate OHM per wstETH (9 decimals)
        return (stethPerWsteth * stethPerEth) / (ethPerOhm * 1e9);
    }

    function _getTknOhmPrice() internal view returns (uint256) {
        // Get stETH per wstETH (18 Decimals)
        uint256 stethPerWsteth = IWsteth(address(wsteth)).stEthPerToken();

        // Get ETH per OHM (18 Decimals)
        uin256 ethPerOhm = _validatePrice(ohmEthPriceFeed.feed, ohmEthPriceFeed.updateThreshold);

        // Get stETH per ETH (18 Decimals)
        uint256 stethPerEth = _validatePrice(
            stethEthPriceFeed.feed,
            stethEthPriceFeed.updateThreshold
        );

        // Calculate wstETH per OHM (18 decimals)
        return (ethPerOhm * 1e36) / (stethPerWsteth * stethPerEth);
    }

    function _validatePrice(
        AggregatorV3Interface priceFeed_,
        uint48 updateThreshold_
    ) internal view returns (uint256) {
        (uint80 roundId, int256 priceInt, , uint256 updatedAt, uint80 answeredInRound) = priceFeed_
            .latestRoundData();

        // Validate chainlink price feed data
        // 1. Price should be greater than 0
        // 2. Updated at timestamp should be within the update threshold
        // 3. Answered in round ID should be the same as round ID
        if (
            priceInt <= 0 ||
            updatedAt < block.timestamp - updateThreshold_ ||
            answeredInRound != roundId
        ) revert LiquidityVault_BadPriceFeed();

        return uint256(priceInt);
    }
}
