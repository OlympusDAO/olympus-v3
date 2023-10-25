// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

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

    /// @notice                 Emitted if any of the module dependencies are the wrong version
    /// @param expectedMajors_  The expected major versions of the modules
    error BunniManager_WrongModuleVersion(uint8[2] expectedMajors_);

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

    //============================================================================================//
    //                                      STATE                                                 //
    //============================================================================================//

    BunniHub bunniHub;

    // Modules
    TRSRYv1 internal TRSRY;

    // Constants
    uint256 constant SLIPPAGE_TOLERANCE = 100; // 1%
    uint256 constant SLIPPAGE_SCALE = 10000; // 100%

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    /// @dev    The BunniHub contract cannot be passed into the constructor, as it requires the owner to
    ///         be set to this contract. Therefore, the BunniHub must be set manually after deployment.
    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));

        (uint8 ROLES_MAJOR, ) = roles.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        if (
            ROLES_MAJOR != 1 ||
            TRSRY_MAJOR != 1
        ) revert BunniManager_WrongModuleVersion([1, 1]);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        requests = new Permissions[](3);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseWithdrawApproval.selector);
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

        // TODO register the token with PRICEv2.addAsset (requires the PRICE submodule)

        return deployedToken;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The caller is unauthorized
    ///             - The `bunniHub` state variable is not set
    function deposit(
        address pool_,
        uint256 amount0_,
        uint256 amount1_
    ) external override nonReentrant onlyRole("bunni_admin") bunniHubSet returns (uint256) {
        // Create a BunniKey
        BunniKey memory key = _getBunniKey(pool_);

        // Construct the parameters
        IBunniHub.DepositParams memory params = IBunniHub.DepositParams({
            key: key,
            amount0Desired: amount0_,
            amount1Desired: amount1_,
            amount0Min: _calculateAmountMin(amount0_),
            amount1Min: _calculateAmountMin(amount1_),
            deadline: block.timestamp, // Ensures that the action be executed in this block or reverted
            recipient: getModuleAddress(toKeycode("TRSRY")) // Transfers directly into TRSRY
        });

        // Deposit
        (uint256 shares, , , ) = bunniHub.deposit(params);

        return shares;
    }

    /// @inheritdoc IBunniManager
    /// @dev        This function reverts if:
    ///             - The caller is unauthorized
    ///             - The `bunniHub` state variable is not set
    function withdraw(
        address pool_,
        uint256 shares_
    ) external override nonReentrant onlyRole("bunni_admin") bunniHubSet {
        // Create a BunniKey
        BunniKey memory key = _getBunniKey(pool_);

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

            amount0Min = _calculateAmountMin(amount0);
            amount1Min = _calculateAmountMin(amount1);
        }

        // Construct the parameters
        IBunniHub.WithdrawParams memory params = IBunniHub.WithdrawParams({
            key: key,
            recipient: getModuleAddress(toKeycode("TRSRY")), // Transfers directly into TRSRY
            shares: shares_,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp // Ensures that the action be executed in this block or reverted
        });

        // Withdraw
        bunniHub.withdraw(params);
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
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK
            });
    }

    /// @notice         Modifier to assert that the `bunniHub` state variable is set
    /// @dev            The `bunniHub` state variable is set after deployment, so this
    ///                 modifier is needed to check that the configuration is valid.
    modifier bunniHubSet() {
        if (address(bunniHub) == address(0)) revert BunniManager_HubNotSet();
        _;
    }
}
