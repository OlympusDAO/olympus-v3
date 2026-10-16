// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {HEART_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "../RevenueDistributor/RevenueDistributorTest.sol";

abstract contract RevenueDistributorTaskTest is RevenueDistributorTest {
    uint32 internal constant DEFAULT_EXECUTION_GAS_LIMIT = 5_000_000;

    RevenueDistributorTask internal task;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        task = new RevenueDistributorTask(
            kernel,
            address(distributor),
            DEFAULT_EXECUTION_GAS_LIMIT
        );
        vm.label(address(task), "Revenue distributor task");
        kernel.executeAction(Actions.ActivatePolicy, address(task));
        task.enable("");
        rolesAdmin.grantRole(HEART_ROLE, alice);
        vm.stopPrank();
    }

    function _grantRevenueDistributorAdmin(address account_) internal {
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, account_);
    }

    function _authorizedTaskAdmin(bool adminCalls_) internal returns (address caller_) {
        if (adminCalls_) return admin;
        _grantRevenueDistributorAdmin(bob);
        return bob;
    }

    function _newActivatedTask() internal returns (RevenueDistributorTask fresh_) {
        fresh_ = new RevenueDistributorTask(
            kernel,
            address(distributor),
            DEFAULT_EXECUTION_GAS_LIMIT
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh_));
    }

    function _disableTask(bytes memory data_) internal {
        vm.prank(emergency);
        task.disable(data_);
    }

    function _setTaskDisabled(bool disabled_) internal {
        if (disabled_) _disableTask("");
    }

    function _setTaskLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) _disableTask("");
        if (!active_) _deactivateTask();
    }

    function _setDistributorLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) _disableDistributor();
        if (!active_) _deactivateDistributor();
    }

    function _deactivateTask() internal {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(task));
    }

    function _disableDistributor() internal {
        vm.prank(emergency);
        distributor.disable("");
    }

    function _deactivateDistributor() internal {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
    }

    function _expectInvalidDistributor() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_InvalidDistributor.selector,
                address(distributor)
            )
        );
    }

    function _boundUint8(uint8 value_, uint8 min_, uint8 max_) internal pure returns (uint8) {
        // bound() guarantees that the result remains within the supplied uint8 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(bound(value_, min_, max_));
    }

    function _boundUint32(uint32 value_, uint32 min_, uint32 max_) internal pure returns (uint32) {
        // bound() guarantees that the result remains within the supplied uint32 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(bound(value_, min_, max_));
    }

    function _boundUint48(uint48 value_, uint48 min_, uint48 max_) internal pure returns (uint48) {
        // bound() guarantees that the result remains within the supplied uint48 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint48(bound(value_, min_, max_));
    }

    // Test scenarios cap generated asset arrays at 13 entries.
    // forge-lint: disable-start(calls-loop)
    function _configureAsset(MockERC20 asset_, uint256 receipt_) internal {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(asset_), 0, routes);
        if (receipt_ != 0) asset_.mint(address(distributor), receipt_);
    }

    function _configureAssets(
        uint256 count_,
        uint256 receipt_
    ) internal returns (MockERC20[] memory assets_) {
        assets_ = new MockERC20[](count_);
        for (uint256 i; i < count_; ++i) {
            assets_[i] = new MockERC20("Revenue", "REV", 18);
            _configureAsset(assets_[i], receipt_);
        }
    }
    // forge-lint: disable-end(calls-loop)
}
