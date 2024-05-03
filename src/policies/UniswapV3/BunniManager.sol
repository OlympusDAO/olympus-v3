// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Standard libraries
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FullMath} from "libraries/FullMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Bophades
import {Kernel, Permissions, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {toSubKeycode} from "src/Submodules.sol";

// Bophades modules
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1, TRSRYv1_1, toCategory as toTreasuryCategory} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {SPPLYv1} from "modules/SPPLY/SPPLY.v1.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Libraries
import {BunniHelper} from "libraries/UniswapV3/BunniHelper.sol";
import {UniswapV3Positions} from "libraries/UniswapV3/Positions.sol";
import {UniswapV3PoolLibrary} from "libraries/UniswapV3/PoolLibrary.sol";

// Bunni
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniManager} from "policies/UniswapV3/interfaces/IBunniManager.sol";

/// @title  BunniManager
/// @author 0xJem
/// @notice Bophades policy to manage UniswapV3 positions
/// @dev    The policy is required as Uniswap V3 positions are not ERC20-compatible,
/// @dev    and the TRSRY module is unable to custody them. This policy uses the Bunni framework
/// @dev    to deploy ERC20-compatible tokens that represent the Uniswap V3 positions.
///
/// @dev    This policy is paired with a BunniHub instance to manage the lifecycle of BunniTokens.
///
/// @dev    Most of the functions are permissioned and require the "bunni_admin" role.
///
/// @dev    What this policy does not cover:
/// @dev    - Migrating positions between BunniHub deployments. (This could be achieved by withdrawing and depositing into the new BunniHub instance.)
/// @dev    - Migrating positions between Uniswap V3 pools. (This could be achieved by withdrawing and depositing into the new Uniswap V3 pool.)
/// @dev    - Managing positions that were not deployed by this policy. (This could be achieved by deploying a new BunniToken and depositing into it.)
/// @dev    - Migrating LP tokens between addresses. (This could be achieved by transferring the ERC20 tokens to the new address.)
/// @dev    - Setting the protocol fee on the BunniHub instance (applied when compounding pool fees), as there is no use for having the protocol fees applied.
contract BunniManager is IBunniManager, Policy, RolesConsumer, ReentrancyGuard {
    using FullMath for uint256;

    //============================================================================================//
    //                                      EVENTS                                                //
    //============================================================================================//

    /// @notice             Emitted when the BunniLens and BunniHub is set on the policy
    ///
    /// @param newBunniHub_ The address of the new BunniHub
    /// @param newBunniLens_ The address of the new BunniLens
    event BunniLensSet(address indexed newBunniHub_, address indexed newBunniLens_);

    /// @notice             Emitted when the owner of the BunniHub is set on the policy
    ///
    /// @param bunniHub_    The address of the BunniHub
    /// @param newOwner_    The address of the new owner
    event BunniHubOwnerSet(address indexed bunniHub_, address indexed newOwner_);

    /// @notice                 Emitted when the last harvest timestamp is reset
    ///
    /// @param newLastHarvest_  The new last harvest timestamp
    event LastHarvestReset(uint48 newLastHarvest_);

    /// @notice                 Emitted when the harvest frequency is set
    ///
    /// @param newFrequency_    The new harvest frequency
    event HarvestFrequencySet(uint48 newFrequency_);

    /// @notice                 Emitted when the harvest reward parameters are set
    ///
    /// @param newMaxReward_    The new max reward
    /// @param newFee_          The new fee
    event HarvestRewardParamsSet(uint256 newMaxReward_, uint16 newFee_);

    /// @notice                 Emitted when a BunniToken (ERC20-compatible) token is activated/deactivated for `pool_`
    ///
    /// @param pool             The address of the Uniswap V3 pool
    /// @param token            The address of the BunniToken
    /// @param activated        Whether the token was activated or deactivated
    event PoolTokenStatusChanged(
        address indexed pool,
        address indexed token,
        bool indexed activated
    );

    /// @notice                 Emitted when the swap fees of a pool are updated
    ///
    /// @param pool_            The address of the Uniswap V3 pool
    event PoolSwapFeesUpdated(address indexed pool_);

    //============================================================================================//
    //                                      ERRORS                                                //
    //============================================================================================//

    /// @notice                 Emitted if the given parameters were invalid
    error BunniManager_InvalidParams();

    /// @notice   Emitted if the BunniHub has not been set
    error BunniManager_HubNotSet();

    /// @notice         Emitted if the pool liquidity is invalid for the operation
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    error BunniManager_InvalidPoolLiquidity(address pool_);

    /// @notice                 Emitted if the caller does not have sufficient balance to deposit
    ///
    /// @param token_           The address of the token
    /// @param requiredBalance_ The required balance
    /// @param actualBalance_   The actual balance
    error BunniManager_InsufficientBalance(
        address token_,
        uint256 requiredBalance_,
        uint256 actualBalance_
    );

    /// @notice         Emitted if the policy is inactive
    error BunniManager_Inactive();

    /// @notice         Emitted if harvest is being called too early
    error BunniManager_HarvestTooEarly(uint48 nextHarvest_);

    //============================================================================================//
    //                                      STATE                                                 //
    //============================================================================================//

    /// @notice     Address of the BunniHub instance that this policy interfaces with
    BunniHub public bunniHub;

    /// @notice     Address of the BunniLens instance that this policy interfaces with
    BunniLens public bunniLens;

    /// @notice     Timestamp of the last harvest (UTC, in seconds)
    uint48 public lastHarvest;

    /// @notice     Minimum seconds between harvesting of pool fees
    uint48 public harvestFrequency;

    /// @notice     Max reward for harvesting (in reward token decimals)
    uint256 public harvestRewardMax;

    /// @notice     Percentage of the pool fees to reward (in basis points)
    uint16 public harvestRewardFee;

    /// @notice     The pools that have been deployed by this policy
    address[] public pools;

    /// @notice     An array of unique tokens that have been used in the pools
    ERC20[] internal poolUnderlyingTokens;

    address internal ohm;

    // Modules
    TRSRYv1_1 internal TRSRY;
    PRICEv2 internal PRICE;
    MINTRv1 internal MINTR;
    SPPLYv1 internal SPPLY;

    // Constants
    uint16 private constant BPS_MAX = 10_000; // 100%

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    /// @dev    The BunniLens and BunniHub contracts cannot be passed into the constructor, as it requires the owner to
    ///         be set to this contract. Therefore, the BunniLens must be set manually after deployment using `setBunniLens`.
    constructor(
        Kernel kernel_,
        uint256 harvestRewardMax_,
        uint16 harvestRewardFee_,
        uint48 harvestFrequency_
    ) Policy(kernel_) {
        lastHarvest = uint48(block.timestamp);
        harvestRewardMax = harvestRewardMax_;
        harvestRewardFee = harvestRewardFee_;
        harvestFrequency = harvestFrequency_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        dependencies[2] = toKeycode("PRICE");
        dependencies[3] = toKeycode("MINTR");
        dependencies[4] = toKeycode("SPPLY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1_1(getModuleAddress(dependencies[1]));
        PRICE = PRICEv2(getModuleAddress(dependencies[2]));
        MINTR = MINTRv1(getModuleAddress(dependencies[3]));
        ohm = address(MINTR.ohm());
        SPPLY = SPPLYv1(getModuleAddress(dependencies[4]));

        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, uint8 TRSRY_MINOR) = TRSRY.VERSION();
        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 SPPLY_MAJOR, ) = SPPLY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 2, 1, 1, 1]);
        if (
            MINTR_MAJOR != 1 ||
            PRICE_MAJOR != 2 ||
            ROLES_MAJOR != 1 ||
            SPPLY_MAJOR != 1 ||
            TRSRY_MAJOR != 1
        ) revert Policy_WrongModuleVersion(expected);

        // Check TRSRY minor version
        if (TRSRY_MINOR < 1) revert Policy_WrongModuleVersion(expected);

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ERC20(ohm).approve(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();
        Keycode PRICE_KEYCODE = PRICE.KEYCODE();
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();
        Keycode SPPLY_KEYCODE = SPPLY.KEYCODE();

        requests = new Permissions[](14);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseWithdrawApproval.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        requests[5] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        requests[6] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);
        requests[7] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        requests[8] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        requests[9] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[10] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[11] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        requests[12] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
        requests[13] = Permissions(SPPLY_KEYCODE, SPPLY.execOnSubmodule.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    // =========  POOL REGISTRATION ========= //

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    /// @dev        - The policy is inactive
    /// @dev        - The caller is unauthorized
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - The pool is already registered with this policy
    /// @dev        - No BunniToken has been deployed for the pool
    /// @dev        - `pool_` is not a Uniswap V3 pool
    /// @dev        - A price cannot be accessed for either token in the pool
    function registerPool(
        address pool_
    )
        external
        override
        nonReentrant
        onlyIfActive
        onlyRole("bunni_admin")
        bunniHubSet
        returns (IBunniToken)
    {
        // Check that `pool_` is an actual Uniswap V3 pool
        _assertIsValidPool(pool_);

        // Get the BunniToken or revert
        IBunniToken token = getPoolToken(pool_);

        // Check if the pool is already registered
        uint256 poolCount = pools.length;
        for (uint256 i = 0; i < poolCount; i++) {
            if (pools[i] == pool_) revert BunniManager_InvalidParams();
        }

        // Check that both tokens from the pool have prices (else PRICE will revert)
        (address poolToken0, address poolToken1) = UniswapV3PoolLibrary.getPoolTokens(pool_);
        PRICE.getPrice(poolToken0);
        PRICE.getPrice(poolToken1);

        // Add the underlying tokens to the list
        _addUnderlyingToken(poolToken0);
        _addUnderlyingToken(poolToken1);

        // Add the pool to the registry
        pools.push(pool_);

        return token;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    /// @dev        - The policy is inactive
    /// @dev        - The caller is unauthorized
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - `pool_` is not a Uniswap V3 pool
    /// @dev        - A BunniToken has already been deployed for the pool
    /// @dev        - A price cannot be accessed for either token in the pool
    function deployPoolToken(
        address pool_
    )
        external
        override
        nonReentrant
        onlyIfActive
        onlyRole("bunni_admin")
        bunniHubSet
        returns (IBunniToken)
    {
        // Check that `pool_` is an actual Uniswap V3 pool
        _assertIsValidPool(pool_);

        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(pool_);

        // Check if a token for the pool has been deployed already
        if (address(bunniHub.getBunniToken(key)) != address(0)) revert BunniManager_InvalidParams();

        // Check that both tokens from the pool have prices (else PRICE will revert)
        (address poolToken0, address poolToken1) = UniswapV3PoolLibrary.getPoolTokens(pool_);
        PRICE.getPrice(poolToken0);
        PRICE.getPrice(poolToken1);

        // Add the underlying tokens to the list
        _addUnderlyingToken(poolToken0);
        _addUnderlyingToken(poolToken1);

        // Update the pools variable
        pools.push(pool_);

        // Deploy
        return bunniHub.deployBunniToken(key);
    }

    // =========  POOL ACTIVATION ========= //

    /// @inheritdoc IBunniManager
    /// @dev                            This function reverts if:
    /// @dev                            - The policy is inactive
    /// @dev                            - The caller is unauthorized
    /// @dev                            - The `bunniHub` state variable is not set
    /// @dev                            - An ERC20 token for `pool_` has not been deployed/registered
    /// @dev                            - The position representing `pool_` has no liquidity
    /// @dev                            - The ERC20 token for `pool_` has already been activated in TRSRY/SPPLY/PRICE
    function activatePoolToken(
        address pool_,
        uint32 priceMovingAverageDuration_,
        uint48 priceLastObservationTime_,
        uint256[] memory priceObservations_,
        uint32 reserveMovingAverageDuration_,
        uint48 reserveLastObservationTime_,
        uint256[] memory reserveToken0Observations_,
        uint256[] memory reserveToken1Observations_
    ) external override nonReentrant onlyIfActive onlyRole("bunni_admin") bunniHubSet {
        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(pool_);

        // Check that the token has been deployed
        address poolTokenAddress = address(_getPoolToken(key));

        // Check that the position has liquidity
        if (
            !UniswapV3Positions.positionHasLiquidity(
                key.pool,
                key.tickLower,
                key.tickUpper,
                address(bunniHub)
            )
        ) revert BunniManager_InvalidPoolLiquidity(pool_);

        // Register the pool token with TRSRY, PRICE and SPPLY (each will check for prior activation)
        _addPoolTokenToPRICE(
            poolTokenAddress,
            priceMovingAverageDuration_,
            priceLastObservationTime_,
            priceObservations_
        );
        _addPoolTokenToTRSRY(poolTokenAddress);
        _addPoolTokenToSPPLY(
            poolTokenAddress,
            reserveMovingAverageDuration_,
            reserveLastObservationTime_,
            reserveToken0Observations_,
            reserveToken1Observations_
        );

        emit PoolTokenStatusChanged(pool_, poolTokenAddress, true);
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function will deactivate the pool token by de-registering it in TRSRY, PRICE and SPPLY.
    /// @dev        If the asset is not registered in any of those modules, it will not raise an error as the outcome is the same.
    ///
    /// @dev        This function reverts if:
    /// @dev        - The policy is inactive
    /// @dev        - The caller is unauthorized
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - An ERC20 token for `pool_` has not been deployed/registered
    /// @dev        - The position representing `pool_` has liquidity
    function deactivatePoolToken(
        address pool_
    ) external override nonReentrant onlyIfActive onlyRole("bunni_admin") bunniHubSet {
        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(pool_);

        // Check that the token has been deployed
        address poolTokenAddress = address(_getPoolToken(key));

        // Check that the position has NO liquidity
        if (
            UniswapV3Positions.positionHasLiquidity(
                key.pool,
                key.tickLower,
                key.tickUpper,
                address(bunniHub)
            )
        ) revert BunniManager_InvalidPoolLiquidity(pool_);

        // De-register the pool token
        _removePoolTokenFromPRICE(poolTokenAddress);
        _removePoolTokenFromTRSRY(poolTokenAddress);
        _removePoolTokenFromSPPLY(poolTokenAddress);

        emit PoolTokenStatusChanged(pool_, poolTokenAddress, false);
    }

    // =========  LIQUIDITY ========= //

    /// @inheritdoc IBunniManager
    /// @dev        This function does the following:
    /// @dev        - Determines the correct ordering of tokens
    /// @dev        - Moves the required non-OHM token(s) from TRSRY to this contract
    /// @dev        - If one of the tokens is OHM, then mint the OHM
    /// @dev        - Deposit the tokens into the BunniHub, which mints share tokens
    /// @dev        - Transfer the share tokens to TRSRY
    /// @dev        - Return any non-OHM token(s) to the TRSRY
    /// @dev        - Burns any remaining OHM
    ///
    /// @dev        This function reverts if:
    /// @dev        - The policy is inactive
    /// @dev        - The caller is unauthorized
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - An ERC20 token for `pool_` has not been deployed/registered
    /// @dev        - `tokenA_` is not an underlying token for the pool
    /// @dev        - There is insufficient balance of tokens
    /// @dev        - The BunniHub instance reverts
    function deposit(
        address pool_,
        address tokenA_,
        uint256 amountA_,
        uint256 amountB_,
        uint16 slippageBps_
    )
        external
        override
        nonReentrant
        onlyIfActive
        onlyRole("bunni_admin")
        bunniHubSet
        returns (uint256)
    {
        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(pool_);

        // Check that the token has been deployed
        _getPoolToken(key);

        // Determine token amounts
        (
            address token0Address,
            address token1Address,
            uint256 token0Amount,
            uint256 token1Amount
        ) = UniswapV3PoolLibrary.getPoolTokenAmounts(pool_, tokenA_, amountA_, amountB_);

        // Move tokens into the policy
        _transferOrMint(token0Address, token0Amount);
        _transferOrMint(token1Address, token1Amount);

        // Approve BunniHub to use the tokens
        ERC20(token0Address).approve(address(bunniHub), token0Amount);
        ERC20(token1Address).approve(address(bunniHub), token1Amount);

        // Construct the parameters
        IBunniHub.DepositParams memory params = IBunniHub.DepositParams({
            key: key,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: UniswapV3PoolLibrary.getAmountMin(token0Amount, slippageBps_),
            amount1Min: UniswapV3PoolLibrary.getAmountMin(token1Amount, slippageBps_),
            deadline: block.timestamp, // Ensures that the action be executed in this block or reverted
            recipient: address(TRSRY) // Transfers directly into TRSRY
        });

        // Deposit
        (uint256 shares, , , ) = bunniHub.deposit(params);

        // Return/burn remaining tokens
        _transferOrBurn(token0Address, ERC20(token0Address).balanceOf(address(this)));
        _transferOrBurn(token1Address, ERC20(token1Address).balanceOf(address(this)));

        return shares;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function does the following:
    /// @dev        - Moves the required shares from TRSRY to this contract
    /// @dev        - Using BunniHub, withdraws shares from the pool and returns the tokens to this contract
    /// @dev        - If one of the tokens is OHM, then burn the OHM
    /// @dev        - Return any non-OHM token(s) to the TRSRY
    ///
    /// @dev        This function reverts if:
    /// @dev        - The policy is inactive
    /// @dev        - The caller is unauthorized
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - An ERC20 token for `pool_` has not been deployed/registered
    /// @dev        - There is insufficient balance of the token
    /// @dev        - The BunniHub instance reverts
    function withdraw(
        address pool_,
        uint256 shares_,
        uint16 slippageBps_
    ) external override nonReentrant onlyIfActive onlyRole("bunni_admin") bunniHubSet {
        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(pool_);

        // Get the existing token (or revert)
        IBunniToken existingToken = _getPoolToken(key);

        // Construct the parameters
        IBunniHub.WithdrawParams memory params = BunniHelper.getWithdrawParams(
            shares_,
            slippageBps_,
            key,
            existingToken,
            address(bunniHub),
            address(this)
        );

        // Move the tokens into the policy
        _transferOrMint(address(existingToken), shares_);

        // Withdraw
        (, uint256 withdrawnAmount0, uint256 withdrawnAmount1) = bunniHub.withdraw(params);

        // Return/burn remaining tokens
        (address poolToken0, address poolToken1) = UniswapV3PoolLibrary.getPoolTokens(pool_);
        _transferOrBurn(poolToken0, withdrawnAmount0);
        _transferOrBurn(poolToken1, withdrawnAmount1);
    }

    // =========  FEE HARVESTING ========= //

    /// @inheritdoc IBunniManager
    /// @dev        For each pool, this function does the following:
    /// @dev        - Calls the `burn()` function with a 0 amount, which triggers a fee update
    ///
    /// @dev        Reverts if:
    /// @dev        - The policy is inactive
    /// @dev        - The `bunniHub` state variable is not set
    function updateSwapFees() external nonReentrant onlyIfActive bunniHubSet {
        _updateSwapFees();
    }

    /// @inheritdoc     IBunniManager
    /// @dev            This function does the following:
    /// @dev            - Determines if enough time has passed since the previous harvest
    /// @dev            - Updates the fees for the pools
    /// @dev            - For each pool:
    /// @dev                - Calls the `compound()` function on BunniHub
    /// @dev            - Returns any extraneous tokens in BunniHub to the TRSRY (or burns, if OHM)
    /// @dev            - Mints OHM as a reward and transfers it to the caller (provided there are pools to harvest from)
    ///
    /// @dev            The reward for harvesting is determined by `getCurrentHarvestReward`.
    ///
    /// @dev            Reverts if:
    /// @dev            - The policy is inactive
    /// @dev            - The `bunniHub` state variable is not set
    /// @dev            - Not enough time has elapsed from the previous harvest
    /// @dev            - The BunniHub instance reverts while calling `compound()`
    function harvest() external nonReentrant onlyIfActive bunniHubSet {
        uint48 minHarvest = lastHarvest + harvestFrequency;
        if (minHarvest > block.timestamp) revert BunniManager_HarvestTooEarly(minHarvest);

        // Ensure fees are up to date
        _updateSwapFees();

        // Determine the award amount
        uint256 currentHarvestReward = getCurrentHarvestReward();

        uint256 poolCount = pools.length;
        for (uint256 i = 0; i < poolCount; i++) {
            address poolAddress = pools[i];

            // Skip if no shares have been minted
            if (getPoolTokenBalance(poolAddress) == 0) continue;

            BunniKey memory key = BunniHelper.getFullRangeBunniKey(poolAddress);
            bunniHub.compound(key);
        }

        // Sweep tokens from the BunniHub
        // As `poolUnderlyingTokens` is a unique list, this will not sweep the same token twice.
        // It also does not contain any zero addresses, which would cause a revert in `sweepTokens`.
        bunniHub.sweepTokens(poolUnderlyingTokens, address(this));

        // Burn/transfer any swept tokens
        for (uint256 i = 0; i < poolUnderlyingTokens.length; i++) {
            ERC20 poolUnderlyingToken = poolUnderlyingTokens[i];
            _transferOrBurn(
                address(poolUnderlyingToken),
                poolUnderlyingToken.balanceOf(address(this))
            );
        }

        // Mint the OHM reward and transfer it to the caller
        if (currentHarvestReward > 0) {
            MINTR.increaseMintApproval(address(this), currentHarvestReward);
            MINTR.mintOhm(msg.sender, currentHarvestReward);
        }

        // Update the lastHarvest
        lastHarvest = uint48(block.timestamp);
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - An ERC20 token for `pool_` has not been deployed/registered
    function getPoolToken(address pool_) public view override bunniHubSet returns (IBunniToken) {
        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(pool_);

        return _getPoolToken(key);
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - An ERC20 token for `pool_` has not been deployed/registered
    function getPoolTokenBalance(address pool_) public view override bunniHubSet returns (uint256) {
        // Get the token
        // `getPoolToken` will revert if the pool is not found
        IBunniToken token = getPoolToken(pool_);

        // Get the balance of the token in TRSRY
        return token.balanceOf(address(TRSRY));
    }

    /// @inheritdoc IBunniManager
    /// @dev        The harvest reward is determined in the following manner:
    /// @dev        - For all managed pools, determine the total amount of fees that have been collected
    /// @dev        - Get the USD value of the fees
    /// @dev        - Determine the potential harvest reward as the fee multiplier * USD value of fees
    /// @dev        - Return the reward as the minimum of the potential reward and the max reward
    ///
    /// @dev        This function assumes that the pending fees for the pools are up-to-date. Calling
    /// @dev        functions should update the pending fees before calling this function using `updateSwapFees()`.
    function getCurrentHarvestReward() public view override bunniHubSet returns (uint256 reward) {
        // 0 if enough time has not elapsed
        if (lastHarvest + harvestFrequency < block.timestamp) return 0;

        uint256 feeUsdValue; // Scale: PRICE decimals
        uint256 priceScale = 10 ** PRICE.decimals();
        uint256 poolCount = pools.length;
        for (uint256 i = 0; i < poolCount; i++) {
            address currentPool = pools[i];
            BunniKey memory key = BunniHelper.getFullRangeBunniKey(currentPool);

            // Get the fees
            (uint128 fees0, uint128 fees1) = UniswapV3Positions.getPositionFees(
                key.pool,
                key.tickLower,
                key.tickUpper,
                address(bunniHub)
            );

            // Convert fees from native into PRICE decimals
            (address token0Address, address token1Address) = UniswapV3PoolLibrary.getPoolTokens(
                currentPool
            );
            uint256 token0Fees = uint256(fees0).mulDiv(
                priceScale,
                10 ** ERC20(token0Address).decimals()
            );
            uint256 token1Fees = uint256(fees1).mulDiv(
                priceScale,
                10 ** ERC20(token1Address).decimals()
            );

            // Get the USD value of the fees
            feeUsdValue += PRICE.getPrice(token0Address).mulDiv(token0Fees, priceScale);
            feeUsdValue += PRICE.getPrice(token1Address).mulDiv(token1Fees, priceScale);
        }

        // Calculate the reward value
        uint256 rewardUsdValue = feeUsdValue.mulDiv(harvestRewardFee, BPS_MAX);

        // Convert in terms of OHM
        uint256 ohmPrice = PRICE.getPrice(ohm); // This will revert if the asset is not defined or 0
        uint256 ohmAmount = rewardUsdValue.mulDiv(1e9, ohmPrice); // Scale: OHM decimals

        // Returns the minimum
        return ohmAmount < harvestRewardMax ? ohmAmount : harvestRewardMax;
    }

    /// @inheritdoc IBunniManager
    function getPoolCount() external view override returns (uint256) {
        return pools.length;
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    /// @dev        - The caller is unauthorized
    /// @dev        - `newBunniLens_` is the zero address
    /// @dev        - The `hub` state variable on `newBunniLens_` is not set
    function setBunniLens(
        address newBunniLens_
    ) external override nonReentrant onlyRole("bunni_admin") {
        if (address(newBunniLens_) == address(0)) revert BunniManager_InvalidParams();

        bunniLens = BunniLens(newBunniLens_);
        bunniHub = BunniHub(address(bunniLens.hub()));
        if (address(bunniHub) == address(0)) revert BunniManager_InvalidParams();

        emit BunniLensSet(address(bunniHub), newBunniLens_);
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    /// @dev        - The caller is unauthorized
    /// @dev        - The `bunniHub` state variable is not set
    /// @dev        - `newOwner_` is the zero address
    function setBunniOwner(
        address newOwner_
    ) external override nonReentrant onlyRole("bunni_admin") bunniHubSet {
        if (address(newOwner_) == address(0)) revert BunniManager_InvalidParams();

        bunniHub.transferOwnership(newOwner_);

        emit BunniHubOwnerSet(address(bunniHub), newOwner_);
    }

    /// @inheritdoc IBunniManager
    function resetLastHarvest() external override nonReentrant onlyRole("bunni_admin") {
        // Avoid an underflow
        lastHarvest = harvestFrequency > block.timestamp
            ? 0
            : uint48(block.timestamp - harvestFrequency);

        emit LastHarvestReset(lastHarvest);
    }

    /// @inheritdoc IBunniManager
    function setHarvestFrequency(
        uint48 newFrequency_
    ) external override nonReentrant onlyRole("bunni_admin") {
        if (newFrequency_ == 0) revert BunniManager_InvalidParams();

        harvestFrequency = newFrequency_;

        emit HarvestFrequencySet(newFrequency_);
    }

    /// @inheritdoc IBunniManager
    function setHarvestRewardParameters(
        uint256 newRewardMax_,
        uint16 newRewardFee_
    ) external override nonReentrant onlyRole("bunni_admin") {
        if (newRewardFee_ > BPS_MAX) revert BunniManager_InvalidParams();

        harvestRewardMax = newRewardMax_;
        harvestRewardFee = newRewardFee_;

        emit HarvestRewardParamsSet(newRewardMax_, newRewardFee_);
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

    /// @notice         Obtains the BunniToken for the given pool
    /// @dev            This function reverts if:
    /// @dev            - A BunniToken for `key_` cannot be found
    ///
    /// @param key_     The BunniKey representing the position
    /// @return         The BunniToken for the pool
    function _getPoolToken(BunniKey memory key_) internal view returns (IBunniToken) {
        IBunniToken token = bunniHub.getBunniToken(key_);

        // Ensure the token exists
        if (address(token) == address(0)) revert BunniManager_InvalidParams();

        return token;
    }

    /// @notice         Transfers the tokens from TRSRY or mints them if the token is OHM
    ///
    /// @param token_   The address of the token
    /// @param amount_  The amount of tokens to transfer/mint
    function _transferOrMint(address token_, uint256 amount_) internal {
        if (token_ == ohm) {
            MINTR.increaseMintApproval(address(this), amount_);
            MINTR.mintOhm(address(this), amount_);
        } else {
            // Check the balance
            ERC20 token = ERC20(token_);
            uint256 actualBalance = token.balanceOf(address(TRSRY));
            if (actualBalance < amount_)
                revert BunniManager_InsufficientBalance(token_, amount_, actualBalance);

            // Increase the allowance
            TRSRY.increaseWithdrawApproval(address(this), token, amount_);

            // Transfer into the policy
            TRSRY.withdrawReserves(address(this), token, amount_);
        }
    }

    /// @notice         Transfers the tokens to TRSRY or burns them if the token is OHM
    ///
    /// @param token_   The address of the token
    /// @param amount_  The amount of tokens to transfer/burn
    function _transferOrBurn(address token_, uint256 amount_) internal {
        // Nothing to burn
        if (amount_ == 0) return;

        if (token_ == ohm) {
            MINTR.burnOhm(address(this), amount_);
        } else {
            // All tokens are pre-filtered by TRSRY, so safeTransfer is not needed
            ERC20(token_).transfer(address(TRSRY), amount_);
        }
    }

    /// @notice     Asserts that the given address is a Uniswap V3 pool
    /// @dev        This is determined by calling `slot0()`
    function _assertIsValidPool(address pool_) internal view {
        if (!UniswapV3PoolLibrary.isValidPool(pool_)) revert BunniManager_InvalidParams();
    }

    /// @notice     Adds the token to the list of underlying tokens
    /// @dev        Duplicate tokens are skipped
    function _addUnderlyingToken(address token_) internal {
        // Check if the token has already been added
        uint256 poolUnderlyingTokenCount = poolUnderlyingTokens.length;
        for (uint256 i = 0; i < poolUnderlyingTokenCount; i++) {
            if (address(poolUnderlyingTokens[i]) == token_) return;
        }

        // Add the token
        poolUnderlyingTokens.push(ERC20(token_));
    }

    /// @notice     Updates the swap fees for all pools
    /// @dev        This internal function is provided as external/public functions
    /// @dev        (such as `harvest()`) need to use this functionality, but would
    /// @dev        run into re-entrancy issues using the external/public function.
    function _updateSwapFees() internal {
        uint256 poolCount = pools.length;
        for (uint256 i = 0; i < poolCount; i++) {
            address poolAddress = pools[i];

            // Skip if no shares have been minted
            if (getPoolTokenBalance(poolAddress) == 0) continue;

            BunniKey memory key = BunniHelper.getFullRangeBunniKey(poolAddress);
            bunniHub.updateSwapFees(key);

            emit PoolSwapFeesUpdated(poolAddress);
        }
    }

    /// @notice                         Registers `poolToken_` as an asset in the PRICE module
    /// @dev                            This function performs the following:
    /// @dev                            - Checks if the asset is already registered, and reverts if so
    /// @dev                            - Calls `PRICE.addAsset`
    ///
    /// @param poolToken_               The pool token to register
    /// @param movingAverageDuration_   The moving average duration
    /// @param lastObservationTime_     The last observation time
    /// @param observations_            The observations
    function _addPoolTokenToPRICE(
        address poolToken_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) internal {
        // Revert if already activated
        if (PRICE.isAssetApproved(poolToken_) == true) revert BunniManager_InvalidParams();

        // Prepare price feeds
        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        {
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.BNI"), // Subkeycode
                BunniPrice.getBunniTokenPrice.selector, // Selector
                abi.encode(BunniPrice.BunniParams(address(bunniLens))) // Params
            );
        }

        // Add asset
        {
            PRICE.addAsset(
                poolToken_, // address asset_
                true, // bool storeMovingAverage_
                true, // bool useMovingAverage_
                movingAverageDuration_, // uint32 movingAverageDuration_
                lastObservationTime_, // uint48 lastObservationTime_
                observations_, // uint256[] memory observations_
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAveragePrice.selector,
                    abi.encode(0)
                ), // Average of values
                feeds // Component[] memory feeds_
            );
        }
    }

    /// @notice             Registers `poolToken_` as an asset in the TRSRY module
    /// @dev                This function performs the following:
    /// @dev                - Checks if the asset is already registered, and reverts if so
    /// @dev                - Adds the asset to TRSRY (if needed)
    /// @dev                - Adds the TRSRY location to the asset
    /// @dev                - Categorizes the asset
    ///
    /// @param poolToken_   The pool token to register
    function _addPoolTokenToTRSRY(address poolToken_) internal {
        TRSRYv1_1.Asset memory assetData = TRSRY.getAssetData(poolToken_);
        // Revert if the asset exists and the location is already registered (which would indicate an inconsistent activation state)
        if (assetData.approved == true) {
            bool locationExists = false;
            for (uint256 i = 0; i < assetData.locations.length; i++) {
                if (assetData.locations[i] == address(TRSRY)) {
                    locationExists = true;
                    break;
                }
            }

            if (locationExists) revert BunniManager_InvalidParams();
        } else {
            // Add the asset to TRSRY
            TRSRY.addAsset(poolToken_, new address[](0));
        }

        // Add TRSRY as a location
        TRSRY.addAssetLocation(poolToken_, address(TRSRY));

        // Categorize the asset
        TRSRY.categorize(poolToken_, toTreasuryCategory("liquid"));
        TRSRY.categorize(poolToken_, toTreasuryCategory("volatile"));
        TRSRY.categorize(poolToken_, toTreasuryCategory("protocol-owned-liquidity"));
    }

    /// @notice                         Registers `poolToken_` as an asset in the SPPLY module
    /// @dev                            This function performs the following:
    /// @dev                            - Checks if the asset is already registered, and reverts if so
    /// @dev                            - Calls `SPPLY.categorize`
    ///
    /// @param poolToken_               The pool token to register
    /// @param movingAverageDuration_   The moving average duration
    /// @param lastObservationTime_     The last observation time
    /// @param token0Observations_      The observations for token0
    /// @param token1Observations_      The observations for token1
    function _addPoolTokenToSPPLY(
        address poolToken_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory token0Observations_,
        uint256[] memory token1Observations_
    ) internal {
        // Revert if already activated
        if (_isPoolTokenRegisteredInSPPLY(poolToken_)) revert BunniManager_InvalidParams();

        // Register the asset with SPPLY submodule
        SPPLY.execOnSubmodule(
            toSubKeycode("SPPLY.BNI"),
            abi.encodeWithSelector(
                BunniSupply.addBunniToken.selector,
                poolToken_,
                address(bunniLens),
                movingAverageDuration_,
                lastObservationTime_,
                token0Observations_,
                token1Observations_
            )
        );
    }

    /// @notice             Deregisters `poolToken_` as an asset in the PRICE module
    /// @dev                This function performs the following:
    /// @dev                - Checks if the asset is registered, or exits if not
    /// @dev                - Calls `PRICE.removeAsset`
    ///
    /// @param poolToken_   The pool token to deregister
    function _removePoolTokenFromPRICE(address poolToken_) internal {
        // Exit if not activated
        if (PRICE.isAssetApproved(poolToken_) == false) return;

        // Remove the asset
        PRICE.removeAsset(poolToken_);
    }

    /// @notice             Deregisters `poolToken_` as an asset in the TRSRY module
    /// @dev                This function performs the following:
    /// @dev                - Checks if the asset is registered, or exits if not
    /// @dev                - Removes the TRSRY location from the asset
    /// @dev                - Removes the categorization of the asset
    ///
    /// @param poolToken_   The pool token to deregister
    function _removePoolTokenFromTRSRY(address poolToken_) internal {
        // Exit if not activated
        if (TRSRY.isAssetApproved(poolToken_) == false) return;

        // Remove the TRSRY location from the asset
        TRSRY.removeAssetLocation(poolToken_, address(TRSRY));

        // Cannot remove the categorization of the asset
    }

    /// @notice             Deregisters `poolToken_` as an asset in the SPPLY module
    /// @dev                This function performs the following:
    /// @dev                - Checks if the asset is registered, or exits if not
    /// @dev                - Calls `BunniSupply.removeBunniToken`
    ///
    /// @param poolToken_   The pool token to deregister
    function _removePoolTokenFromSPPLY(address poolToken_) internal {
        // Exit if not activated
        if (!_isPoolTokenRegisteredInSPPLY(poolToken_)) return;

        // Remove the asset
        SPPLY.execOnSubmodule(
            toSubKeycode("SPPLY.BNI"),
            abi.encodeWithSelector(BunniSupply.removeBunniToken.selector, poolToken_)
        );
    }

    function _isPoolTokenRegisteredInSPPLY(address poolToken_) internal returns (bool) {
        return
            abi.decode(
                SPPLY.execOnSubmodule(
                    toSubKeycode("SPPLY.BNI"),
                    abi.encodeWithSelector(BunniSupply.hasBunniToken.selector, poolToken_)
                ),
                (bool)
            );
    }

    //============================================================================================//
    //                                      MODIFIERS                                             //
    //============================================================================================//

    /// @notice         Modifier to assert that the `bunniHub` state variable is set
    /// @dev            The `bunniHub` state variable is set after deployment, so this
    /// @dev            modifier is needed to check that the configuration is valid.
    modifier bunniHubSet() {
        if (address(bunniHub) == address(0)) revert BunniManager_HubNotSet();
        _;
    }

    /// @notice         Modifier to assert that the policy is active
    modifier onlyIfActive() {
        if (!kernel.isPolicyActive(this)) revert BunniManager_Inactive();
        _;
    }
}
