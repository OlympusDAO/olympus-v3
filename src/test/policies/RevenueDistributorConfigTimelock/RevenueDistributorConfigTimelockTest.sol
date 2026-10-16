// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

// These fixture helpers are intentionally reusable from finite scenario loops.
// forge-lint: disable-start(calls-loop)
abstract contract RevenueDistributorConfigTimelockTest is RevenueDistributorTest {
    function _disableTimelock() internal {
        vm.prank(emergency);
        configTimelock.disable("");
    }

    function _deactivateTimelock() internal {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
    }

    function _permittedProposer(bool useRevenueAdmin_) internal returns (address proposer) {
        if (!useRevenueAdmin_) return admin;
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, alice);
        return alice;
    }

    function _emptyRoutes() internal pure returns (IRevenueDistributor.AssetRoute[] memory routes) {
        // Empty memory allocation cannot make an external call.
        // forge-lint: disable-next-line(calls-loop)
        routes = new IRevenueDistributor.AssetRoute[](0);
    }

    function _activateAsset(address asset_) internal {
        vm.prank(admin);
        distributor.setAssetRoutes(asset_, 0, _emptyRoutes());
    }

    function _activeYieldRecipient() internal returns (MockYieldRepurchaseRecipient recipient) {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
    }

    function _queueRoute(address asset_) internal returns (uint64 actionId) {
        vm.prank(admin);
        actionId = configTimelock.queueSetAssetRoutes(asset_, 0, _emptyRoutes());
    }

    function _queuedKey(uint64 actionId_, uint256 index_) internal view returns (bytes32 key) {
        // Callers only need the key; the expected configuration hash is intentionally omitted.
        // forge-lint: disable-next-line(unused-return)
        (key, ) = configTimelock.getQueuedConfigState(actionId_, index_, 0);
    }
}
// forge-lint: disable-end(calls-loop)
