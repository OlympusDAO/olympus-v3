// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

import {BurnerLoansYieldRoutingTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansYieldRoutingTestBase.sol";

contract BurnerLoansConfigSetYieldRecipientAssetBpsTest is BurnerLoansYieldRoutingTestBase {
    event YieldRecipientAssetBpsSet(address indexed asset, uint16 bps);

    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
        _configureYieldRecipientAsset(address(usds), address(0));
        vm.prank(admin);
        burnerLoansConfig.setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipientAssetBps_givenUnauthorizedCaller_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        burnerLoansConfig.setYieldRecipientAssetBps(address(usds), 5_000);
    }

    function test_setYieldRecipientAssetBps_givenBurnerLoansAdminCallsDirectly_reverts() public {
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                burnerLoansAdmin
            )
        );
        burnerLoansConfig.setYieldRecipientAssetBps(address(usds), 5_000);
    }

    function test_setYieldRecipientAssetBps_givenConfigDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setYieldRecipientAssetBps(address(usds), 5_000);
    }

    function test_setYieldRecipientAssetBps_givenAdmin_forwardsWithoutDuplicateEvent_fuzz(
        uint16 bps_
    ) public {
        bps_ = uint16(bound(bps_, 1, 10_000));

        vm.recordLogs();
        vm.prank(admin);
        burnerLoansConfig.setYieldRecipientAssetBps(address(usds), bps_);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "configuration event count");
        assertEq(entries[0].emitter, address(burnerLoans), "configuration event emitter");
        assertEq(
            burnerLoans.getYieldRecipientAssetBps(address(usds)),
            bps_,
            "asset yield recipient bps"
        );
    }

    function test_setYieldRecipientAssetBps_givenConfigOperator_forwards() public {
        _setDefaultConfigOperator();

        vm.prank(address(configTimelock));
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit YieldRecipientAssetBpsSet(address(usds), 5_000);
        burnerLoansConfig.setYieldRecipientAssetBps(address(usds), 5_000);

        assertEq(
            burnerLoans.getYieldRecipientAssetBps(address(usds)),
            5_000,
            "asset yield recipient bps"
        );
    }
}
