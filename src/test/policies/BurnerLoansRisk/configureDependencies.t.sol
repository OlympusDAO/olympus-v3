// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";

// Contracts
import {Actions, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskConfigureDependenciesTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-CONSTRUCTOR-D13.
    function test_whenPriceDecimalsAreUnsupported_reverts(uint8 decimals_, address caller_) public {
        decimals_ = uint8(bound(decimals_, 78, type(uint8).max));
        _price.setPriceDecimals(decimals_);

        vm.expectRevert(
            abi.encodeWithSelector(LoanMath.LoanMath_UnsupportedDecimals.selector, decimals_)
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D13.
    function test_whenPriceDecimalsAre78_reverts() public {
        _price.setPriceDecimals(78);

        vm.expectRevert(
            abi.encodeWithSelector(LoanMath.LoanMath_UnsupportedDecimals.selector, uint8(78))
        );
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D13.
    function test_whenPriceDecimalsAreMaximum_reverts() public {
        _price.setPriceDecimals(type(uint8).max);

        vm.expectRevert(
            abi.encodeWithSelector(LoanMath.LoanMath_UnsupportedDecimals.selector, type(uint8).max)
        );
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D14.
    function test_whenPriceDecimalsAreSupported(uint8 decimals_, address caller_) public {
        decimals_ = uint8(bound(decimals_, 0, 77));
        _price.setPriceDecimals(decimals_);

        vm.prank(caller_);
        Keycode[] memory dependencies = _risk.configureDependencies();

        _assertDependencies(dependencies);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D14.
    function test_whenPriceDecimalsAreZero() public {
        _price.setPriceDecimals(0);
        _assertDependencies(_risk.configureDependencies());
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D14.
    function test_whenPriceDecimalsAre77() public {
        _price.setPriceDecimals(77);
        _assertDependencies(_risk.configureDependencies());
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D15.
    function test_givenUnsupportedPriceDecimals_whenRiskActivated_reverts() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _price.setPriceDecimals(78);

        vm.expectRevert(
            abi.encodeWithSelector(LoanMath.LoanMath_UnsupportedDecimals.selector, uint8(78))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));

        assertFalse(_risk.isActive(), "Failed dependency configuration leaves Risk inactive");
        assertTrue(_risk.isEnabled(), "Failed activation preserves the prior local enabled state");
    }

    function _assertDependencies(Keycode[] memory dependencies) internal pure {
        assertEq(dependencies.length, 3, "Risk has exactly three module dependencies");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "First dependency is ROLES"
        );
        assertEq(
            Keycode.unwrap(dependencies[1]),
            Keycode.unwrap(toKeycode("PRICE")),
            "Second dependency is PRICE"
        );
        assertEq(
            Keycode.unwrap(dependencies[2]),
            Keycode.unwrap(toKeycode("FLOAN")),
            "Third dependency is FLOAN"
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D06.
    function test_givenMissingROLES_whenDependenciesConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("ROLES")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D09.
    function test_givenIncompatibleROLES_whenDependenciesConfigured_reverts(
        address caller_,
        uint8 major_,
        uint8 minor_
    ) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(_roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, minor_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_WrongModuleVersion.selector, abi.encode([1, 2, 1]))
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D07.
    function test_givenMissingPRICE_whenDependenciesConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("PRICE")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("PRICE"))
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D10.
    function test_givenIncompatiblePRICE_whenDependenciesConfigured_reverts(
        address caller_,
        uint8 major_,
        uint8 minor_
    ) public {
        vm.assume(major_ != 2);
        vm.mockCall(
            address(_price),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, minor_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_WrongModuleVersion.selector, abi.encode([1, 2, 1]))
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D08.
    function test_givenMissingFLOAN_whenDependenciesConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("FLOAN")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("FLOAN"))
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D11.
    function test_givenIncompatibleFLOAN_whenDependenciesConfigured_reverts(
        address caller_,
        uint8 major_,
        uint8 minor_
    ) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(_floan),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, minor_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_WrongModuleVersion.selector, abi.encode([1, 2, 1]))
        );
        vm.prank(caller_);
        _risk.configureDependencies();
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D05.
    function test_whenModuleBindingsAreValid(address caller_) public {
        vm.prank(caller_);
        Keycode[] memory dependencies = _risk.configureDependencies();
        assertEq(dependencies.length, 3, "three dependencies");
        assertEq(Keycode.unwrap(dependencies[0]), bytes5("ROLES"), "ROLES first");
        assertEq(Keycode.unwrap(dependencies[1]), bytes5("PRICE"), "PRICE second");
        assertEq(Keycode.unwrap(dependencies[2]), bytes5("FLOAN"), "FLOAN third");
        // Actual reads after configuration prove that the resolved module bindings are usable.
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
        assertEq(_risk.health(_prices(), _MARKET, 1e6, 1e9), 1e18, "FLOAN binding");
        _risk.setConfigOperator(_operator);
    }
}
