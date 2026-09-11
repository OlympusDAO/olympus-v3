// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansValidateAssetDependenciesTest is BurnerLoansTest {
    function test_givenPriceAndCustodySupport_succeeds() public {
        _configureUsdsDependencies();

        burnerLoans.validateAssetDependencies(address(usds));
    }

    function test_givenPriceIsNotApproved_reverts() public {
        _configureDepositManagerAsset(address(usds));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.validateAssetDependencies(address(usds));
    }

    function test_givenApprovedPriceIsZero_succeedsWithoutReadingLivePrice() public {
        _configureDepositManagerAsset(address(usds));
        _configurePrice(address(usds), 0);

        burnerLoans.validateAssetDependencies(address(usds));
    }

    function test_givenAssetIsNotConfiguredInDepositManager_reverts() public {
        _configurePrice(address(usds), 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.validateAssetDependencies(address(usds));
    }

    function test_givenDepositPeriodIsDisabled_reverts() public {
        _configureUsdsDependencies();
        depositManager.disableAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.validateAssetDependencies(address(usds));
    }

    function test_givenDepositManagerIsDisabled_reverts() public {
        _configureUsdsDependencies();
        vm.prank(admin);
        _disableDepositManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.validateAssetDependencies(address(usds));
    }

    function test_givenPriceModuleUpgradedWhileFacilityInactive_reverts() public {
        _configureUsdsDependencies();
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        MockPrice replacement = new MockPrice(kernel, PRICE_DECIMALS, uint32(8 hours));
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.stopPrank();

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.validateAssetDependencies(address(usds));
    }
}
