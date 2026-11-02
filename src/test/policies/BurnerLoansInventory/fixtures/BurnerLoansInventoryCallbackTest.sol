// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

// Interfaces

// Libraries

import {ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryTest} from "../BurnerLoansInventoryTest.sol";
import {InventoryCallbackOhm} from "./InventoryCallbackOhm.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

abstract contract BurnerLoansInventoryCallbackTest is BurnerLoansInventoryTest {
    InventoryCallbackOhm internal _token;

    function _deployOhm() internal override returns (MockOhm) {
        return new InventoryCallbackOhm();
    }

    function setUp() public override {
        super.setUp();
        _token = InventoryCallbackOhm(address(ohm));
        _enableAndSetCap(1000);
        _supply(100);
        // An unrelated provider has a real, funded claim for the nested withdrawal.
        vm.startPrank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, address(_token));
        rolesAdmin.grantRole(ADMIN_ROLE, address(_token));
        vm.stopPrank();
        ohm.mint(address(_token), 7);
        vm.startPrank(address(_token));
        ohm.approve(address(inventory), 7);
        inventory.supply(7);
        vm.stopPrank();
        // A draw consumes all idle before calling the token. Keep an independent unit
        // and allowance so its nested supply remains valid even when no idle is left.
        ohm.mint(address(_token), 1);
        vm.prank(address(_token));
        ohm.approve(address(inventory), 1);
    }

    function _armWithdrawal(bytes4 phase_, bool bubble_) internal {
        _token.arm(
            phase_,
            address(inventory),
            abi.encodeCall(inventory.withdraw, (1, outsider)),
            bubble_
        );
    }

    function _assertNestedRejected() internal view {
        assertEq(
            _token.rejection(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            "Nested operation reaches Inventory guard"
        );
        assertEq(
            inventory.providerClaimOhm(address(_token)),
            7,
            "Unrelated provider claim preserved"
        );
        assertEq(ohm.balanceOf(outsider), 0, "Nested withdrawal did not pay");
        assertEq(ohm.balanceOf(address(_token)), 1, "Nested supply did not spend reserve");
        assertEq(
            ohm.allowance(address(_token), address(inventory)),
            1,
            "Nested allowance preserved"
        );
    }

    function _armSupply(bytes4 phase_, bool bubble_) internal {
        _token.arm(phase_, address(inventory), abi.encodeCall(inventory.supply, (1)), bubble_);
    }

    function _expectPropagatedRejection() internal {
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return)
