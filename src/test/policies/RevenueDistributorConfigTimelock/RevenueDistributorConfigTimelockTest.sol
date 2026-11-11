// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Libraries
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
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
        _setPolicyActive(address(configTimelock), false);
    }

    function _permittedProposer(bool useRevenueAdmin_) internal returns (address proposer) {
        if (_proposerSeed != address(0)) return _proposerSeed;
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
        _setPolicyActive(address(recipient), true);
    }

    function _queueRoute(address asset_) internal returns (uint64 actionId) {
        vm.prank(admin);
        actionId = configTimelock.queueSetAssetRoutes(asset_, 0, _emptyRoutes());
    }

    function _routeStateHash(address asset_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(distributor.assetDistributionHash(asset_), distributor.configOperator())
            );
    }

    function _queuedKey(uint64 actionId_, uint256 index_) internal view returns (bytes32 key) {
        // Callers only need the key; the expected configuration hash is intentionally omitted.
        // forge-lint: disable-next-line(unused-return)
        (key, ) = configTimelock.getQueuedConfigState(actionId_, index_, 0);
    }

    function _newTimelock() internal returns (RevenueDistributorConfigTimelock fresh_) {
        return new RevenueDistributorConfigTimelock(kernel, distributor);
    }

    function _newActivatedTimelock() internal returns (RevenueDistributorConfigTimelock fresh_) {
        fresh_ = _newTimelock();
        _setPolicyActive(address(fresh_), true);
        vm.prank(admin);
        distributor.setConfigOperator(address(fresh_));
    }

    function _newTimelockWithoutModules()
        internal
        returns (Kernel freshKernel_, RevenueDistributorConfigTimelock fresh_)
    {
        freshKernel_ = new Kernel();
        fresh_ = new RevenueDistributorConfigTimelock(
            freshKernel_,
            new RevenueDistributor(freshKernel_)
        );
    }

    function _moveDistributorToDifferentKernel() internal returns (Kernel otherKernel) {
        otherKernel = new Kernel();
        vm.prank(address(kernel));
        distributor.changeKernel(otherKernel);
    }
}
// forge-lint: disable-end(calls-loop)
