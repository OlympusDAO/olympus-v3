// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {RevenueDistributorHarness} from "./RevenueDistributorHarness.sol";

/// @dev A token callback records post-debit reads for comparison with the final state.
contract RevenueDistributorRescueObserver {
    uint256 public entitlement;
    uint256 public preview;
    bytes public failure;
    bytes32 public state;

    /// @dev Probe one unit, catching the expected insufficient-entitlement error after full drainage.
    function observe(
        RevenueDistributorHarness rd_,
        IERC20 asset_,
        address recipient_,
        address destination_
    ) external {
        entitlement = rd_.pendingPayout(address(asset_), recipient_);
        try rd_.previewRescuePendingPayout(address(asset_), recipient_, destination_, 1) returns (
            uint256 available
        ) {
            preview = available;
        } catch (bytes memory errorData) {
            failure = errorData;
        }
        state = observation(rd_, asset_, recipient_, destination_);
    }

    /// @dev Include raw accounting, indexes, config and custody; exclude the observer's own storage.
    function observation(
        RevenueDistributorHarness rd_,
        IERC20 asset_,
        address recipient_,
        address destination_
    ) public view returns (bytes32) {
        bytes32 accounting = keccak256(
            abi.encode(
                rd_.pendingAssetRouteForTest(address(asset_), recipient_),
                rd_.pendingRepurchaseForTest(address(asset_)),
                rd_.pendingTreasuryForTest(address(asset_)),
                rd_.totalPendingForTest(address(asset_)),
                rd_.getPendingPayoutAssets(),
                rd_.getPendingPayoutRecipients(address(asset_))
            )
        );
        bytes32 config = keccak256(
            abi.encode(
                rd_.assetState(address(asset_)),
                rd_.configOperator(),
                rd_.yieldRecipient(),
                rd_.treasury()
            )
        );
        return
            keccak256(
                abi.encode(
                    accounting,
                    config,
                    asset_.balanceOf(address(rd_)),
                    asset_.balanceOf(destination_)
                )
            );
    }
}
