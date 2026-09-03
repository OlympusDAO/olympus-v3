// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Contracts
import {BurnerLoansYieldRoutingTestBase} from "./fixtures/BurnerLoansYieldRoutingTestBase.sol";

contract BurnerLoansSetYieldRecipientAssetBpsTest is BurnerLoansYieldRoutingTestBase {
    function test_setYieldRecipientAssetBps_givenCallerIsNotConfigurator_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_OnlyConfigurator.selector, caller_)
        );
        vm.prank(caller_);
        burnerLoans.setYieldRecipientAssetBps(address(usds), 1);
    }

    function test_setYieldRecipientAssetBps_givenBurnerLoansDisabled_reverts() public {
        _configureDefaultUsdsYieldRecipient();
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _setYieldRecipientAssetBps(address(usds), 1);
    }

    function test_setYieldRecipientAssetBps_givenBpsAboveMaximum_reverts(uint16 bps_) public {
        bps_ = uint16(bound(bps_, 10_001, type(uint16).max));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, uint256(bps_))
        );
        _setYieldRecipientAssetBps(address(usds), bps_);
    }

    function test_setYieldRecipientAssetBps_givenAssetNotInDepositManagerOrBurnerLoans_reverts(
        uint16 bps_
    ) public {
        bps_ = uint16(bound(bps_, 0, 10_000));
        address asset = makeAddr("unconfiguredAsset");

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset)
        );
        _setYieldRecipientAssetBps(asset, bps_);
    }

    function test_setYieldRecipientAssetBps_givenAssetInDepositManagerButNotBurnerLoans_reverts(
        uint16 bps_
    ) public {
        bps_ = uint16(bound(bps_, 0, 10_000));
        _configureDepositManagerAsset(address(usds));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        _setYieldRecipientAssetBps(address(usds), bps_);
    }

    function test_setYieldRecipientAssetBps_givenYieldRecipientIsZero_reverts(uint16 bps_) public {
        bps_ = uint16(bound(bps_, 0, 10_000));
        _addDefaultUsdsAsset();

        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        _setYieldRecipientAssetBps(address(usds), bps_);
    }

    function test_setYieldRecipientAssetBps_givenValidBps_setsAllocation(uint16 bps_) public {
        bps_ = uint16(bound(bps_, 1, 10_000));
        _configureDefaultUsdsYieldRecipient();

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.YieldRecipientAssetBpsSet(address(usds), bps_);
        _setYieldRecipientAssetBps(address(usds), bps_);

        assertEq(burnerLoans.getYieldRecipientAssetBps(address(usds)), bps_, "asset bps");
    }

    function test_setYieldRecipientAssetBps_givenZeroVault_acceptsExactPair() public {
        _configureDefaultUsdsYieldRecipient();

        _setYieldRecipientAssetBps(address(usds), 10_000);

        assertEq(
            burnerLoans.getYieldRecipientAssetBps(address(usds)),
            10_000,
            "zero-vault allocation"
        );
    }

    function test_setYieldRecipientAssetBps_givenReturnedVaultMismatch_reverts() public {
        _addDefaultUsdsAsset();
        _configureYieldRecipientAsset(address(usds), address(0));
        yieldRecipient.setReturnedVault(address(0), makeAddr("differentVault"));
        _setYieldRecipient(address(yieldRecipient));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientAssetVaultMismatch.selector,
                address(0),
                makeAddr("differentVault")
            )
        );
        _setYieldRecipientAssetBps(address(usds), 1);
    }

    function test_setYieldRecipientAssetBps_givenAssetMismatch_reverts() public {
        _addDefaultUsdsAsset();
        _configureYieldRecipientAsset(makeAddr("differentAsset"), address(0));
        _setYieldRecipient(address(yieldRecipient));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientAssetMismatch.selector,
                address(usds),
                makeAddr("differentAsset")
            )
        );
        _setYieldRecipientAssetBps(address(usds), 1);
    }

    function test_setYieldRecipientAssetBps_givenRecipientAssetDisabled_reverts() public {
        _addDefaultUsdsAsset();
        yieldRecipient.setVaultConfig(address(0), address(usds), false);
        _setYieldRecipient(address(yieldRecipient));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientAssetNotEnabled.selector,
                address(yieldRecipient),
                address(usds),
                address(0)
            )
        );
        _setYieldRecipientAssetBps(address(usds), 1);
    }

    function test_setYieldRecipientAssetBps_givenYieldRecipientIsDisabled_whenAssetBpsIsNonZero_reverts()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 5_000);
        yieldRecipient.setEnabled(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRecipientAssetBps(address(usds), 5_000);
    }

    function test_setYieldRecipientAssetBps_givenSameValidValue_isNoOp() public {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 5_000);
        vm.recordLogs();

        _setYieldRecipientAssetBps(address(usds), 5_000);

        assertEq(vm.getRecordedLogs().length, 0, "no-op event count");
    }

    function test_setYieldRecipientAssetBps_givenYieldRecipientIsDisabled_whenAssetBpsIsZero_clearsAllocation()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 5_000);
        yieldRecipient.setEnabled(false);

        _setYieldRecipientAssetBps(address(usds), 0);

        assertEq(burnerLoans.getYieldRecipientAssetBps(address(usds)), 0, "cleared asset bps");
    }

    function test_setYieldRecipientAssetBps_givenAlreadyZero_isNoOp() public {
        _configureDefaultUsdsYieldRecipient();
        vm.recordLogs();

        _setYieldRecipientAssetBps(address(usds), 0);

        assertEq(vm.getRecordedLogs().length, 0, "no-op event count");
    }
}
