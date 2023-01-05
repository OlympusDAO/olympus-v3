// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus Base Liquidity AMO
contract BaseLiquidityAMO is Policy, ReentrancyGuard, RolesConsumer {
    // ========= ERRORS ========= //

    error LiquidityAMO_LimitViolation();
    error LiquidityAMO_PoolImbalanced();
    error LiquidityAMO_BadPriceFeed();

    // ========= DATA STRUCTURES ========= //

    struct InternalRewardToken {
        address token;
        uint256 rewardsPerSecond;
        uint256 lastRewardTime;
        uint256 accumulatedRewardsPerShare;
    }

    struct ExternalRewardToken {
        address token;
        uint256 accumulatedRewardsPerShare;
    }

    // ========= STATE ========= //

    // Modules
    MINTRv1 public MINTR;

    // Tokens
    ERC20 public ohm;
    ERC20 public pairToken;

    // Pool
    address public liquidityPool;

    // Aggregate Contract State
    uint256 public ohmMinted; // Total OHM minted over time
    uint256 public ohmBurned; // Total OHM withdrawn and burnt over time
    mapping(address => uint256) public accumulatedFees; // Total fees accumulated over time

    // User State
    mapping(address => uint256) public pairTokenDeposits; // User pair token deposits
    mapping(address => uint256) public lpPositions; // User LP positions
    mapping(address => mapping(address => uint256)) public userRewardDebts; // User reward debts

    // Reward Token State
    InternalRewardToken[] public rewardTokens;
    ExternalRewardToken[] public externalRewardTokens;

    // Configuration values
    uint256 public LIMIT;
    uint256 public THRESHOLD;
    uint256 public FEE;
    uint256 public constant PRECISION = 1000;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address pairToken_,
        address liquidityPool_
    ) Policy(kernel_) {
        // Set tokens
        ohm = ERC20(ohm_);
        pairToken = ERC20(pairToken_);

        // Set pool
        liquidityPool = liquidityPool_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = MINTR.KEYCODE();

        permissions = new Permissions[](3);
        permissions[0] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.burnOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                 Deposits pair tokens, mints OHM against the deposited pair tokens, and deposits the
    ///                         pair token and OHM into a liquidity pool and receives LP tokens in return
    /// @param  amount_         The amount of pair tokens to deposit
    /// @param  minLpAmount_    The minimum amount of LP tokens to receive
    /// @dev                    This needs to be non-reentrant since the contract only knows the amount of LP tokens it
    ///                         receives after an external interaction with the liquidity pool
    function deposit(uint256 amount_, uint256 minLpAmount_)
        external
        nonReentrant
        returns (uint256 lpAmountOut)
    {
        uint256 ohmToBorrow = _valueCollateral(amount_);
        if (!_canDeposit(ohmToBorrow)) revert LiquidityAMO_LimitViolation();

        _depositUpdateRewardState();

        // Update state about user's deposits and borrows
        pairTokenDeposits[msg.sender] += amount_;
        ohmMinted += ohmToBorrow;

        // Take pair token from user
        pairToken.transferFrom(msg.sender, address(this), amount_);

        // Borrow OHM
        _borrow(ohmToBorrow);

        uint256 lpReceived = _deposit(ohmToBorrow, amount_, minLpAmount_);

        // Update user's LP position
        lpPositions[msg.sender] += lpReceived;

        // Update user's reward debts
        _depositUpdateRewardDebts(lpReceived);
    }

    /// @notice                     Withdraws pair tokens and OHM from a liquidity pool, returns any received pair tokens to the
    ///                             user, and burns any received OHM
    /// @param  lpAmount_           The amount of LP tokens to withdraw
    /// @param  minTokenAmounts_    The minimum amounts of pair tokens and OHM to receive
    /// @dev                        This needs to be non-reentrant since the contract only knows the amount of OHM and
    ///                             pair tokens it receives after an external call to withdraw liquidity
    function withdraw(
        uint256 lpAmount_,
        uint256[] calldata minTokenAmounts_,
        bool claim_
    ) external nonReentrant returns (uint256) {
        if (!_isPoolSafe()) revert LiquidityAMO_PoolImbalanced();

        _withdrawUpdateRewardState(lpAmount_, true);

        lpPositions[msg.sender] -= lpAmount_;

        // Withdraw OHM and stETH from LP
        (uint256 ohmReceived, uint256 pairTokenReceived) = _withdraw(lpAmount_, minTokenAmounts_);

        // Reduce deposit values
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;
        ohmBurned += ohmReceived;

        // Return assets
        _repay(ohmReceived);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    /// @notice                     Claims user's rewards for all reward tokens
    function claimRewards() external returns (uint256) {
        uint256 numExternalRewardTokens = externalRewardTokens.length;
        uint256 numRewardTokens = rewardTokens.length;

        for (uint256 i; i < numExternalRewardTokens; ) {
            _claimExternalRewards(i, 0);

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numRewardTokens; ) {
            _claimRewards(i);

            unchecked {
                ++i;
            }
        }
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                     Returns the amount of rewards a user has earned for a given reward token
    /// @param  id_                 The ID of the reward token
    /// @param  user_               The user's address to check rewards for
    function rewardsForToken(uint256 id_, address user_) public view returns (uint256) {
        InternalRewardToken memory rewardToken = rewardTokens[id_];
        uint256 accumulatedRewardsPerShare = rewardToken.accumulatedRewardsPerShare;
        uint256 totalLP = ERC20(liquidityPool).balanceOf(address(this));

        if (block.timestamp > rewardToken.lastRewardTime && totalLP != 0) {
            uint256 timeDiff = block.timestamp - rewardToken.lastRewardTime;
            uint256 totalRewards = (timeDiff * rewardToken.rewardsPerSecond);
            accumulatedRewardsPerShare += (totalRewards * 1e18) / totalLP;
        }

        return
            ((lpPositions[user_] * accumulatedRewardsPerShare) / 1e18) -
            userRewardDebts[user_][rewardToken.token];
    }

    function externalRewardsForToken(
        uint256 id_,
        address user_,
        uint256 rewardsReceived_
    ) public view returns (uint256) {
        ExternalRewardToken memory rewardToken = externalRewardTokens[id_];
        uint256 accumulatedRewardsPerShare = rewardToken.accumulatedRewardsPerShare;
        uint256 totalLP = ERC20(liquidityPool).balanceOf(address(this));

        if (totalLP != 0) {
            accumulatedRewardsPerShare += rewardsReceived_ / totalLP;
        }

        return
            ((lpPositions[user_] * accumulatedRewardsPerShare) / 1e18) -
            userRewardDebts[user_][rewardToken.token];
    }

    /// @notice                     Calculates the net amount of OHM that this contract has emitted to or removed from the broader market
    /// @dev                        This is based on a point-in-time snapshot of the liquidity pool's current OHM balance
    function getOhmEmissions() external view returns (uint256 emitted, uint256 removed) {
        uint256 currentPoolOhmShare = _getPoolOhmShare();
        uint256 burnedAndOutstanding = currentPoolOhmShare + ohmBurned;

        if (burnedAndOutstanding > ohmMinted) {
            removed = burnedAndOutstanding - ohmMinted;
        } else {
            emitted = ohmMinted - burnedAndOutstanding;
        }
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _accumulateInternalRewards() internal returns (uint256[] memory) {
        uint256 numRewardTokens = rewardTokens.length;
        uint256[] memory accumulatedInternalRewards = new uint256[](rewardTokens.length);

        for (uint256 i; i < numRewardTokens; ) {
            InternalRewardToken storage rewardToken = rewardTokens[i];
            uint256 timeDiff = block.timestamp - rewardToken.lastRewardTime;
            uint256 totalRewards = (timeDiff * rewardToken.rewardsPerSecond);
            accumulatedInternalRewards[i] = totalRewards;

            unchecked {
                ++i;
            }
        }

        return accumulatedInternalRewards;
    }

    function _depositUpdateRewardState() internal {
        // Track reward accumulation
        uint256[] memory accumulatedExternalRewards = _accumulateExternalRewards();
        uint256[] memory accumulatedInternalRewards = _accumulateInternalRewards();

        // Update internal reward token state
        // This has to be done before the contract receives any LP tokens which is why it's not baked into the
        // for loop for updating reward debts like in both withdrawal functions
        uint256 numRewardTokens = rewardTokens.length;
        for (uint256 i; i < numRewardTokens; ) {
            _updateInternalRewardState(i, accumulatedInternalRewards[i]);

            unchecked {
                ++i;
            }
        }

        // Update external reward token state
        uint256 numExternalRewardTokens = externalRewardTokens.length;
        for (uint256 i; i < numExternalRewardTokens; ) {
            _updateExternalRewardState(i, accumulatedExternalRewards[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _depositUpdateRewardDebts(uint256 lpReceived_) internal {
        uint256 numRewardTokens = rewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        for (uint256 i; i < numRewardTokens; ) {
            address rewardToken = rewardTokens[i].token;
            userRewardDebts[msg.sender][rewardToken] +=
                (lpReceived_ * rewardTokens[i].accumulatedRewardsPerShare) /
                1e18;

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numExternalRewardTokens; ) {
            address rewardToken = externalRewardTokens[i].token;
            userRewardDebts[msg.sender][rewardToken] +=
                (lpReceived_ * externalRewardTokens[i].accumulatedRewardsPerShare) /
                1e18;

            unchecked {
                ++i;
            }
        }
    }

    function _withdrawUpdateRewardState(uint256 lpAmount_, bool claim_) internal {
        // Cache reward token counts
        uint256 numRewardTokens = rewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        uint256[] memory accumulatedExternalRewards = _accumulateExternalRewards();
        uint256[] memory accumulatedInternalRewards = _accumulateInternalRewards();

        for (uint256 i; i < numExternalRewardTokens; ) {
            _updateExternalRewardState(i, accumulatedExternalRewards[i]);
            if (claim_) _claimExternalRewards(i, accumulatedExternalRewards[i]);

            ExternalRewardToken memory rewardToken = externalRewardTokens[i];
            userRewardDebts[msg.sender][rewardToken.token] -=
                (lpAmount_ * rewardToken.accumulatedRewardsPerShare) /
                1e18;

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numRewardTokens; ) {
            _updateInternalRewardState(i, accumulatedInternalRewards[i]);
            if (claim_) _claimRewards(i);

            InternalRewardToken memory rewardToken = rewardTokens[i];
            userRewardDebts[msg.sender][rewardToken.token] -=
                (lpAmount_ * rewardToken.accumulatedRewardsPerShare) /
                1e18;

            unchecked {
                ++i;
            }
        }
    }

    //============================================================================================//
    //                                     VIRTUAL FUNCTIONS                                      //
    //============================================================================================//

    function _validatePrice(address priceFeed_, uint256 updateThreshold_)
        internal
        view
        returns (uint256)
    {
        (
            uint80 roundId,
            int256 priceInt,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(priceFeed_).latestRoundData();

        // Validate chainlink price feed data
        // 1. Price should be greater than 0
        // 2. Updated at timestamp should be within the update threshold
        // 3. Answered in round ID should be the same as round ID
        if (
            priceInt <= 0 ||
            updatedAt < block.timestamp - updateThreshold_ ||
            answeredInRound != roundId
        ) revert LiquidityAMO_BadPriceFeed();

        return uint256(priceInt);
    }

    function _valueCollateral(uint256 amount_) internal view virtual returns (uint256) {}

    function _getPoolPrice() internal view virtual returns (uint256) {}

    function _getPoolOhmShare() internal view virtual returns (uint256) {}

    function _canDeposit(uint256 amount_) internal view virtual returns (bool) {
        if (ohmBurned > ohmMinted + amount_) return true;
        else if (ohmMinted + amount_ - ohmBurned <= LIMIT) return true;
        else return false;
    }

    function _isPoolSafe() internal view returns (bool) {
        uint256 pairTokenDecimals = pairToken.decimals();
        uint256 poolPrice = _getPoolPrice();
        uint256 oraclePrice = _valueCollateral(10**pairTokenDecimals); // 1 pair token in OHM

        uint256 lowerBound = (oraclePrice * (PRECISION - THRESHOLD)) / PRECISION;
        uint256 upperBound = (oraclePrice * (PRECISION + THRESHOLD)) / PRECISION;

        return poolPrice >= lowerBound && poolPrice <= upperBound;
    }

    function _deposit(
        uint256 ohmAmount_,
        uint256 pairAmount_,
        uint256 minLpAmount_
    ) internal virtual returns (uint256) {}

    function _withdraw(uint256 lpAmount_, uint256[] calldata minTokenAmounts_)
        internal
        virtual
        returns (uint256, uint256)
    {}

    function _updateInternalRewardState(uint256 id_, uint256 amountAccumulated_) internal {
        InternalRewardToken storage rewardToken = rewardTokens[id_];
        uint256 totalLP = ERC20(liquidityPool).balanceOf(address(this));

        if (totalLP != 0) {
            rewardToken.accumulatedRewardsPerShare += (amountAccumulated_ * 1e18) / totalLP;
            rewardToken.lastRewardTime = block.timestamp;
        }
    }

    function _updateExternalRewardState(uint256 id_, uint256 amountAccumulated_) internal {
        ExternalRewardToken storage rewardToken = externalRewardTokens[id_];
        uint256 totalLP = ERC20(liquidityPool).balanceOf(address(this));

        if (totalLP != 0) {
            rewardToken.accumulatedRewardsPerShare += (amountAccumulated_ * 1e18) / totalLP;
        }
    }

    function _accumulateExternalRewards() internal virtual returns (uint256[] memory) {}

    function _claimExternalRewards(uint256 id_, uint256 rewardsReceived_)
        internal
        virtual
        returns (uint256)
    {
        ExternalRewardToken memory rewardToken = externalRewardTokens[id_];
        uint256 reward = externalRewardsForToken(id_, msg.sender, rewardsReceived_);
        uint256 fee = (reward * FEE) / PRECISION;

        userRewardDebts[msg.sender][rewardToken.token] += reward;
        accumulatedFees[rewardToken.token] += fee;

        if (reward > 0) ERC20(rewardToken.token).transfer(msg.sender, reward - fee);
    }

    function _claimRewards(uint256 id_) internal returns (uint256) {
        InternalRewardToken memory rewardToken = rewardTokens[id_];
        uint256 reward = rewardsForToken(id_, msg.sender);
        uint256 fee = (reward * FEE) / PRECISION;

        userRewardDebts[msg.sender][rewardToken.token] += reward;
        accumulatedFees[rewardToken.token] += fee;

        if (reward > 0) ERC20(rewardToken.token).transfer(msg.sender, reward - fee);
    }

    function _borrow(uint256 amount_) internal {
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    // TODO: Need a way to report net minted amount
    function _repay(uint256 amount_) internal {
        MINTR.burnOhm(address(this), amount_);
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                    Adds a new reward token to the contract
    /// @param  token_             The address of the reward token
    /// @param  rewardsPerSecond_  The amount of reward tokens to distribute per second
    /// @param  startTimestamp_    The timestamp at which to start distributing rewards
    function addRewardToken(
        address token_,
        uint256 rewardsPerSecond_,
        uint256 startTimestamp_
    ) external onlyRole("liquidityamo_admin") {
        InternalRewardToken memory newRewardToken = InternalRewardToken({
            token: token_,
            rewardsPerSecond: rewardsPerSecond_,
            lastRewardTime: block.timestamp > startTimestamp_ ? block.timestamp : startTimestamp_,
            accumulatedRewardsPerShare: 0
        });

        rewardTokens.push(newRewardToken);
    }

    function addExternalRewardToken(address token_) external onlyRole("liquidityamo_admin") {
        ExternalRewardToken memory newRewardToken = ExternalRewardToken({
            token: token_,
            accumulatedRewardsPerShare: 0
        });

        externalRewardTokens.push(newRewardToken);
    }

    /// @notice                    Transfers accumulated fees on reward tokens to the admin
    function claimFees() external onlyRole("liquidityamo_admin") {
        uint256 rewardTokenCount = rewardTokens.length;
        for (uint256 i; i < rewardTokenCount; ) {
            InternalRewardToken memory rewardToken = rewardTokens[i];
            uint256 feeToSend = accumulatedFees[rewardToken.token];

            accumulatedFees[rewardToken.token] = 0;

            ERC20(rewardToken.token).transfer(msg.sender, feeToSend);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice                    Updates the maximum amount of OHM that can be minted by this contract
    /// @param  limit_             The new limit
    function setLimit(uint256 limit_) external onlyRole("liquidityamo_admin") {
        LIMIT = limit_;
    }

    /// @notice                    Updates the threshold for the price deviation from the oracle price that is acceptable
    /// @param  threshold_         The new threshold (out of 1000)
    function setThreshold(uint256 threshold_) external onlyRole("liquidityamo_admin") {
        THRESHOLD = threshold_;
    }

    /// @notice                    Updates the fee charged on rewards
    /// @param  fee_               The new fee (out of 1000)
    function setFee(uint256 fee_) external onlyRole("liquidityamo_admin") {
        FEE = fee_;
    }
}
