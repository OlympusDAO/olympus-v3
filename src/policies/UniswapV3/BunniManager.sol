// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import {IBunniManager} from "policies/UniswapV3/interfaces/IBunniManager.sol";

import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "modules/PRICE/OlympusPrice.v2.sol";

import "src/Kernel.sol";

/// @title  BunniManager
/// @author 0xJem
/// @notice Bophades policy to manage UniswapV3 positions.
/// @dev    This policy is paired with a BunniHub instance to manage the lifecycle of BunniTokens.
///
///         What this policy does not cover:
///         - Migrating positions between BunniHub deployments. (This could be achieved by withdrawing and depositing into the new BunniHub instance.)
///         - Migrating positions between Uniswap V3 pools. (This could be achieved by withdrawing and depositing into the new Uniswap V3 pool.)
///         - Managing positions that were not deployed by this policy. (This could be achieved by deploying a new BunniToken and depositing into it.)
///         - Harvesting pool fees. (There is a separate, public policy for this purpose.)
///         - Migrating LP tokens between addresses. (This could be achieved by transferring the ERC20 tokens to the new address.)
///         - Setting the protocol fee on the BunniHub instance (applied when compounding pool fees), as there is no use for having the protocol fees applied.
contract BunniManager is IBunniManager, Policy, RolesConsumer, ReentrancyGuard {
    using FullMath for uint256;
    using TransferHelper for ERC20;

    /// @notice                 Emitted if any of the module dependencies are the wrong version
    /// @param expectedMajors_  The expected major versions of the modules
    error BunniManager_WrongModuleVersion(uint8[4] expectedMajors_);

    /// @notice                 Emitted if the given address is invalid
    /// @param address_         The invalid address
    error BunniManager_Params_InvalidAddress(address address_);

    /// @notice   Emitted if the BunniHub has not been set
    error BunniManager_HubNotSet();

    /// @notice         Emitted if the pool is not managed by this policy
    /// @param pool_    The address of the Uniswap V3 pool
    error BunniManager_PoolNotFound(address pool_);

    /// @notice         Emitted if the pool has already been deployed as a token
    /// @param pool_    The address of the Uniswap V3 pool
    /// @param token_   The address of the existing BunniToken
    error BunniManager_TokenDeployed(address pool_, address token_);

    /// @notice                 Emitted if the caller does not have sufficient balance to deposit
    /// @param token_           The address of the token
    /// @param requiredBalance_ The required balance
    /// @param actualBalance_   The actual balance
    error BunniManager_InsufficientBalance(address token_, uint256 requiredBalance_, uint256 actualBalance_);

    //============================================================================================//
    //                                      STATE                                                 //
    //============================================================================================//

    BunniHub public bunniHub;

    // Modules
    TRSRYv1 internal TRSRY;
    PRICEv2 internal PRICE;
    MINTRv1 internal MINTR;

    // Constants
    uint256 constant SLIPPAGE_TOLERANCE = 100; // 1%
    uint256 constant SLIPPAGE_SCALE = 10000; // 100%
    int24 constant TICK_SPACING_DIVISOR = 50;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    /// @dev    The BunniHub contract cannot be passed into the constructor, as it requires the owner to
    ///         be set to this contract. Therefore, the BunniHub must be set manually after deployment.
    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        dependencies[2] = toKeycode("PRICE");
        dependencies[3] = toKeycode("MINTR");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));
        PRICE = PRICEv2(getModuleAddress(dependencies[2]));
        MINTR = MINTRv1(getModuleAddress(dependencies[3]));

        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();

        // Ensure Modules are using the expected major version.
        if (
            ROLES_MAJOR != 1 ||
            TRSRY_MAJOR != 1 ||
            PRICE_MAJOR != 2 ||
            MINTR_MAJOR != 1
        ) revert BunniManager_WrongModuleVersion([1, 1, 2, 1]);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();
        Keycode PRICE_KEYCODE = PRICE.KEYCODE();
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        requests = new Permissions[](8);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseWithdrawApproval.selector);
        requests[3] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        requests[4] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[5] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[6] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        requests[7] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The caller is unauthorized
    ///             - The `bunniHub` state variable is not set
    function deployToken(
        address pool_
    )
        external
        override
        nonReentrant
        onlyRole("bunni_admin")
        bunniHubSet
        returns (IBunniToken token)
    {
        // Create a BunniKey
        BunniKey memory key = _getBunniKey(pool_);

        // Check that `pool_` is an actual Uniswap V3 pool
        try IUniswapV3Pool(pool_).slot0() returns (
            uint160,
            int24,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            // Do nothing
        } catch (bytes memory) {
            // If slot0 throws, then pool_ is not a Uniswap V3 pool
            revert BunniManager_PoolNotFound(pool_);
        }

        // Check if a token for the pool has been deployed already
        IBunniToken existingToken = bunniHub.getBunniToken(key);
        if (address(existingToken) != address(0)) {
            revert BunniManager_TokenDeployed(pool_, address(existingToken));
        }

        // Deploy
        IBunniToken deployedToken = bunniHub.deployBunniToken(key);

        // Register the token for lookups
        // PRICEv2.Component[] memory feeds = new PRICEv2.Component[](0);
        // // TODO configure PRICE submodule

        // PRICE.addAsset(
        //     address(deployedToken), // asset_
        //     false, // storeMovingAverage_
        //     false, // useMovingAverage_
        //     uint32(0), // movingAverageDuration_
        //     uint48(0), // uint48 lastObservationTime_
        //     new uint256[](0), // uint256[] memory observations_
        //     PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
        //     feeds //
        // );

        return deployedToken;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function does the following:
    ///             - Determines the correct ordering of tokens
    ///             - Moves the required non-OHM token(s) from TRSRY to this contract
    ///             - If one of the tokens is OHM, then mint the OHM
    ///             - Deposit the tokens into the BunniHub, which mints share tokens
    ///             - Transfer the share tokens to TRSRY
    ///             - Return any non-OHM token(s) to the TRSRY
    ///             - Burns any remaining OHM
    ///
    ///             This function reverts if:
    ///             - The caller is unauthorized
    ///             - The `bunniHub` state variable is not set
    ///             - An ERC20 token for `pool_` has not been deployed
    ///             - There is insufficient balance of tokens
    function deposit(
        address pool_,
        address tokenA_,
        uint256 amountA_,
        address,
        uint256 amountB_
    ) external override nonReentrant onlyRole("bunni_admin") bunniHubSet returns (uint256) {
        // Create a BunniKey
        BunniKey memory key = _getBunniKey(pool_);

        // TODO take slippage as a parameter

        // Check that the token has been deployed
        IBunniToken existingToken = bunniHub.getBunniToken(key);
        if (address(existingToken) == address(0)) {
            revert BunniManager_PoolNotFound(pool_);
        }

        // Move non-OHM tokens from TRSRY to this contract
        IUniswapV3Pool pool = IUniswapV3Pool(pool_);
        ERC20 token0 = ERC20(pool.token0());
        ERC20 token1 = ERC20(pool.token1());

        bool token0IsTokenA = address(token0) == tokenA_;
        uint256 token0Amount = token0IsTokenA ? amountA_ : amountB_;
        uint256 token1Amount = token0IsTokenA ? amountB_ : amountA_;

        // Move tokens into the policy
        _transferOrMint(address(token0), token0Amount);
        _transferOrMint(address(token1), token1Amount);

        // Approve BunniHub to use the tokens
        token0.approve(address(bunniHub), token0Amount);
        token1.approve(address(bunniHub), token1Amount);

        // Construct the parameters
        IBunniHub.DepositParams memory params = IBunniHub.DepositParams({
            key: key,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: _calculateAmountMin(token0Amount),
            amount1Min: _calculateAmountMin(token1Amount),
            deadline: block.timestamp, // Ensures that the action be executed in this block or reverted
            recipient: getModuleAddress(toKeycode("TRSRY")) // Transfers directly into TRSRY
        });

        // Deposit
        (uint256 shares, , , ) = bunniHub.deposit(params);

        // Return/burn remaining tokens
        _transferOrBurn(address(token0), token0.balanceOf(address(this)));
        _transferOrBurn(address(token1), token1.balanceOf(address(this)));

        return shares;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function does the following:
    ///             - Moves the required shares from TRSRY to this contract
    ///             - Using BunniHub, withdraws shares from the pool and returns the tokens to this contract
    ///             - If one of the tokens is OHM, then burn the OHM
    ///             - Return any non-OHM token(s) to the TRSRY
    ///
    ///             This function reverts if:
    ///             - The caller is unauthorized
    ///             - The `bunniHub` state variable is not set
    ///             - An ERC20 token for `pool_` has not been deployed
    ///             - There is insufficient balance of the token
    function withdraw(
        address pool_,
        uint256 shares_
    ) external override nonReentrant onlyRole("bunni_admin") bunniHubSet {
        // Create a BunniKey
        BunniKey memory key = _getBunniKey(pool_);

        IBunniToken existingToken = bunniHub.getBunniToken(key);
        if (address(existingToken) == address(0)) {
            revert BunniManager_PoolNotFound(pool_);
        }

        // TODO take slippage as a parameter

        // Determine the minimum amounts
        uint256 amount0Min;
        uint256 amount1Min;
        {
            (uint160 sqrtRatioX96, , , , , , ) = key.pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(key.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(key.tickUpper);

            // Copied from BunniHub.deposit()
            (uint128 existingLiquidity, , , , ) = key.pool.positions(
                keccak256(abi.encodePacked(address(bunniHub), key.tickLower, key.tickUpper))
            );

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                existingLiquidity
            );

            // Adjust for proportion of total supply
            uint256 totalSupply = existingToken.totalSupply();
            amount0 = amount0.mulDiv(shares_, totalSupply);
            amount1 = amount1.mulDiv(shares_, totalSupply);

            amount0Min = _calculateAmountMin(amount0);
            amount1Min = _calculateAmountMin(amount1);
        }

        // Move the tokens into the policy
        _transferFromTRSRY(address(existingToken), shares_);

        // Construct the parameters
        IBunniHub.WithdrawParams memory params = IBunniHub.WithdrawParams({
            key: key,
            recipient: address(this),
            shares: shares_,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp // Ensures that the action be executed in this block or reverted
        });

        // Withdraw
        (, uint256 withdrawnAmount0, uint256 withdrawnAmount1) = bunniHub.withdraw(params);

        // Return/burn remaining tokens
        IUniswapV3Pool pool = IUniswapV3Pool(pool_);
        _transferOrBurn(pool.token0(), withdrawnAmount0);
        _transferOrBurn(pool.token1(), withdrawnAmount1);
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The `bunniHub` state variable is not set
    function getToken(address pool_) public view override bunniHubSet returns (IBunniToken) {
        // Create a BunniKey
        BunniKey memory key = _getBunniKey(pool_);

        IBunniToken token = bunniHub.getBunniToken(key);

        // Ensure the token exists
        if (address(token) == address(0)) {
            revert BunniManager_PoolNotFound(pool_);
        }

        return token;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The `bunniHub` state variable is not set
    function getTRSRYBalance(address pool_) external view override returns (uint256) {
        // Get the token
        // `getToken` will revert if the pool is not found
        IBunniToken token = getToken(pool_);

        // Get the balance of the token in TRSRY
        return token.balanceOf(address(TRSRY));
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The caller is unauthorized
    ///             - `newBunniHub_` is the zero address
    function setBunniHub(
        address newBunniHub_
    ) external override nonReentrant onlyRole("bunni_admin") {
        if (address(newBunniHub_) == address(0)) {
            revert BunniManager_Params_InvalidAddress(newBunniHub_);
        }

        bunniHub = BunniHub(newBunniHub_);
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The caller is unauthorized
    ///             - The `bunniHub` state variable is not set
    ///             - `newOwner_` is the zero address
    function setBunniOwner(
        address newOwner_
    ) external override nonReentrant onlyRole("bunni_admin") bunniHubSet {
        if (address(newOwner_) == address(0)) {
            revert BunniManager_Params_InvalidAddress(newOwner_);
        }

        bunniHub.setOwner(newOwner_);
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

    /// @notice         Convenience method to calculate the minimum amount of tokens to receive
    /// @dev            This is calculated as `amount_ * (1 - slippageTolerance)`
    /// @param amount_  The amount of tokens to calculate the minimum for
    function _calculateAmountMin(uint256 amount_) internal pure returns (uint256) {
        return amount_.mulDiv(SLIPPAGE_SCALE - SLIPPAGE_TOLERANCE, SLIPPAGE_SCALE);
    }

    /// @notice         Convenience method to create a BunniKey identifier representing a full-range position.
    /// @param pool_    The address of the Uniswap V3 pool
    /// @return         The BunniKey identifier
    function _getBunniKey(address pool_) internal pure returns (BunniKey memory) {
        return
            BunniKey({
                pool: IUniswapV3Pool(pool_),
                // The ticks need to be divisible by the tick spacing
                // Source: https://github.com/Aboudoc/Uniswap-v3/blob/7aa9db0d0bf3d188a8a53a1dbe542adf7483b746/contracts/UniswapV3Liquidity.sol#L49C23-L49C23
                tickLower: (TickMath.MIN_TICK / TICK_SPACING_DIVISOR) * TICK_SPACING_DIVISOR,
                tickUpper: (TickMath.MAX_TICK / TICK_SPACING_DIVISOR) * TICK_SPACING_DIVISOR
            });
    }

    function _transferFromTRSRY(address token_, uint256 amount_) internal {
        // Check the balance
        ERC20 token = ERC20(token_);
        uint256 actualBalance = token.balanceOf(address(TRSRY));
        if (actualBalance < amount_) {
            revert BunniManager_InsufficientBalance(token_, amount_, actualBalance);
        }

        // Increase the allowance
        TRSRY.increaseWithdrawApproval(address(this), token, amount_);

        // Transfer into the policy
        TRSRY.withdrawReserves(address(this), token, amount_);
    }

    function _transferOrMint(address token_, uint256 amount_) internal {
        if (token_ == address(MINTR.ohm())) {
            MINTR.increaseMintApproval(address(this), amount_);
            MINTR.mintOhm(address(this), amount_);
        }
        else {
            _transferFromTRSRY(token_, amount_);
        }
    }

    function _transferOrBurn(address token_, uint256 amount_) internal {
        // Nothing to burn
        if (amount_ == 0) return;

        if (token_ == address(MINTR.ohm())) {
            MINTR.burnOhm(address(this), amount_);
        }
        else {
            ERC20(token_).safeTransfer(address(TRSRY), amount_);
        }
    }

    /// @notice         Modifier to assert that the `bunniHub` state variable is set
    /// @dev            The `bunniHub` state variable is set after deployment, so this
    ///                 modifier is needed to check that the configuration is valid.
    modifier bunniHubSet() {
        if (address(bunniHub) == address(0)) revert BunniManager_HubNotSet();
        _;
    }
}
