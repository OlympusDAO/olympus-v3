// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {IBLVaultLido, RewardsData} from "policies/BoostedLiquidity/interfaces/IBLVaultLido.sol";
import {IBLVaultManagerLido} from "policies/BoostedLiquidity/interfaces/IBLVaultManagerLido.sol";
import {BLVaultManagerLido} from "policies/BoostedLiquidity/BLVaultManagerLido.sol";

// Import external dependencies
import {JoinPoolRequest, ExitPoolRequest, IVault, IBasePool} from "policies/BoostedLiquidity/interfaces/IBalancer.sol";
import {IAuraBooster, IAuraRewardPool, IAuraMiningLib} from "policies/BoostedLiquidity/interfaces/IAura.sol";

// Import types
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {Clone} from "clones/Clone.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

contract BLVaultLido is IBLVaultLido, Clone {
    using TransferHelper for ERC20;
    using FullMath for uint256;

    // ========= ERRORS ========= //

    error BLVaultLido_AlreadyInitialized();
    error BLVaultLido_OnlyOwner();
    error BLVaultLido_Inactive();
    error BLVaultLido_Reentrancy();

    // ========= EVENTS ========= //

    event Deposit(uint256 ohmAmount, uint256 wstethAmount);
    event Withdraw(uint256 ohmAmount, uint256 wstethAmount);
    event RewardsClaimed(address indexed rewardsToken, uint256 amount);

    // ========= STATE VARIABLES ========= //

    uint256 private constant _OHM_DECIMALS = 1e9;
    uint256 private constant _WSTETH_DECIMALS = 1e18;

    uint256 private _reentrancyStatus;

    // ========= CONSTRUCTOR ========= //

    constructor() {}

    // ========= INITIALIZER ========= //

    function initializeClone() external {
        if (_reentrancyStatus != 0) revert BLVaultLido_AlreadyInitialized();
        _reentrancyStatus = 1;
    }

    // ========= IMMUTABLE CLONE ARGS ========= //

    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    function manager() public pure returns (BLVaultManagerLido) {
        return BLVaultManagerLido(_getArgAddress(20));
    }

    function TRSRY() public pure returns (address) {
        return _getArgAddress(40);
    }

    function MINTR() public pure returns (address) {
        return _getArgAddress(60);
    }

    function ohm() public pure returns (OlympusERC20Token) {
        return OlympusERC20Token(_getArgAddress(80));
    }

    function wsteth() public pure returns (ERC20) {
        return ERC20(_getArgAddress(100));
    }

    function aura() public pure returns (ERC20) {
        return ERC20(_getArgAddress(120));
    }

    function bal() public pure returns (ERC20) {
        return ERC20(_getArgAddress(140));
    }

    function vault() public pure returns (IVault) {
        return IVault(_getArgAddress(160));
    }

    function liquidityPool() public pure returns (IBasePool) {
        return IBasePool(_getArgAddress(180));
    }

    function pid() public pure returns (uint256) {
        return _getArgUint256(200);
    }

    function auraBooster() public pure returns (IAuraBooster) {
        return IAuraBooster(_getArgAddress(232));
    }

    function auraRewardPool() public pure returns (IAuraRewardPool) {
        return IAuraRewardPool(_getArgAddress(252));
    }

    function fee() public pure returns (uint64) {
        return _getArgUint64(272);
    }

    // ========= MODIFIERS ========= //

    modifier onlyOwner() {
        if (msg.sender != owner()) revert BLVaultLido_OnlyOwner();
        _;
    }

    modifier onlyWhileActive() {
        if (!manager().isLidoBLVaultActive()) revert BLVaultLido_Inactive();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus != 1) revert BLVaultLido_Reentrancy();

        _reentrancyStatus = 2;

        _;

        _reentrancyStatus = 1;
    }

    //============================================================================================//
    //                                      LIQUIDITY FUNCTIONS                                   //
    //============================================================================================//

    /// @inheritdoc IBLVaultLido
    function deposit(
        uint256 amount_,
        uint256 minLpAmount_
    ) external override onlyWhileActive onlyOwner nonReentrant returns (uint256 lpAmountOut) {
        // Cache variables into memory
        IBLVaultManagerLido manager = manager();
        OlympusERC20Token ohm = ohm();
        ERC20 wsteth = wsteth();
        IBasePool liquidityPool = liquidityPool();
        IAuraBooster auraBooster = auraBooster();

        // Calculate OHM amount to mint
        // getOhmTknPrice returns the amount of OHM per 1 wstETH
        uint256 ohmWstethPrice = manager.getOhmTknPrice();
        uint256 ohmMintAmount = (amount_ * ohmWstethPrice) / _WSTETH_DECIMALS;

        // Cache OHM-wstETH BPT before
        uint256 bptBefore = liquidityPool.balanceOf(address(this));

        // Transfer in wstETH
        wsteth.transferFrom(msg.sender, address(this), amount_);

        // Mint OHM
        manager.mintOhmToVault(ohmMintAmount);

        // Join Balancer pool
        _joinBalancerPool(ohmMintAmount, amount_, minLpAmount_);

        // OHM-PAIR BPT after
        lpAmountOut = liquidityPool.balanceOf(address(this)) - bptBefore;
        manager.increaseTotalLp(lpAmountOut);

        // Stake into Aura
        liquidityPool.approve(address(auraBooster), lpAmountOut);
        auraBooster.deposit(pid(), lpAmountOut, true);

        // Return unused tokens
        uint256 unusedOhm = ohm.balanceOf(address(this));
        uint256 unusedWsteth = wsteth.balanceOf(address(this));

        if (unusedOhm > 0) {
            ohm.increaseAllowance(MINTR(), unusedOhm);
            manager.burnOhmFromVault(unusedOhm);
        }

        if (unusedWsteth > 0) {
            wsteth.transfer(msg.sender, unusedWsteth);
        }

        // Emit event
        emit Deposit(ohmMintAmount - unusedOhm, amount_ - unusedWsteth);

        return lpAmountOut;
    }

    /// @inheritdoc IBLVaultLido
    function withdraw(
        uint256 lpAmount_,
        uint256[] calldata minTokenAmounts_
    ) external override onlyWhileActive onlyOwner nonReentrant returns (uint256, uint256) {
        // Cache variables into memory
        OlympusERC20Token ohm = ohm();
        ERC20 wsteth = wsteth();
        IBLVaultManagerLido manager = manager();

        // Cache OHM and wstETH balances before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 wstethBefore = wsteth.balanceOf(address(this));

        // Decrease total LP
        manager.decreaseTotalLp(lpAmount_);

        // Unstake from Aura
        auraRewardPool().withdrawAndUnwrap(lpAmount_, true);

        // Exit Balancer pool
        _exitBalancerPool(lpAmount_, minTokenAmounts_);

        // Calculate OHM and wstETH amounts received
        uint256 ohmAmountOut = ohm.balanceOf(address(this)) - ohmBefore;
        uint256 wstethAmountOut = wsteth.balanceOf(address(this)) - wstethBefore;

        // Calculate oracle expected wstETH received amount
        // getTknOhmPrice returns the amount of wstETH per 1 OHM based on the oracle price
        uint256 wstethOhmPrice = manager.getTknOhmPrice();
        uint256 expectedWstethAmountOut = (ohmAmountOut * wstethOhmPrice) / _OHM_DECIMALS;

        // Take any arbs relative to the oracle price for the Treasury and return the rest to the owner
        uint256 wstethToReturn = wstethAmountOut > expectedWstethAmountOut
            ? expectedWstethAmountOut
            : wstethAmountOut;
        if (wstethAmountOut > wstethToReturn)
            wsteth.transfer(TRSRY(), wstethAmountOut - wstethToReturn);

        // Burn OHM
        ohm.increaseAllowance(MINTR(), ohmAmountOut);
        manager.burnOhmFromVault(ohmAmountOut);

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

    /// @inheritdoc IBLVaultLido
    function claimRewards() external override onlyWhileActive onlyOwner nonReentrant {
        // Claim rewards from Aura
        auraRewardPool().getReward(owner(), true);

        // Send rewards to owner
        _sendRewards();
    }

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// @inheritdoc IBLVaultLido
    function getLpBalance() public view override returns (uint256) {
        return auraRewardPool().balanceOf(address(this));
    }

    /// @inheritdoc IBLVaultLido
    function getUserPairShare() public view override returns (uint256) {
        // If total supply is 0 return 0
        if (liquidityPool().totalSupply() == 0) return 0;

        // Get user's LP balance
        uint256 userLpBalance = getLpBalance();

        // Get pool balances
        (, uint256[] memory balances, ) = vault().getPoolTokens(liquidityPool().getPoolId());

        // Get user's share of the wstETH
        uint256 userWstethShare = (userLpBalance * balances[1]) / liquidityPool().totalSupply();

        // Check pool against oracle price
        // getTknOhmPrice returns the amount of wstETH per 1 OHM based on the oracle price
        uint256 wstethOhmPrice = manager().getTknOhmPrice();
        uint256 userOhmShare = (userLpBalance * balances[0]) / liquidityPool().totalSupply();
        uint256 expectedWstethShare = (userOhmShare * wstethOhmPrice) / _OHM_DECIMALS;

        return userWstethShare > expectedWstethShare ? expectedWstethShare : userWstethShare;
    }

    /// @inheritdoc IBLVaultLido
    function getOutstandingRewards() public view override returns (RewardsData[] memory) {
        uint256 numExtraRewards = auraRewardPool().extraRewardsLength();
        RewardsData[] memory rewards = new RewardsData[](numExtraRewards + 2);

        // Get Bal reward
        uint256 balRewards = auraRewardPool().earned(address(this));
        rewards[0] = RewardsData({rewardToken: address(bal()), outstandingRewards: balRewards});

        // Get Aura rewards
        uint256 auraRewards = manager().auraMiningLib().convertCrvToCvx(balRewards);
        rewards[1] = RewardsData({rewardToken: address(aura()), outstandingRewards: auraRewards});

        // Get extra rewards
        for (uint256 i; i < numExtraRewards; ) {
            IAuraRewardPool extraRewardPool = IAuraRewardPool(auraRewardPool().extraRewards(i));

            address extraRewardToken = extraRewardPool.rewardToken();
            uint256 extraRewardAmount = extraRewardPool.earned(address(this));

            rewards[i + 2] = RewardsData({
                rewardToken: extraRewardToken,
                outstandingRewards: extraRewardAmount
            });

            unchecked {
                ++i;
            }
        }

        return rewards;
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

    function _joinBalancerPool(
        uint256 ohmAmount_,
        uint256 wstethAmount_,
        uint256 minLpAmount_
    ) internal {
        // Cache variables to memory
        OlympusERC20Token ohm = ohm();
        ERC20 wsteth = wsteth();
        IVault vault = vault();

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(wsteth);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmAmount_;
        maxAmountsIn[1] = wstethAmount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, minLpAmount_),
            fromInternalBalance: false
        });

        // Join pool
        ohm.increaseAllowance(address(vault), ohmAmount_);
        wsteth.approve(address(vault), wstethAmount_);
        vault.joinPool(liquidityPool().getPoolId(), address(this), address(this), joinPoolRequest);
    }

    function _exitBalancerPool(uint256 lpAmount_, uint256[] calldata minTokenAmounts_) internal {
        // Cache variables to memory
        OlympusERC20Token ohm = ohm();
        ERC20 wsteth = wsteth();
        IBasePool liquidityPool = liquidityPool();
        IVault vault = vault();

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(wsteth);

        ExitPoolRequest memory exitPoolRequest = ExitPoolRequest({
            assets: assets,
            minAmountsOut: minTokenAmounts_,
            userData: abi.encode(1, lpAmount_),
            toInternalBalance: false
        });

        // Exit Balancer pool
        liquidityPool.approve(address(vault), lpAmount_);
        vault.exitPool(
            liquidityPool.getPoolId(),
            address(this),
            payable(address(this)),
            exitPoolRequest
        );
    }

    function _sendRewards() internal {
        // Send Bal rewards to owner
        {
            uint256 balRewards = bal().balanceOf(address(this));
            uint256 balFee = (balRewards * fee()) / 10_000;
            if (balRewards - balFee > 0) {
                bal().transfer(owner(), balRewards - balFee);
                emit RewardsClaimed(address(bal()), balRewards - balFee);
            }
            if (balFee > 0) bal().transfer(TRSRY(), balFee);
        }

        // Send Aura rewards to owner
        {
            uint256 auraRewards = aura().balanceOf(address(this));
            uint256 auraFee = (auraRewards * fee()) / 10_000;
            if (auraRewards - auraFee > 0) {
                aura().transfer(owner(), auraRewards - auraFee);
                emit RewardsClaimed(address(aura()), auraRewards - auraFee);
            }
            if (auraFee > 0) aura().transfer(TRSRY(), auraFee);
        }

        // Send extra rewards to owner
        {
            uint256 numExtraRewards = auraRewardPool().extraRewardsLength();
            for (uint256 i; i < numExtraRewards; ) {
                IAuraRewardPool extraRewardPool = IAuraRewardPool(auraRewardPool().extraRewards(i));
                ERC20 extraRewardToken = ERC20(extraRewardPool.rewardToken());

                uint256 extraRewardAmount = extraRewardToken.balanceOf(address(this));
                uint256 extraRewardFee = (extraRewardAmount * fee()) / 10_000;
                if (extraRewardAmount - extraRewardFee > 0) {
                    extraRewardToken.transfer(owner(), extraRewardAmount - extraRewardFee);
                    emit RewardsClaimed(
                        address(extraRewardToken),
                        extraRewardAmount - extraRewardFee
                    );
                }
                if (extraRewardFee > 0) extraRewardToken.transfer(TRSRY(), extraRewardFee);

                unchecked {
                    ++i;
                }
            }
        }
    }
}
