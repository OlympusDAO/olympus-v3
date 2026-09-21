// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";

// Contracts
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansYieldRoutingTestBase} from "./fixtures/BurnerLoansYieldRoutingTestBase.sol";
import {MockYieldRepurchaseRecipient} from "./fixtures/MockYieldRepurchaseRecipient.sol";

contract BurnerLoansSetYieldRepurchaseRecipientTest is BurnerLoansYieldRoutingTestBase {
    function test_whenCallerIsNotConfigurator_reverts(address caller_) public {
        vm.assume(caller_ != address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_OnlyConfigurator.selector, caller_)
        );
        vm.prank(caller_);
        burnerLoans.setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_givenBurnerLoansDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_whenRecipientIsBurnerLoans_revertsBeforeInterfaceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidYieldRepurchaseRecipient.selector,
                address(burnerLoans)
            )
        );
        _setYieldRepurchaseRecipient(address(burnerLoans));
    }

    function test_whenRecipientIsTreasury_revertsBeforeInterfaceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidYieldRepurchaseRecipient.selector,
                address(trsry)
            )
        );
        _setYieldRepurchaseRecipient(address(trsry));
    }

    function test_whenRecipientDoesNotSupportRepurchaseInterface_reverts() public {
        yieldRecipient.setSupportsYieldRepurchaseInterface(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidYieldRepurchaseRecipient.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_whenRecipientDoesNotSupportEnablerInterface_reverts() public {
        yieldRecipient.setSupportsEnablerInterface(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidYieldRepurchaseRecipient.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_whenRecipientIsNotActivePolicy_reverts() public {
        MockYieldRepurchaseRecipient inactive = new MockYieldRepurchaseRecipient(kernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotActivePolicy.selector,
                address(inactive)
            )
        );
        _setYieldRepurchaseRecipient(address(inactive));
    }

    function test_whenRecipientIsDisabled_reverts() public {
        yieldRecipient.setEnabled(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_whenRecipientIsValid_setsRecipient() public {
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.YieldRepurchaseRecipientSet(address(yieldRecipient));
        _setYieldRepurchaseRecipient(address(yieldRecipient));

        assertEq(
            burnerLoans.getYieldRepurchaseRecipient(),
            address(yieldRecipient),
            "repurchase recipient"
        );
    }

    function test_givenSameRecipient_revalidatesThenEmitsNoEvent() public {
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        vm.recordLogs();
        _setYieldRepurchaseRecipient(address(yieldRecipient));

        assertEq(vm.getRecordedLogs().length, 0, "no-op event count");

        yieldRecipient.setEnabled(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        _setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_givenActiveRepurchaseRoute_whenRecipientCleared_reverts() public {
        (MockERC20 asset, ) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        _setYieldAssetRouting(address(asset), _repurchaseRouting(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseAllocationsActive.selector,
                1
            )
        );
        _setYieldRepurchaseRecipient(address(0));
    }

    function test_givenTwoActiveRepurchaseRoutes_whenRecipientCleared_reverts() public {
        (MockERC20 firstAsset, ) = _addYieldAsset();
        (MockERC20 secondAsset, ) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        _setYieldAssetRouting(address(firstAsset), _repurchaseRouting(1));
        _setYieldAssetRouting(address(secondAsset), _repurchaseRouting(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseAllocationsActive.selector,
                2
            )
        );
        _setYieldRepurchaseRecipient(address(0));
    }

    function test_givenFinalRepurchaseRouteCleared_whenRecipientCleared_succeeds() public {
        (MockERC20 asset, ) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        _setYieldAssetRouting(address(asset), _repurchaseRouting(1));
        _setYieldAssetRouting(address(asset), _treasuryOnlyRouting());

        _setYieldRepurchaseRecipient(address(0));

        assertEq(burnerLoans.getYieldRepurchaseRecipient(), address(0), "cleared recipient");
    }

    function test_givenActiveRoutes_whenReplacementMissingVault_revertsAtomically() public {
        (MockERC20 firstAsset, MockERC4626 firstVault) = _addYieldAsset();
        (MockERC20 secondAsset, MockERC4626 secondVault) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        _setYieldAssetRouting(address(firstAsset), _repurchaseRouting(4_000));
        _setYieldAssetRouting(address(secondAsset), _repurchaseRouting(1));

        MockYieldRepurchaseRecipient replacement = new MockYieldRepurchaseRecipient(kernel);
        replacement.setVaultConfig(address(firstVault), address(firstAsset), true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseRecipient.YieldRepurchaseRecipient_VaultNotRegistered.selector,
                address(secondVault)
            )
        );
        _setYieldRepurchaseRecipient(address(replacement));

        assertEq(
            burnerLoans.getYieldRepurchaseRecipient(),
            address(yieldRecipient),
            "recipient unchanged"
        );
    }

    function test_givenStoredDirectRecipient_whenRotatingToThatRecipient_reverts() public {
        _addDefaultUsdsAsset();
        MockYieldRepurchaseRecipient replacement = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));

        address[] memory recipients = new address[](1);
        recipients[0] = address(replacement);
        uint16[] memory bps = new uint16[](1);
        bps[0] = 1;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient.selector,
                address(replacement)
            )
        );
        _setYieldRepurchaseRecipient(address(replacement));
    }
}
