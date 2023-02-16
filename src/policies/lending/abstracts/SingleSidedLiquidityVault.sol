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
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

// Import utilities
import {TransferHelper} from "libraries/TransferHelper.sol";

/// @title  Olympus Base Single Sided Liquidity Vault Contract
/// @dev    Some caveats around this contract:
///         - No internal reward token should also be an external reward token
///         - No pair token should also be an external reward token
///         - No pair, internal reward, or external reward tokens should be ERC777s or non-standard ERC20s
abstract contract SingleSidedLiquidityVault is Policy, ReentrancyGuard, RolesConsumer {
    using TransferHelper for ERC20;

    // ========= ERRORS ========= //

    error LiquidityVault_Inactive();
    error LiquidityVault_StillActive();
    error LiquidityVault_LimitViolation();
    error LiquidityVault_PoolImbalanced();
    error LiquidityVault_BadPriceFeed();
    error LiquidityVault_InvalidRemoval();
    error LiquidityVault_InvalidParams();

    // ========= EVENTS ========= //

    event Deposit(address indexed user, uint256 pairAmount, uint256 ohmMinted);
    event Withdraw(address indexed user, uint256 pairAmount, uint256 ohmBurned);
    event RewardsClaimed(address indexed user, address indexed token, uint256 amount);

    // ========= DATA STRUCTURES ========= //

    struct InternalRewardToken {
        address token;
        uint256 decimalsAdjustment;
        uint256 rewardsPerSecond;
        uint256 lastRewardTime;
        uint256 accumulatedRewardsPerShare;
    }

    struct ExternalRewardToken {
        address token;
        uint256 decimalsAdjustment;
        uint256 accumulatedRewardsPerShare;
        uint256 lastBalance;
    }

    // ========= STATE ========= //

    // Modules
    MINTRv1 public MINTR;
    LQREGv1 public LQREG;

    // Tokens
    OlympusERC20Token public ohm;
    ERC20 public pairToken;

    // Token Decimals
    uint256 public pairTokenDecimals;

    // Pool
    address public liquidityPool;

    // Aggregate Contract State
    uint256 public totalLP;
    uint256 public ohmMinted;
    uint256 public ohmRemoved;
    mapping(address => uint256) public accumulatedFees;

    // User State
    mapping(address => uint256) public pairTokenDeposits;
    mapping(address => uint256) public lpPositions;
    mapping(address => mapping(address => uint256)) public userRewardDebts; // Rewards accumulated prior to user's joining (MasterChef V2 math)
    mapping(address => mapping(address => uint256)) public cachedUserRewards; // Rewards that have been accumulated but not claimed (avoids underflow errors)
    mapping(address => bool) internal _hasDeposited; // Used to determine if a user has ever deposited
    address[] public users; // Used to track users that have interacted with this contract (for migration in the event of a bug)

    // Reward Token State
    /// @notice An internal reward token is a token where the vault is the only source of rewards and the
    ///         vault handles all accounting around how many reward tokens to distribute over time
    InternalRewardToken[] public internalRewardTokens;

    /// @notice An external reward token is a token where the primary accrual of reward tokens occurs outside
    ///         the scope of this contract in a system like Convex or Aura. The vault is responsible for harvesting
    ///         rewards back to the vault and then distributing them proportionally to users
    ExternalRewardToken[] public externalRewardTokens;

    // Exchange Name (used by frontend)
    string public EXCHANGE;

    // Configuration values
    uint256 public LIMIT;
    uint256 public THRESHOLD;
    uint256 public FEE;
    uint256 public constant PRECISION = 1000;
    bool public isVaultActive;

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
        ohm = OlympusERC20Token(ohm_);
        pairToken = ERC20(pairToken_);

        // Set token decimals
        pairTokenDecimals = pairToken.decimals();

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
        permissions[3] = Permissions(lqregKeycode, LQREG.addVault.selector);
        permissions[4] = Permissions(lqregKeycode, LQREG.removeVault.selector);
    }

    //============================================================================================//
    //                                           MODIFIERS                                        //
    //============================================================================================//

    modifier onlyWhileActive() {
        if (!isVaultActive) revert LiquidityVault_Inactive();
        _;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                 Deposits pair tokens, mints OHM against the deposited pair tokens, and deposits the
    ///                         pair token and OHM into a liquidity pool and receives LP tokens in return
    /// @param  amount_         The amount of pair tokens to deposit
    /// @param  slippageParam_  Represents the slippage on joining the liquidity pool. Can either be the minimum LP token
    ///                         amount to receive in the cases of Balancer or Curve, or can be a value (in thousandths) which
    ///                         will be used to calculate the minimum amount of OHM and pair tokens to use in the case of Uniswap,
    ///                         Sushiswap, Fraxswap, etc.
    /// @dev                    This needs to be non-reentrant since the contract only knows the amount of LP tokens it
    ///                         receives after an external interaction with the liquidity pool
    function deposit(uint256 amount_, uint256 slippageParam_)
        external
        onlyWhileActive
        nonReentrant
        returns (uint256 lpAmountOut)
    {
        // If this is a new user, add them to the users array in case we need to migrate
        // their state in the future
        if (!_hasDeposited[msg.sender]) {
            _hasDeposited[msg.sender] = true;
            users.push(msg.sender);
        }

        // Calculate amount of OHM to borrow
        uint256 ohmToBorrow = _valueCollateral(amount_);

        // Cache pair token and OHM balance before deposit
        uint256 pairTokenBalanceBefore = pairToken.balanceOf(address(this));
        uint256 ohmBalanceBefore = ohm.balanceOf(address(this));

        // The pool being imbalanced is less of a concern here on deposit than on withdrawal,
        // but in the event the frontend miscalculates the expected LP amount to receive, we want
        // to reduce the risk of entering a manipulated pool at a bad price
        if (!_isPoolSafe()) revert LiquidityVault_PoolImbalanced();
        if (!_canDeposit(ohmToBorrow)) revert LiquidityVault_LimitViolation();

        _depositUpdateRewardState();

        // Gather tokens for deposit
        pairToken.safeTransferFrom(msg.sender, address(this), amount_);
        _borrow(ohmToBorrow);

        uint256 lpReceived = _deposit(ohmToBorrow, amount_, slippageParam_);

        // Calculate amount of pair tokens and OHM unused in deposit
        uint256 unusedPairToken = pairToken.balanceOf(address(this)) - pairTokenBalanceBefore;
        uint256 unusedOhm = ohm.balanceOf(address(this)) - ohmBalanceBefore;

        // Return unused pair tokens to user
        if (unusedPairToken > 0) pairToken.safeTransfer(msg.sender, unusedPairToken);

        // Burn unused OHM
        if (unusedOhm > 0) _repay(unusedOhm);

        uint256 pairTokenUsed = amount_ - unusedPairToken;
        uint256 ohmUsed = ohmToBorrow - unusedOhm;

        ohmMinted += ohmUsed;
        totalLP += lpReceived;

        pairTokenDeposits[msg.sender] += pairTokenUsed;
        lpPositions[msg.sender] += lpReceived;

        // Update user's reward debts
        _depositUpdateRewardDebts(lpReceived);

        emit Deposit(msg.sender, pairTokenUsed, ohmUsed);
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
    ) external onlyWhileActive nonReentrant returns (uint256) {
        // Liquidity vaults should always be built around a two token pool so we can assume
        // the array will always have two elements
        if (lpAmount_ == 0 || minTokenAmounts_[0] == 0 || minTokenAmounts_[1] == 0)
            revert LiquidityVault_InvalidParams();
        if (!_isPoolSafe()) revert LiquidityVault_PoolImbalanced();

        _withdrawUpdateRewardState(lpAmount_, claim_);

        totalLP -= lpAmount_;
        lpPositions[msg.sender] -= lpAmount_;

        // Withdraw OHM and pairToken from LP
        (uint256 ohmReceived, uint256 pairTokenReceived) = _withdraw(lpAmount_, minTokenAmounts_);

        // Reduce deposit values
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;
        ohmMinted -= ohmReceived > ohmMinted ? ohmMinted : ohmReceived;
        ohmRemoved += ohmReceived > ohmMinted ? ohmReceived - ohmMinted : 0;

        // Return assets
        _repay(ohmReceived);
        pairToken.safeTransfer(msg.sender, pairTokenReceived);

        emit Withdraw(msg.sender, pairTokenReceived, ohmReceived);
        return pairTokenReceived;
    }

    /// @notice                     Claims user's rewards for all reward tokens
    function claimRewards() external onlyWhileActive nonReentrant {
        uint256 numInternalRewardTokens = internalRewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        uint256[] memory accumulatedRewards = _accumulateExternalRewards();

        for (uint256 i; i < numInternalRewardTokens; ) {
            _claimInternalRewards(i);

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numExternalRewardTokens; ) {
            _updateExternalRewardState(i, accumulatedRewards[i]);
            _claimExternalRewards(i);

            unchecked {
                ++i;
            }
        }
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                         Gets the max amount of pair tokens that can be deposited currently
    /// @return uint256                 The max amount of pair tokens that can be deposited currently
    function getMaxDeposit() public view returns (uint256) {
        uint256 currentPoolOhmShare = _getPoolOhmShare();
        uint256 emitted;

        // Calculate max OHM mintable amount
        if (ohmMinted > currentPoolOhmShare) emitted = ohmMinted - currentPoolOhmShare;
        uint256 maxOhmAmount = LIMIT + ohmRemoved - ohmMinted - emitted;

        // Convert max OHM mintable amount to pair token amount
        uint256 ohmPerPairToken = _valueCollateral(1e18); // OHM per 1 pairToken
        uint256 pairTokenDecimalAdjustment = 10**pairToken.decimals();
        return (maxOhmAmount * pairTokenDecimalAdjustment) / ohmPerPairToken;
    }

    /// @notice                         Gets all users that have deposited into the vault
    /// @return address[]               An array of all users that have deposited into the vault
    function getUsers() public view returns (address[] memory) {
        return users;
    }

    /// @notice                         Gets a list of all the internal reward tokens
    /// @return InternalRewardToken[]   An array of all the internal reward tokens
    function getInternalRewardTokens() public view returns (InternalRewardToken[] memory) {
        return internalRewardTokens;
    }

    /// @notice                         Gets a list of all the external reward tokens
    /// @return ExternalRewardToken[]   An array of all the external reward tokens
    function getExternalRewardTokens() public view returns (ExternalRewardToken[] memory) {
        return externalRewardTokens;
    }

    /// @notice                         Returns the amount of rewards a user has earned for a given reward token
    /// @param  id_                     The ID of the reward token
    /// @param  user_                   The user's address to check rewards for
    /// @return uint256                 The amount of rewards the user has earned
    function internalRewardsForToken(uint256 id_, address user_) public view returns (uint256) {
        InternalRewardToken memory rewardToken = internalRewardTokens[id_];
        uint256 lastRewardTime = rewardToken.lastRewardTime;
        uint256 accumulatedRewardsPerShare = rewardToken.accumulatedRewardsPerShare;

        if (block.timestamp > lastRewardTime && totalLP != 0) {
            uint256 timeDiff = block.timestamp - lastRewardTime;
            uint256 totalRewards = timeDiff * rewardToken.rewardsPerSecond;

            // This correctly uses 1e18 because the LP tokens of all major DEXs have 18 decimals
            accumulatedRewardsPerShare += (totalRewards * 1e18) / totalLP;
        }

        // This correctly uses 1e18 because the LP tokens of all major DEXs have 18 decimals
        uint256 totalAccumulatedRewards = (lpPositions[user_] * accumulatedRewardsPerShare) -
            userRewardDebts[user_][rewardToken.token];

        return (cachedUserRewards[user_][rewardToken.token] + totalAccumulatedRewards) / 1e18;
    }

    /// @notice                         Returns the amount of rewards a user has earned for a given external reward token
    /// @param  id_                     The ID of the external reward token
    /// @param  user_                   The user's address to check rewards for
    /// @return uint256                 The amount of rewards the user has earned
    function externalRewardsForToken(uint256 id_, address user_) public view returns (uint256) {
        ExternalRewardToken memory rewardToken = externalRewardTokens[id_];

        // This correctly uses 1e18 because the LP tokens of all major DEXs have 18 decimals
        uint256 totalAccumulatedRewards = (lpPositions[user_] *
            rewardToken.accumulatedRewardsPerShare) - userRewardDebts[user_][rewardToken.token];

        return (cachedUserRewards[user_][rewardToken.token] + totalAccumulatedRewards) / 1e18;
    }

    /// @notice                         Calculates the net amount of OHM that this contract has emitted to or removed from the broader market
    /// @return emitted                 The amount of OHM that this contract has emitted to the broader market
    /// @return removed                 The amount of OHM that this contract has removed from the broader market
    /// @dev                            This is based on a point-in-time snapshot of the liquidity pool's current OHM balance
    function getOhmEmissions() external view returns (uint256 emitted, uint256 removed) {
        uint256 currentPoolOhmShare = _getPoolOhmShare();

        if (ohmMinted > currentPoolOhmShare + ohmRemoved)
            emitted = ohmMinted - currentPoolOhmShare - ohmRemoved;
        else removed = currentPoolOhmShare + ohmRemoved - ohmMinted;
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    // ========= CHECKS AND SAFETY ========= //

    function _canDeposit(uint256 amount_) internal view virtual returns (bool) {
        if (amount_ + ohmMinted > LIMIT + ohmRemoved) revert LiquidityVault_LimitViolation();
        return true;
    }

    function _isPoolSafe() internal view returns (bool) {
        uint256 pairTokenDecimals = pairToken.decimals();
        uint256 poolPrice = _getPoolPrice();
        uint256 oraclePrice = _valueCollateral(10**pairTokenDecimals); // 1 pair token in OHM

        // Pool price should fall within a threshold of the oracle price
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
        ) revert LiquidityVault_BadPriceFeed();

        return uint256(priceInt);
    }

    // ========= OHM MANAGEMENT ========= //

    function _borrow(uint256 amount_) internal {
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    function _repay(uint256 amount_) internal {
        ohm.increaseAllowance(address(MINTR), amount_);
        MINTR.burnOhm(address(this), amount_);
    }

    // ========= REWARDS CALCULATIONS ========= //

    function _accumulateInternalRewards() internal view returns (uint256[] memory) {
        uint256 numInternalRewardTokens = internalRewardTokens.length;
        uint256[] memory accumulatedInternalRewards = new uint256[](numInternalRewardTokens);

        for (uint256 i; i < numInternalRewardTokens; ) {
            InternalRewardToken memory rewardToken = internalRewardTokens[i];

            uint256 totalRewards;
            if (totalLP > 0) {
                uint256 timeDiff = block.timestamp - rewardToken.lastRewardTime;
                totalRewards = (timeDiff * rewardToken.rewardsPerSecond);
            }

            accumulatedInternalRewards[i] = totalRewards;

            unchecked {
                ++i;
            }
        }

        return accumulatedInternalRewards;
    }

    // ========= ACCUMULATED REWARDS STATE MANAGEMENT ========= //

    function _updateInternalRewardState(uint256 id_, uint256 amountAccumulated_) internal {
        // This correctly uses 1e18 because the LP tokens of all major DEXs have 18 decimals
        InternalRewardToken storage rewardToken = internalRewardTokens[id_];
        if (totalLP != 0)
            rewardToken.accumulatedRewardsPerShare += (amountAccumulated_ * 1e18) / totalLP;
        rewardToken.lastRewardTime = block.timestamp;
    }

    function _updateExternalRewardState(uint256 id_, uint256 amountAccumulated_) internal {
        // This correctly uses 1e18 because the LP tokens of all major DEXs have 18 decimals
        if (totalLP != 0)
            externalRewardTokens[id_].accumulatedRewardsPerShare +=
                (amountAccumulated_ * 1e18) /
                totalLP;
    }

    // ========= PRE/POST ACTION HOOKS ========= //

    function _depositUpdateRewardState() internal {
        uint256 numInternalRewardTokens = internalRewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        // Handles accounting logic for internal and external rewards, harvests external rewards
        uint256[] memory accumulatedInternalRewards = _accumulateInternalRewards();
        uint256[] memory accumulatedExternalRewards = _accumulateExternalRewards();

        // Update internal reward token state
        // This has to be done before the contract receives any LP tokens which is why it's not baked into the
        // for loop for updating reward debts like in both withdrawal functions
        for (uint256 i; i < numInternalRewardTokens; ) {
            _updateInternalRewardState(i, accumulatedInternalRewards[i]);

            unchecked {
                ++i;
            }
        }

        // Update external reward token state
        for (uint256 i; i < numExternalRewardTokens; ) {
            _updateExternalRewardState(i, accumulatedExternalRewards[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _depositUpdateRewardDebts(uint256 lpReceived_) internal {
        uint256 numInternalRewardTokens = internalRewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        for (uint256 i; i < numInternalRewardTokens; ) {
            // Reward debts for this deposit should be equal to the rewards accrued for a given value
            // of LP tokens prior to the user joining the pool with the given value of LP tokens
            InternalRewardToken memory rewardToken = internalRewardTokens[i];
            userRewardDebts[msg.sender][rewardToken.token] +=
                lpReceived_ *
                rewardToken.accumulatedRewardsPerShare;

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numExternalRewardTokens; ) {
            // Reward debts for this deposit should be equal to the rewards accrued for a given value
            // of LP tokens prior to the user joining the pool with the given value of LP tokens
            ExternalRewardToken memory rewardToken = externalRewardTokens[i];
            userRewardDebts[msg.sender][rewardToken.token] +=
                lpReceived_ *
                rewardToken.accumulatedRewardsPerShare;

            unchecked {
                ++i;
            }
        }
    }

    function _withdrawUpdateRewardState(uint256 lpAmount_, bool claim_) internal {
        uint256 numInternalRewardTokens = internalRewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        // Handles accounting logic for internal and external rewards, harvests external rewards
        uint256[] memory accumulatedInternalRewards = _accumulateInternalRewards();
        uint256[] memory accumulatedExternalRewards = _accumulateExternalRewards();

        for (uint256 i; i < numInternalRewardTokens; ) {
            _updateInternalRewardState(i, accumulatedInternalRewards[i]);
            if (claim_) _claimInternalRewards(i);

            // Update reward debts so as to not understate the amount of rewards owed to the user, and push
            // any unclaimed rewards to the user's reward debt so that they can be claimed later
            InternalRewardToken memory rewardToken = internalRewardTokens[i];
            uint256 rewardDebtDiff = lpAmount_ * rewardToken.accumulatedRewardsPerShare;

            if (rewardDebtDiff > userRewardDebts[msg.sender][rewardToken.token]) {
                userRewardDebts[msg.sender][rewardToken.token] = 0;
                cachedUserRewards[msg.sender][rewardToken.token] +=
                    rewardDebtDiff -
                    userRewardDebts[msg.sender][rewardToken.token];
            } else {
                userRewardDebts[msg.sender][rewardToken.token] -= rewardDebtDiff;
            }

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numExternalRewardTokens; ) {
            _updateExternalRewardState(i, accumulatedExternalRewards[i]);
            if (claim_) _claimExternalRewards(i);

            // Update reward debts so as to not understate the amount of rewards owed to the user, and push
            // any unclaimed rewards to the user's reward debt so that they can be claimed later
            ExternalRewardToken memory rewardToken = externalRewardTokens[i];
            uint256 rewardDebtDiff = lpAmount_ * rewardToken.accumulatedRewardsPerShare;

            if (rewardDebtDiff > userRewardDebts[msg.sender][rewardToken.token]) {
                userRewardDebts[msg.sender][rewardToken.token] = 0;
                cachedUserRewards[msg.sender][rewardToken.token] +=
                    rewardDebtDiff -
                    userRewardDebts[msg.sender][rewardToken.token];
            } else {
                userRewardDebts[msg.sender][rewardToken.token] -= rewardDebtDiff;
            }

            unchecked {
                ++i;
            }
        }
    }

    // ========= REWARDS CLAIMING ========= //

    function _claimInternalRewards(uint256 id_) internal {
        address rewardToken = internalRewardTokens[id_].token;
        uint256 reward = internalRewardsForToken(id_, msg.sender);
        uint256 fee = (reward * FEE) / PRECISION;

        userRewardDebts[msg.sender][rewardToken] += reward;
        accumulatedFees[rewardToken] += fee;

        if (reward > 0) ERC20(rewardToken).safeTransfer(msg.sender, reward - fee);

        emit RewardsClaimed(msg.sender, rewardToken, reward - fee);
    }

    function _claimExternalRewards(uint256 id_) internal {
        ExternalRewardToken storage rewardToken = externalRewardTokens[id_];
        uint256 reward = externalRewardsForToken(id_, msg.sender);
        uint256 fee = (reward * FEE) / PRECISION;

        userRewardDebts[msg.sender][rewardToken.token] += reward;
        accumulatedFees[rewardToken.token] += fee;

        if (reward > 0) ERC20(rewardToken.token).safeTransfer(msg.sender, reward - fee);
        rewardToken.lastBalance = ERC20(rewardToken.token).balanceOf(address(this));

        emit RewardsClaimed(msg.sender, rewardToken.token, reward - fee);
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @notice                 Registers the vault in the LQREG contract
    /// @dev                    This function can only be accessed by the liquidityvault_admin role
    function activate() external onlyRole("liquidityvault_admin") {
        isVaultActive = true;
        LQREG.addVault(address(this));
    }

    /// @notice                 Unregisters the vault in the LQREG contract and sets the borrowable limit to 0
    /// @dev                    This function can only be accessed by the liquidityvault_admin role
    function deactivate() external onlyRole("liquidityvault_admin") {
        LIMIT = 0;
        isVaultActive = false;
        LQREG.removeVault(address(this));
    }

    /// @notice                    Adds a new internal reward token to the contract
    /// @param  token_             The address of the reward token
    /// @param  rewardsPerSecond_  The amount of reward tokens to distribute per second
    /// @param  startTimestamp_    The timestamp at which to start distributing rewards
    /// @dev                       This function can only be accessed by the liquidityvault_admin role
    function addInternalRewardToken(
        address token_,
        uint256 rewardsPerSecond_,
        uint256 startTimestamp_
    ) external onlyRole("liquidityvault_admin") {
        InternalRewardToken memory newInternalRewardToken = InternalRewardToken({
            token: token_,
            decimalsAdjustment: 10**ERC20(token_).decimals(),
            rewardsPerSecond: rewardsPerSecond_,
            lastRewardTime: block.timestamp > startTimestamp_ ? block.timestamp : startTimestamp_,
            accumulatedRewardsPerShare: 0
        });

        internalRewardTokens.push(newInternalRewardToken);
    }

    /// @notice                 Removes an internal reward token from the contract
    /// @param  id_             The index of the reward token to remove
    /// @param  token_          The address of the reward token to remove
    /// @dev                    This function can only be accessed by the liquidityvault_admin role
    function removeInternalRewardToken(uint256 id_, address token_)
        external
        onlyRole("liquidityvault_admin")
    {
        if (internalRewardTokens[id_].token != token_) revert LiquidityVault_InvalidRemoval();

        // Delete reward token from array by swapping with the last element and popping
        internalRewardTokens[id_] = internalRewardTokens[internalRewardTokens.length - 1];
        internalRewardTokens.pop();
    }

    /// @notice                 Adds a new external reward token to the contract
    /// @param  token_          The address of the reward token
    /// @dev                    This function can only be accessed by the liquidityvault_admin role
    function addExternalRewardToken(address token_) external onlyRole("liquidityvault_admin") {
        ExternalRewardToken memory newRewardToken = ExternalRewardToken({
            token: token_,
            decimalsAdjustment: 10**ERC20(token_).decimals(),
            accumulatedRewardsPerShare: 0,
            lastBalance: 0
        });

        externalRewardTokens.push(newRewardToken);
    }

    /// @notice                 Removes an external reward token from the contract
    /// @param  id_             The index of the reward token to remove
    /// @param  token_          The address of the reward token to remove
    /// @dev                    This function can only be accessed by the liquidityvault_admin role
    function removeExternalRewardToken(uint256 id_, address token_)
        external
        onlyRole("liquidityvault_admin")
    {
        if (externalRewardTokens[id_].token != token_) revert LiquidityVault_InvalidRemoval();

        // Delete reward token from array by swapping with the last element and popping
        externalRewardTokens[id_] = externalRewardTokens[externalRewardTokens.length - 1];
        externalRewardTokens.pop();
    }

    /// @notice                    Transfers accumulated fees on reward tokens to the admin
    /// @dev                       This function can only be accessed by the liquidityvault_admin role
    function claimFees() external onlyRole("liquidityvault_admin") {
        uint256 numInternalRewardTokens = internalRewardTokens.length;
        uint256 numExternalRewardTokens = externalRewardTokens.length;

        for (uint256 i; i < numInternalRewardTokens; ) {
            address rewardToken = internalRewardTokens[i].token;
            uint256 feeToSend = accumulatedFees[rewardToken];

            accumulatedFees[rewardToken] = 0;

            ERC20(rewardToken).safeTransfer(msg.sender, feeToSend);

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < numExternalRewardTokens; ) {
            ExternalRewardToken storage rewardToken = externalRewardTokens[i];
            uint256 feeToSend = accumulatedFees[rewardToken.token];

            accumulatedFees[rewardToken.token] = 0;

            ERC20(rewardToken.token).safeTransfer(msg.sender, feeToSend);
            rewardToken.lastBalance = ERC20(rewardToken.token).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }
    }

    /// @notice                   Transfers tokens from the contract to the admin
    /// @param  token_            The address of the token to transfer
    /// @param  amount_           The amount of tokens to transfer
    /// @dev                      This function can only be accessed by the liquidityvault_admin role and only when
    ///                           the vault is deactivated. This acts as an emergency migration function in the event
    ///                           that the vault is compromised.
    function rescueToken(address token_, uint256 amount_)
        external
        onlyRole("liquidityvault_admin")
    {
        if (isVaultActive) revert LiquidityVault_StillActive();
        ERC20(token_).safeTransfer(msg.sender, amount_);
    }

    /// @notice                    Updates the maximum amount of OHM that can be minted by this contract
    /// @param  limit_             The new limit
    /// @dev                       This function can only be accessed by the liquidityvault_admin role
    function setLimit(uint256 limit_) external onlyRole("liquidityvault_admin") {
        if (limit_ < ohmMinted) revert LiquidityVault_InvalidParams();
        LIMIT = limit_;
    }

    /// @notice                    Updates the threshold for the price deviation from the oracle price that is acceptable
    /// @param  threshold_         The new threshold (out of 1000)
    /// @dev                       This function can only be accessed by the liquidityvault_admin role
    function setThreshold(uint256 threshold_) external onlyRole("liquidityvault_admin") {
        if (threshold_ > PRECISION) revert LiquidityVault_InvalidParams();
        THRESHOLD = threshold_;
    }

    /// @notice                    Updates the fee charged on rewards
    /// @param  fee_               The new fee (out of 1000)
    /// @dev                       This function can only be accessed by the liquidityvault_admin role
    function setFee(uint256 fee_) external onlyRole("liquidityvault_admin") {
        if (fee_ > PRECISION) revert LiquidityVault_InvalidParams();
        FEE = fee_;
    }

    //============================================================================================//
    //                                     VIRTUAL FUNCTIONS                                      //
    //============================================================================================//

    /// @notice                 Calculates the expected amount of LP tokens to receive for a given pair token
    ///                         deposit. This is useful for the frontend to have a standard interface across vaults
    function getExpectedLPAmount(uint256 amount_) public virtual returns (uint256) {}

    /// @notice                 Calculates the equivalent OHM amount for a given amount of partner tokens
    /// @param amount_          The amount of partner tokens to calculate the OHM value of
    /// @return uint256         The OHM value of the given amount of partner tokens
    function _valueCollateral(uint256 amount_) public view virtual returns (uint256) {}

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
}
