// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {LQREGv1} from "src/modules/LQREG/LQREG.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus Base Liquidity AMO
abstract contract BaseLiquidityAMO is Policy, ReentrancyGuard, RolesConsumer {
    // ========= ERRORS ========= //

    error LiquidityAMO_LimitViolation();
    error LiquidityAMO_PoolImbalanced();
    error LiquidityAMO_BadPriceFeed();
    error LiquidityAMO_InvalidRemoval();

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
    LQREGv1 public LQREG;

    // Tokens
    ERC20 public ohm;
    ERC20 public pairToken;

    // Pool
    address public liquidityPool;

    // Aggregate Contract State
    uint256 public totalLP;
    uint256 public ohmMinted;
    uint256 public ohmBurned;
    mapping(address => uint256) public accumulatedFees;

    // User State
    mapping(address => uint256) public pairTokenDeposits;
    mapping(address => uint256) public lpPositions;
    mapping(address => mapping(address => int256)) public userRewardDebts; // Rewards accumulated prior to user's joining (MasterChef V2 math)

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
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("LQREG");
        dependencies[2] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        LQREG = LQREGv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = MINTR.KEYCODE();
        Keycode lqregKeycode = LQREG.KEYCODE();

        permissions = new Permissions[](5);
        permissions[0] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.burnOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(lqregKeycode, LQREG.addAMO.selector);
        permissions[4] = Permissions(lqregKeycode, LQREG.removeAMO.selector);
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

        // Gather tokens for deposit
        pairToken.transferFrom(msg.sender, address(this), amount_);
        _borrow(ohmToBorrow);

        uint256 lpReceived = _deposit(ohmToBorrow, amount_, minLpAmount_);
        totalLP += lpReceived;

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

        _withdrawUpdateRewardState(lpAmount_, claim_);

        totalLP -= lpAmount_;
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
    function claimRewards() external returns () {
        uint256 numExternalRewardTokens = externalRewardTokens.length;
        uint256 numRewardTokens = rewardTokens.length;

        for (uint256 i; i < numExternalRewardTokens; ) {
            _claimExternalRewards(i);

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
    /// @return int256              The amount of rewards the user has earned
    function rewardsForToken(uint256 id_, address user_) public view returns (int256) {
        InternalRewardToken memory rewardToken = rewardTokens[id_];
        uint256 accumulatedRewardsPerShare = rewardToken.accumulatedRewardsPerShare;

        if (block.timestamp > rewardToken.lastRewardTime && totalLP != 0) {
            uint256 timeDiff = block.timestamp - rewardToken.lastRewardTime;
            uint256 totalRewards = (timeDiff * rewardToken.rewardsPerSecond);
            accumulatedRewardsPerShare += (totalRewards * 1e18) / totalLP;
        }

        return
            int256((lpPositions[user_] * accumulatedRewardsPerShare) / 1e18) -
            userRewardDebts[user_][rewardToken.token];
    }

    /// @notice                     Returns the amount of rewards a user has earned for a given external reward token
    /// @param  id_                 The ID of the external reward token
    /// @param  user_               The user's address to check rewards for
    /// @return int256              The amount of rewards the user has earned
    function externalRewardsForToken(uint256 id_, address user_) public view returns (int256) {
        ExternalRewardToken memory rewardToken = externalRewardTokens[id_];
        uint256 accumulatedRewardsPerShare = rewardToken.accumulatedRewardsPerShare;

        return
            int256((lpPositions[user_] * accumulatedRewardsPerShare) / 1e18) -
            userRewardDebts[user_][rewardToken.token];
    }

    /// @notice                     Calculates the net amount of OHM that this contract has emitted to or removed from the broader market
    /// @return emitted             The amount of OHM that this contract has emitted to the broader market
    /// @return removed             The amount of OHM that this contract has removed from the broader market
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

    // ========= CHECKS AND SAFETY ========= //

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

    // ========= OHM MANAGEMENT ========= //

    function _borrow(uint256 amount_) internal {
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    function _repay(uint256 amount_) internal {
        MINTR.burnOhm(address(this), amount_);
    }

    // ========= REWARDS CALCULATIONS ========= //

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

    // ========= ACCUMULATED REWARDS STATE MANAGEMENT ========= //

    function _updateInternalRewardState(uint256 id_, uint256 amountAccumulated_) internal {
        InternalRewardToken storage rewardToken = rewardTokens[id_];

        if (totalLP != 0) {
            rewardToken.accumulatedRewardsPerShare += (amountAccumulated_ * 1e18) / totalLP;
            rewardToken.lastRewardTime = block.timestamp;
        }
    }

    function _updateExternalRewardState(uint256 id_, uint256 amountAccumulated_) internal {
        ExternalRewardToken storage rewardToken = externalRewardTokens[id_];

        if (totalLP != 0) {
            rewardToken.accumulatedRewardsPerShare += (amountAccumulated_ * 1e18) / totalLP;
        }
    }

    // ========= PRE/POST ACTION HOOKS ========= //

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
            userRewardDebts[msg.sender][rewardToken] += int256(
                (lpReceived_ * rewardTokens[i].accumulatedRewardsPerShare) / 1e18
            );

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numExternalRewardTokens; ) {
            address rewardToken = externalRewardTokens[i].token;
            userRewardDebts[msg.sender][rewardToken] += int256(
                (lpReceived_ * externalRewardTokens[i].accumulatedRewardsPerShare) / 1e18
            );

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
            if (claim_) _claimExternalRewards(i);

            ExternalRewardToken memory rewardToken = externalRewardTokens[i];
            userRewardDebts[msg.sender][rewardToken.token] -= int256(
                (lpAmount_ * rewardToken.accumulatedRewardsPerShare) / 1e18
            );

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numRewardTokens; ) {
            _updateInternalRewardState(i, accumulatedInternalRewards[i]);
            if (claim_) _claimRewards(i);

            // TODO FIX THIS UNDERFLOW WHEN NO CLAIM
            InternalRewardToken memory rewardToken = rewardTokens[i];
            userRewardDebts[msg.sender][rewardToken.token] -= int256(
                (lpAmount_ * rewardToken.accumulatedRewardsPerShare) / 1e18
            );

            unchecked {
                ++i;
            }
        }
    }

    // ========= REWARDS CLAIMING ========= //

    function _claimExternalRewards(uint256 id_) internal virtual returns (uint256) {
        ExternalRewardToken memory rewardToken = externalRewardTokens[id_];
        int256 reward = externalRewardsForToken(id_, msg.sender);
        uint256 fee = (uint256(reward) * FEE) / PRECISION;

        userRewardDebts[msg.sender][rewardToken.token] += reward;
        accumulatedFees[rewardToken.token] += fee;

        if (reward > 0) ERC20(rewardToken.token).transfer(msg.sender, uint256(reward) - fee);
    }

    function _claimRewards(uint256 id_) internal returns (uint256) {
        InternalRewardToken memory rewardToken = rewardTokens[id_];
        int256 reward = rewardsForToken(id_, msg.sender);
        uint256 fee = (uint256(reward) * FEE) / PRECISION;

        userRewardDebts[msg.sender][rewardToken.token] += reward;
        accumulatedFees[rewardToken.token] += fee;

        if (reward > 0) ERC20(rewardToken.token).transfer(msg.sender, uint256(reward) - fee);
    }

    //============================================================================================//
    //                                     VIRTUAL FUNCTIONS                                      //
    //============================================================================================//

    /// @notice                 Calculates the equivalent OHM amount for a given amount of partner tokens
    /// @param amount_          The amount of partner tokens to calculate the OHM value of
    /// @return uint256         The OHM value of the given amount of partner tokens
    function _valueCollateral(uint256 amount_) internal view virtual returns (uint256) {}

    /// @notice                 Calculates the current price of the liquidity pool in OHM/TKN
    /// @return uint256         The current price of the liquidity pool in OHM/TKN
    function _getPoolPrice() internal view virtual returns (uint256) {}

    /// @notice                 Calculates the contract's current share of OHM in the liquidity pool
    /// @return uint256         The contract's current share of OHM in the liquidity pool
    function _getPoolOhmShare() internal view virtual returns (uint256) {}

    /// @notice                 Deposits OHM and partner tokens into the liquidity pool
    /// @param ohmAmount_       The amount of OHM to deposit
    /// @param pairAmount_      The amount of partner tokens to deposit
    /// @param minLpAmount_     The minimum amount of liquidity pool tokens to receive
    /// @return uint256         The amount of liquidity pool tokens received
    /// @dev                    This function should also handle deposits into any external staking pools like Aura or Convex
    function _deposit(
        uint256 ohmAmount_,
        uint256 pairAmount_,
        uint256 minLpAmount_
    ) internal virtual returns (uint256) {}

    /// @notice                 Withdraws OHM and partner tokens from the liquidity pool
    /// @param lpAmount_        The amount of liquidity pool tokens to withdraw
    /// @param minTokenAmounts_ The minimum amounts of OHM and partner tokens to receive
    /// @return uint256         The amount of OHM received
    /// @return uint256         The amount of partner tokens received
    /// @dev                    This function should also handle withdrawals from any external staking pools like Aura or Convex
    function _withdraw(uint256 lpAmount_, uint256[] calldata minTokenAmounts_)
        internal
        virtual
        returns (uint256, uint256)
    {}

    /// @notice                 Harvests any external rewards from sources like Aura or Convex
    /// @return uint256[]       The amounts of each external reward token harvested
    function _accumulateExternalRewards() internal virtual returns (uint256[] memory) {}

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                 Registers the AMO in the LQREG contract
    /// @dev                    This function can only be accessed by the liquidityamo_admin role
    function activate() external onlyRole("liquidityamo_admin") {
        LQREG.addAMO(address(this));
    }

    /// @notice                 Unregisters the AMO in the LQREG contract and sets the borrowable limit to 0
    /// @dev                    This function can only be accessed by the liquidityamo_admin role
    function deactivate(uint256 id_) external onlyRole("liquidityamo_admin") {
        LIMIT = 0;
        LQREG.removeAMO(id_, address(this));
    }

    /// @notice                    Adds a new reward token to the contract
    /// @param  token_             The address of the reward token
    /// @param  rewardsPerSecond_  The amount of reward tokens to distribute per second
    /// @param  startTimestamp_    The timestamp at which to start distributing rewards
    /// @dev                       This function can only be accessed by the liquidityamo_admin role
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

    /// @notice                 Removes a reward token from the contract
    /// @param  id_             The index of the reward token to remove
    /// @param  token_          The address of the reward token to remove
    /// @dev                    This function can only be accessed by the liquidityamo_admin role
    function removeRewardToken(uint256 id_, address token_)
        external
        onlyRole("liquidityamo_admin")
    {
        if (rewardTokens[id_].token != token_) revert LiquidityAMO_InvalidRemoval();

        // Delete reward token from array by swapping with the last element and popping
        rewardTokens[id_] = rewardTokens[rewardTokens.length - 1];
        rewardTokens.pop();
    }

    /// @notice                 Adds a new external reward token to the contract
    /// @param  token_          The address of the reward token
    /// @dev                    This function can only be accessed by the liquidityamo_admin role
    function addExternalRewardToken(address token_) external onlyRole("liquidityamo_admin") {
        ExternalRewardToken memory newRewardToken = ExternalRewardToken({
            token: token_,
            accumulatedRewardsPerShare: 0
        });

        externalRewardTokens.push(newRewardToken);
    }

    /// @notice                 Removes an external reward token from the contract
    /// @param  id_             The index of the reward token to remove
    /// @param  token_          The address of the reward token to remove
    /// @dev                    This function can only be accessed by the liquidityamo_admin role
    function removeExternalRewardToken(uint256 id_, address token_)
        external
        onlyRole("liquidityamo_admin")
    {
        if (externalRewardTokens[id_].token != token_) revert LiquidityAMO_InvalidRemoval();

        // Delete reward token from array by swapping with the last element and popping
        externalRewardTokens[id_] = externalRewardTokens[externalRewardTokens.length - 1];
        externalRewardTokens.pop();
    }

    /// @notice                    Transfers accumulated fees on reward tokens to the admin
    /// @dev                       This function can only be accessed by the liquidityamo_admin role
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
    /// @dev                       This function can only be accessed by the liquidityamo_admin role
    function setLimit(uint256 limit_) external onlyRole("liquidityamo_admin") {
        LIMIT = limit_;
    }

    /// @notice                    Updates the threshold for the price deviation from the oracle price that is acceptable
    /// @param  threshold_         The new threshold (out of 1000)
    /// @dev                       This function can only be accessed by the liquidityamo_admin role
    function setThreshold(uint256 threshold_) external onlyRole("liquidityamo_admin") {
        THRESHOLD = threshold_;
    }

    /// @notice                    Updates the fee charged on rewards
    /// @param  fee_               The new fee (out of 1000)
    /// @dev                       This function can only be accessed by the liquidityamo_admin role
    function setFee(uint256 fee_) external onlyRole("liquidityamo_admin") {
        FEE = fee_;
    }
}
