// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansConstructorTest is BurnerLoansTest {
    // constructor
    // given OHM address is zero
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenOhmIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(kernel, IERC20(address(0)), depositManager, backingOracle);
    }

    // constructor
    // given DepositManager address is zero
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenDepositManagerIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(kernel, IERC20(address(ohm)), IDepositManager(address(0)), backingOracle);
    }

    // constructor
    // given DepositManager does not implement the required interface
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenDepositManagerDoesNotSupportInterface_reverts() public {
        MockInvalidDepositManager invalidDepositManager = new MockInvalidDepositManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(invalidDepositManager)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            IDepositManager(address(invalidDepositManager)),
            backingOracle
        );
    }

    // constructor
    // given DepositManager belongs to another Kernel
    //  when BurnerLoans is deployed
    //   then it rejects the cross-Kernel dependency
    function test_constructor_givenDepositManagerKernelMismatch_reverts() public {
        Kernel otherKernel = new Kernel();
        ReceiptTokenManager otherReceiptTokenManager = new ReceiptTokenManager();
        DepositManager otherDepositManager = new DepositManager(
            address(otherKernel),
            address(otherReceiptTokenManager)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_DepositManagerKernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        new BurnerLoans(kernel, IERC20(address(ohm)), otherDepositManager, backingOracle);
    }

    // constructor
    // given backing oracle address is zero
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenBackingOracleIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            IOlympusBackingOracle(address(0))
        );
    }

    // constructor
    // given backing oracle does not implement IOlympusBackingOracle
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenBackingOracleDoesNotSupportInterface_reverts() public {
        MockInvalidBackingOracle invalidBackingOracle = new MockInvalidBackingOracle();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidBackingOracle.selector,
                address(invalidBackingOracle)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            IOlympusBackingOracle(address(invalidBackingOracle))
        );
    }

    // constructor
    // given constructor parameters are valid
    //  when the deployed BurnerLoans instance is inspected
    //   then immutable dependencies and defaults are set
    function test_constructor_givenValidParams_setsImmutableDependencies() public view {
        assertEq(address(burnerLoans.context().ohm), address(ohm), "ohm");
        assertEq(
            address(burnerLoans.context().depositManager),
            address(depositManager),
            "deposit manager"
        );
        assertEq(
            burnerLoans.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "reenable grace period"
        );
        assertEq(burnerLoans.backingOracle(), address(backingOracle), "backing oracle");
        assertEq(burnerLoans.inventory(), address(inventory), "configured inventory");
    }
}

contract MockInvalidDepositManager is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}

contract MockInvalidBackingOracle is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}

contract MockInvalidInventory is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}
