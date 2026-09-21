// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";

// Contracts
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryBurnSurplusTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    function test_givenSurplus_burnsFullAmount(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max - ohm.totalSupply());
        ohm.mint(address(inventory), amount_);
        uint256 supplyBefore = ohm.totalSupply();

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.SurplusBurned(amount_);
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(inventory.surplusOhm(), 0, "surplus burned");
        assertEq(ohm.totalSupply(), supplyBefore - amount_, "total supply reduced");
        _assertInventoryInvariant();
    }

    function test_givenNoSurplus_isNoOp() public {
        vm.recordLogs();
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(vm.getRecordedLogs().length, 0, "no event");
        assertEq(inventory.surplusOhm(), 0, "no surplus");
        _assertInventoryInvariant();
    }

    function test_givenBurnFailure_revertsAndPreservesSurplus(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max - ohm.totalSupply());
        ohm.mint(address(inventory), amount_);
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.burnOhm, (address(inventory), amount_)),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(inventory.surplusOhm(), amount_, "surplus preserved");
        _assertInventoryInvariant();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        inventory.burnSurplus();
    }

    function test_givenGloballyDisabled_reverts(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max - ohm.totalSupply());
        ohm.mint(address(inventory), amount_);
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(inventory.surplusOhm(), amount_, "surplus unchanged");
    }
}
