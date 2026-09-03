// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IYieldRecipient} from "src/policies/interfaces/IYieldRecipient.sol";

import {BurnerLoansYieldRoutingTestBase} from "./fixtures/BurnerLoansYieldRoutingTestBase.sol";
import {MockYieldRecipient} from "./fixtures/MockYieldRecipient.sol";

contract BurnerLoansSetYieldRecipientTest is BurnerLoansYieldRoutingTestBase {
    function test_setYieldRecipient_givenCallerIsNotConfigurator_reverts(address caller_) public {
        vm.assume(caller_ != address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_OnlyConfigurator.selector, caller_)
        );
        vm.prank(caller_);
        burnerLoans.setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenBurnerLoansDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenRecipientIsNotRegisteredWithKernel_reverts() public {
        MockYieldRecipient unregistered = new MockYieldRecipient(kernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientNotActivePolicy.selector,
                address(unregistered)
            )
        );
        _setYieldRecipient(address(unregistered));
    }

    function test_setYieldRecipient_givenRecipientPolicyIsNotActive_reverts() public {
        MockYieldRecipient inactive = new MockYieldRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(inactive));
        kernel.executeAction(Actions.DeactivatePolicy, address(inactive));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientNotActivePolicy.selector,
                address(inactive)
            )
        );
        _setYieldRecipient(address(inactive));
    }

    function test_setYieldRecipient_givenRecipientDoesNotSupportYieldInterface_reverts() public {
        yieldRecipient.setSupportsYieldInterface(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidYieldRecipient.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenRecipientDoesNotSupportIEnabler_reverts() public {
        yieldRecipient.setSupportsEnablerInterface(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidYieldRecipient.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenRecipientIsDisabled_reverts() public {
        yieldRecipient.setEnabled(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenValidRecipient_setsRecipient() public {
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.YieldRecipientSet(address(yieldRecipient));
        _setYieldRecipient(address(yieldRecipient));

        assertEq(burnerLoans.getYieldRecipient(), address(yieldRecipient), "yield recipient");
    }

    function test_setYieldRecipient_givenSameValidRecipient_isNoOpAfterRevalidation() public {
        _setYieldRecipient(address(yieldRecipient));
        vm.recordLogs();
        _setYieldRecipient(address(yieldRecipient));

        assertEq(vm.getRecordedLogs().length, 0, "no-op event count");
    }

    function test_setYieldRecipient_givenYieldRecipientIsDisabled_whenRecipientIsUnchanged_reverts()
        public
    {
        _setYieldRecipient(address(yieldRecipient));
        yieldRecipient.setEnabled(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenActiveAllocations_whenNewYieldRecipientIsZero_reverts()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 5_000);

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_YieldAllocationsActive.selector, 1)
        );
        _setYieldRecipient(address(0));
    }

    function test_setYieldRecipient_givenOneOfMultipleAllocationsIsActive_whenNewYieldRecipientIsZero_reverts()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 5_000);
        (MockERC20 asset, ) = _addYieldAsset();
        _setYieldRecipientAssetBps(address(asset), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_YieldAllocationsActive.selector, 1)
        );
        _setYieldRecipient(address(0));
    }

    function test_setYieldRecipient_givenFinalAllocationCleared_whenNewYieldRecipientIsZero()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 5_000);
        _setYieldRecipientAssetBps(address(usds), 0);

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.YieldRecipientSet(address(0));
        _setYieldRecipient(address(0));

        assertEq(burnerLoans.getYieldRecipient(), address(0), "yield recipient");
    }

    function test_setYieldRecipient_whenNewYieldRecipientIsNonZero_preservesAllocations() public {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 4_000);
        (MockERC20 asset, MockERC4626 vault) = _addYieldAsset();
        _setYieldRecipientAssetBps(address(asset), 7_000);

        MockYieldRecipient replacement = new MockYieldRecipient(kernel);
        replacement.setVaultConfig(address(0), address(usds), true);
        replacement.setVaultConfig(address(vault), address(asset), true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));

        _setYieldRecipient(address(replacement));

        assertEq(burnerLoans.getYieldRecipientAssetBps(address(usds)), 4_000, "USDS allocation");
        assertEq(burnerLoans.getYieldRecipientAssetBps(address(asset)), 7_000, "second allocation");
        assertEq(burnerLoans.getYieldRecipient(), address(replacement), "replacement recipient");
    }

    function test_setYieldRecipient_givenRecipientMissingAllocatedAsset_whenNewYieldRecipientIsNonZero_reverts()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 4_000);
        (MockERC20 asset, MockERC4626 vault) = _addYieldAsset();
        _setYieldRecipientAssetBps(address(asset), 7_000);

        MockYieldRecipient replacement = new MockYieldRecipient(kernel);
        replacement.setVaultConfig(address(0), address(usds), true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRecipient.YieldRecipient_VaultNotRegistered.selector,
                address(vault)
            )
        );
        _setYieldRecipient(address(replacement));

        assertEq(burnerLoans.getYieldRecipient(), address(yieldRecipient), "recipient unchanged");
        assertEq(burnerLoans.getYieldRecipientAssetBps(address(usds)), 4_000, "USDS allocation");
        assertEq(burnerLoans.getYieldRecipientAssetBps(address(asset)), 7_000, "second allocation");
    }

    function test_setYieldRecipient_givenRecipientVaultMismatch_whenNewYieldRecipientIsNonZero_reverts()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 4_000);
        address returnedVault = makeAddr("returnedVault");

        MockYieldRecipient replacement = new MockYieldRecipient(kernel);
        replacement.setVaultConfig(address(0), address(usds), true);
        replacement.setReturnedVault(address(0), returnedVault);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientAssetVaultMismatch.selector,
                address(0),
                returnedVault
            )
        );
        _setYieldRecipient(address(replacement));

        assertEq(burnerLoans.getYieldRecipient(), address(yieldRecipient), "recipient unchanged");
    }

    function test_setYieldRecipient_givenRecipientAssetMismatch_whenNewYieldRecipientIsNonZero_reverts()
        public
    {
        _configureDefaultUsdsYieldRecipient();
        _setYieldRecipientAssetBps(address(usds), 4_000);
        address returnedAsset = makeAddr("returnedAsset");

        MockYieldRecipient replacement = new MockYieldRecipient(kernel);
        replacement.setVaultConfig(address(0), returnedAsset, true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientAssetMismatch.selector,
                address(usds),
                returnedAsset
            )
        );
        _setYieldRecipient(address(replacement));

        assertEq(burnerLoans.getYieldRecipient(), address(yieldRecipient), "recipient unchanged");
    }
}
