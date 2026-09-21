// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

/// @title Deposit Manager V1.1
/// @notice Adds token-aware output modes and conversion previews to DepositManager V1.
/// @dev All requested amounts remain denominated in the configured underlying asset. When share
///      output is selected, `amountOut` is denominated in the returned vault share token, which can
///      differ from the vault entry-point address for ERC-7575 vaults.
///      Extends the complete V1 API and reuses its parameter structs. ERC-165 callers should
///      check both DepositManager interface IDs and the separate `IAssetManagerV1_1` interface ID:
///      Solidity excludes inherited functions from an interface ID.
interface IDepositManagerV1_1 is IDepositManager {
    // ========== ERRORS ========== //

    /// @notice Thrown when a withdrawal recipient would retain output in DepositManager custody.
    /// @param recipient The invalid recipient.
    error DepositManager_InvalidRecipient(address recipient);

    /// @notice Thrown when a borrowing withdrawal would transfer no output token.
    error DepositManager_ZeroOutput();

    // ========== EVENTS ========== //

    /// @notice Emitted when DepositManager processes a share-mode withdrawal request.
    /// @dev Share-output calls emit this six-argument event, including with zero `amountOut` when
    ///      conversion rounds to zero shares. Underlying-output calls instead emit the inherited
    ///      five-argument `AssetWithdrawn(address,address,address,uint256,uint256)` event. The two
    ///      signatures have different `topic0` values, so indexers migrating from V1 must subscribe
    ///      to both and select the event matching the configured output mode.
    /// @param asset The underlying asset in which the request is denominated.
    /// @param recipient The output-token recipient.
    /// @param operator The deposit operator that initiated the withdrawal.
    /// @param requestedAssetAmount The requested amount in underlying-asset units.
    /// @param tokenOut The configured share token transferred.
    /// @param amountOut The quantity transferred in `tokenOut` units, which can be zero.
    event AssetWithdrawn(
        address indexed asset,
        address indexed recipient,
        address indexed operator,
        uint256 requestedAssetAmount,
        address tokenOut,
        uint256 amountOut
    );

    /// @notice Emitted when an operator claims yield as vault shares.
    /// @param asset The underlying asset in which the request is denominated.
    /// @param recipient The output-token recipient.
    /// @param operator The deposit operator whose yield was claimed.
    /// @param requestedAssetAmount The requested yield in underlying-asset units.
    /// @param tokenOut The configured share token transferred.
    /// @param amountOut The quantity transferred in `tokenOut` units.
    event OperatorYieldClaimed(
        address indexed asset,
        address indexed recipient,
        address indexed operator,
        uint256 requestedAssetAmount,
        address tokenOut,
        uint256 amountOut
    );

    /// @notice Emitted when an operator borrowing withdrawal transfers vault shares.
    /// @param asset The underlying asset in which the request is denominated.
    /// @param operator The deposit operator whose borrowing accounting changed.
    /// @param recipient The output-token recipient.
    /// @param requestedAssetAmount The borrowed amount in underlying-asset units.
    /// @param tokenOut The configured share token transferred.
    /// @param amountOut The quantity transferred in `tokenOut` units.
    event BorrowingWithdrawal(
        address indexed asset,
        address indexed operator,
        address indexed recipient,
        uint256 requestedAssetAmount,
        address tokenOut,
        uint256 amountOut
    );

    // ========== ASSET CONFIGURATION ========== //

