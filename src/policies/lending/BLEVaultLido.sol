// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {BLEVaultManagerLido} from "policies/lending/BLEVaultManagerLido.sol";

// Import external dependencies
import {JoinPoolRequest, ExitPoolRequest, IVault, IBasePool} from "policies/lending/interfaces/IBalancer.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import types
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {Clone} from "clones/Clone.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

import {console2} from "forge-std/console2.sol";

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

    // ========= CONSTRUCTOR ========= //

    constructor() {}

    // ========= IMMUTABLE CLONE ARGS ========= //

    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    function manager() public pure returns (BLEVaultManagerLido) {
        return BLEVaultManagerLido(_getArgAddress(20));
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
        if (msg.sender != owner()) revert BLEVaultLido_OnlyOwner();
        _;
    }

    modifier onlyWhileActive() {
        if (!manager().isLidoBLEActive()) revert BLEVaultLido_Inactive();
        _;
    }

    //============================================================================================//
    //                                      LIQUIDITY FUNCTIONS                                   //
    //============================================================================================//

    function deposit(
        uint256 amount_,
        uint256 minLPAmount_
    ) external onlyWhileActive onlyOwner nonReentrant returns (uint256 lpAmountOut) {
        console2.log("1");

        // Calculate OHM amount to mint
        uint256 ohmTknPrice = manager().getOhmTknPrice();
        uint256 ohmMintAmount = (amount_ * ohmTknPrice) / 1e18;

        console2.log("2");

        // Cache OHM-wstETH BPT before
        uint256 bptBefore = liquidityPool().balanceOf(address(this));

        console2.log("3");

        // Mint OHM
        manager().mintOHM(ohmMintAmount);

        console2.log("4");

        // Transfer in wstETH
        wsteth().transferFrom(msg.sender, address(this), amount_);

        console2.log("5");

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm());
        assets[1] = address(wsteth());

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
        ohm().increaseAllowance(address(vault()), ohmMintAmount);
        wsteth().approve(address(vault()), amount_);
        vault().joinPool(
            liquidityPool().getPoolId(),
            address(this),
            address(this),
            joinPoolRequest
        );

        console2.log("6");

        // OHM-PAIR BPT after
        lpAmountOut = liquidityPool().balanceOf(address(this)) - bptBefore;
        manager().increaseTotalLP(lpAmountOut);

        console2.log("7");

        // Stake into Aura
        liquidityPool().approve(address(auraBooster()), lpAmountOut);
        auraBooster().deposit(pid(), lpAmountOut, true);

        console2.log("8");

        // Return unused tokens
        uint256 unusedOHM = ohmMintAmount - ohm().balanceOf(address(this));
        uint256 unusedWsteth = amount_ - wsteth().balanceOf(address(this));

        if (unusedOHM > 0) {
            ohm().increaseAllowance(MINTR(), unusedOHM);
            manager().burnOHM(unusedOHM);
        }

        if (unusedWsteth > 0) {
            wsteth().transfer(msg.sender, unusedWsteth);
        }

        console2.log("9");

        // Emit event
        emit Deposit(ohmMintAmount - unusedOHM, amount_ - unusedWsteth);

        return lpAmountOut;
    }

    function withdraw(
        uint256 lpAmount_,
        uint256[] calldata minTokenAmounts_
    ) external onlyWhileActive onlyOwner nonReentrant returns (uint256, uint256) {
        // Cache OHM and wstETH balances before
        uint256 ohmBefore = ohm().balanceOf(address(this));
        uint256 wstethBefore = wsteth().balanceOf(address(this));

        // Decrease total LP
        manager().decreaseTotalLP(lpAmount_);

        // Unstake from Aura
        auraRewardPool().withdrawAndUnwrap(lpAmount_, true);

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm());
        assets[1] = address(wsteth());

        ExitPoolRequest memory exitPoolRequest = ExitPoolRequest({
            assets: assets,
            minAmountsOut: minTokenAmounts_,
            userData: abi.encode(1, lpAmount_),
            toInternalBalance: false
        });

        // Exit Balancer pool
        liquidityPool().approve(address(vault()), lpAmount_);
        vault().exitPool(
            liquidityPool().getPoolId(),
            address(this),
            payable(address(this)),
            exitPoolRequest
        );

        // Calculate OHM and wstETH amounts received
        uint256 ohmAmountOut = ohm().balanceOf(address(this)) - ohmBefore;
        uint256 wstethAmountOut = wsteth().balanceOf(address(this)) - wstethBefore;

        // Calculate oracle expexted wstETH received amount
        uint256 tknOhmPrice = manager().getTknOhmPrice();
        uint256 expectedWstethAmountOut = (ohmAmountOut * tknOhmPrice) / 1e9;

        uint256 wstethToReturn = wstethAmountOut > expectedWstethAmountOut
            ? expectedWstethAmountOut
            : wstethAmountOut;
        if (wstethAmountOut > wstethToReturn)
            wsteth().transfer(TRSRY(), wstethAmountOut - wstethToReturn);

        // Burn OHM
        ohm().increaseAllowance(MINTR(), ohmAmountOut);
        manager().burnOHM(ohmAmountOut);

        // Return wstETH to owner
        wsteth().transfer(msg.sender, wstethToReturn);

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
        auraRewardPool().getReward(owner(), true);

        // Send rewards to owner
        _sendRewards();
    }

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    function getLPBalance() public view returns (uint256) {
        return auraRewardPool().balanceOf(address(this));
    }

    function getUserPairShare() public view returns (uint256) {
        // Get user's LP balance
        uint256 userLPBalance = getLPBalance();

        // Get pool balances
        (, uint256[] memory balances, ) = vault().getPoolTokens(liquidityPool().getPoolId());

        // Get user's share of the wstETH
        uint256 userWstethShare = (userLPBalance * balances[1]) / liquidityPool().totalSupply();

        // Check pool against oracle price
        uint256 tknOhmPrice = manager().getTknOhmPrice();
        uint256 userOhmShare = (userLPBalance * balances[0]) / liquidityPool().totalSupply();
        uint256 expectedWstethShare = (userOhmShare * tknOhmPrice) / 1e9;

        return userWstethShare > expectedWstethShare ? expectedWstethShare : userWstethShare;
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

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
            }
        }
    }
}
