// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";

/// @dev Authoritative accounting access and funded scenario seeding; distribution is tested separately.
contract RevenueDistributorHarness is RevenueDistributor {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(Kernel kernel_) RevenueDistributor(kernel_) {}

    function pendingAssetRouteForTest(
        address asset_,
        address recipient_
    ) external view returns (uint256) {
        return _pendingConfiguredDistributions[asset_][recipient_];
    }

    function pendingRepurchaseForTest(address asset_) external view returns (uint256) {
        return _pendingYieldRecipient[asset_];
    }

    function pendingTreasuryForTest(address asset_) external view returns (uint256) {
        return _pendingTreasury[asset_];
    }

    function totalPendingForTest(address asset_) external view returns (uint256) {
        return _totalPending[asset_];
    }

    /// @dev Seed a fresh asset's three raw liabilities without distribution rounding or fixture caps.
    ///      Callers fund custody separately; every seeded amount is in token base units.
    function seedPendingForTest(
        address asset_,
        address routeRecipient_,
        uint256 route_,
        uint256 repurchase_,
        uint256 treasury_
    ) external {
        _pendingConfiguredDistributions[asset_][routeRecipient_] = route_;
        _pendingYieldRecipient[asset_] = repurchase_;
        _pendingTreasury[asset_] = treasury_;
        _totalPending[asset_] = route_ + repurchase_ + treasury_;
        if (route_ != 0) _pendingConfiguredRecipients[asset_].add(routeRecipient_);
        if (_totalPending[asset_] != 0) _pendingAssets.add(asset_);
    }

    /// @dev Add unrelated fixed-address debt to a seeded asset and its authoritative indexes.
    function addPendingRouteForTest(address asset_, address recipient_, uint256 amount_) external {
        _pendingConfiguredDistributions[asset_][recipient_] += amount_;
        _totalPending[asset_] += amount_;
        if (amount_ != 0) {
            _pendingConfiguredRecipients[asset_].add(recipient_);
            _pendingAssets.add(asset_);
        }
    }

    /// @dev Inspect internal membership so filtered public getters cannot hide stale indexes.
    function pendingAssetMemberForTest(address asset_) external view returns (bool) {
        return _pendingAssets.contains(asset_);
    }

    /// @dev Inspect the fixed-address index independently of role-based recipient enumeration.
    function pendingRouteMemberForTest(
        address asset_,
        address recipient_
    ) external view returns (bool) {
        return _pendingConfiguredRecipients[asset_].contains(recipient_);
    }
}