    /// @notice Configures an asset and records whether it requires share-token withdrawals.
    /// @param asset_ The underlying asset.
    /// @param vault_ The custody vault, or the zero address for idle custody.
    /// @param depositCap_ The maximum underlying-denominated deposits per operator.
    /// @param minimumDeposit_ The minimum underlying-denominated deposit.
    /// @param requiresShareWithdrawal_ Whether underlying withdrawals are unsupported even when
    ///        the vault does not advertise ERC-7540 asynchronous redemption.
    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_,
        bool requiresShareWithdrawal_
    ) external;

    /// @notice Updates the explicit share-withdrawal requirement for a configured asset.
    /// @param asset_ The configured underlying asset.
    /// @param required_ Whether underlying withdrawals are unsupported.
    function setAssetShareWithdrawalRequired(IERC20 asset_, bool required_) external;

    // ========== PREVIEW FUNCTIONS ========== //

    /// @notice Estimates the custody credit and shares for a deposit at the current vault state.
    /// @dev This is a conversion-only estimate. A vault conversion may change during deposit, so
    ///      the actual post-deposit credit returned by `deposit` remains authoritative.
    /// @param asset_ The configured underlying asset.
    /// @param assetAmount_ The proposed deposit amount in underlying-asset units.
    /// @return estimatedCreditedAssets Estimated receipt credit in underlying-asset units.
    /// @return estimatedCustodyShares Estimated custody quantity in vault-share units, or raw
    ///         asset units when no vault is configured.
    function previewDeposit(
        IERC20 asset_,
        uint256 assetAmount_
    ) external view returns (uint256 estimatedCreditedAssets, uint256 estimatedCustodyShares);

    /// @notice Estimates a withdrawal conversion at the current vault state.
    /// @dev This does not validate authorization, receipt ownership, solvency, enabled state, or
    ///      later vault-state changes. It does validate whether the selected output mode is
    ///      currently supported.
    /// @param asset_ The configured underlying asset.
    /// @param assetAmount_ The requested amount in underlying-asset units.
    /// @param withdrawAsShares_ Whether to return configured shares instead of underlying assets.
    /// @return tokenOut The token expected to be transferred.
    /// @return amountOut The estimated quantity in `tokenOut` units.
    function previewWithdraw(
        IERC20 asset_,
        uint256 assetAmount_,
        bool withdrawAsShares_
    ) external view returns (IERC20 tokenOut, uint256 amountOut);

    // ========== WITHDRAWAL FUNCTIONS ========== //

    /// @notice Withdraws receipt-backed collateral in underlying assets or vault shares.
    /// @dev A positive request that rounds to zero output may still burn receipt tokens, reduce the
    ///      underlying-denominated liability, and emit `AssetWithdrawn` with zero `amountOut`
    ///      without transferring custody shares.
    /// @param params_ The V1 withdrawal parameters, denominated in the underlying asset.
    /// @param withdrawAsShares_ Whether to transfer configured shares instead of redeeming them.
    /// @return tokenOut The token transferred to the recipient.
    /// @return amountOut The quantity transferred in `tokenOut` units.
    function withdraw(
        WithdrawParams calldata params_,
        bool withdrawAsShares_
    ) external returns (IERC20 tokenOut, uint256 amountOut);

    /// @notice Claims operator yield in underlying assets or vault shares.
    /// @dev A positive request that rounds to zero output is a no-op for accounting and transfers.
    ///      It emits `AssetWithdrawn` and the mode-appropriate `OperatorYieldClaimed` event with
    ///      zero `amountOut`.
    /// @param asset_ The configured underlying asset.
    /// @param recipient_ The output-token recipient.
    /// @param assetAmount_ The requested yield in underlying-asset units.
    /// @param withdrawAsShares_ Whether to transfer configured shares instead of redeeming them.
    /// @return tokenOut The token transferred to the recipient.
    /// @return amountOut The quantity transferred in `tokenOut` units.
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 assetAmount_,
        bool withdrawAsShares_
    ) external returns (IERC20 tokenOut, uint256 amountOut);

    /// @notice Borrows from operator custody in underlying assets or vault shares.
    /// @dev All accounting rolls back when output is zero.
    /// @param params_ The V1 borrowing-withdrawal parameters, denominated in the underlying asset.
    /// @param withdrawAsShares_ Whether to transfer configured shares instead of redeeming them.
    /// @return tokenOut The token transferred to the recipient.
    /// @return amountOut The quantity transferred in `tokenOut` units.
    function borrowingWithdraw(
        BorrowingWithdrawParams calldata params_,
        bool withdrawAsShares_
    ) external returns (IERC20 tokenOut, uint256 amountOut);
}
