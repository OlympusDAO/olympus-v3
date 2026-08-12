// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryTest} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryDrawTest is BurnerLoansInventoryTest {
    uint128 internal constant DRAW_CAP = 1_000e9;
    uint128 internal constant SUPPLIED_IDLE = 300e9;

    event OhmDrawn(
        address indexed recipient,
        uint256 amount,
        uint256 suppliedAmount,
        uint256 mintedAmount
    );

    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DRAW_CAP);
    }

    // draw
    // [X] given supplied OHM covers part of the request, it uses idle first and mints the shortfall
    function test_givenMixedFunding_drawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, SUPPLIED_IDLE + 1, DRAW_CAP));
        uint128 mintedAmount = amount_ - SUPPLIED_IDLE;
        _supply(SUPPLIED_IDLE);

        vm.expectEmit(true, true, true, true, address(inventory));
        emit OhmDrawn(recipient, amount_, SUPPLIED_IDLE, mintedAmount);
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        _assertInventoryState(recipient, amount_, amount_, SUPPLIED_IDLE, 0, DRAW_CAP - amount_);
    }

    // draw
    // [X] given no supplied OHM, it mints to Burner Loans Inventory and transfers once
    function test_givenMintFunding_drawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, DRAW_CAP));
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        _assertInventoryState(recipient, amount_, amount_, 0, 0, DRAW_CAP - amount_);
    }

    // draw
    // [X] given supplied OHM covers the request, it uses idle without minting
    function test_givenIdleFunding_drawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, SUPPLIED_IDLE));
        _supply(SUPPLIED_IDLE);

        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        _assertInventoryState(
            recipient,
            amount_,
            amount_,
            SUPPLIED_IDLE,
            SUPPLIED_IDLE - amount_,
            DRAW_CAP - SUPPLIED_IDLE
        );
    }

    // draw
    // [X] given MINTR rejects the shortfall mint, the complete draw transition rolls back
    function test_givenMintFailure_revertsAndRollsBack() public {
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.mintOhm, (address(inventory), 100e9)),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(address(facility));
        inventory.draw(recipient, 100e9);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal rolled back");
        assertEq(ohm.balanceOf(address(inventory)), 0, "BLI balance rolled back");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        assertEq(mintr.mintApproval(address(inventory)), 1_000e9, "approval rolled back");
        _assertInventoryInvariant();
    }

    // draw
    // [X] given the trusted OHM transfer fails, minting and BLI accounting roll back
    function test_givenTransferFailure_revertsAndRollsBack() public {
        bytes memory failure = bytes("transfer failed");
        vm.mockCallRevert(
            address(ohm),
            abi.encodeWithSelector(ERC20.transfer.selector, recipient, 100e9),
            failure
        );

        vm.expectRevert(bytes("TRANSFER_FAILED"));
        vm.prank(address(facility));
        inventory.draw(recipient, 100e9);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal rolled back");
        assertEq(ohm.balanceOf(address(inventory)), 0, "BLI balance rolled back");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        assertEq(mintr.mintApproval(address(inventory)), 1_000e9, "approval rolled back");
        _assertInventoryInvariant();
    }

    // draw
    // [X] given the exact available capacity, it succeeds and exhausts capacity
    function test_givenExactCapacity_succeeds() public {
        uint128 capacity = uint128(inventory.availableCapacity());

        vm.prank(address(facility));
        inventory.draw(recipient, capacity);

        assertEq(inventory.availableCapacity(), 0, "capacity exhausted");
        assertEq(ohm.balanceOf(recipient), capacity, "recipient balance");
        _assertInventoryInvariant();
    }

    // draw
    // [X] given external approval is saturated and idle is non-zero, draw remains cap-bounded
    function test_givenMaximumExternalOverApproval_drawRemainsCapBounded() public {
        _supply(1e9);
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), type(uint256).max);

        assertEq(inventory.availableCapacity(), 1_000e9, "capacity remains bounded by cap");

        vm.prank(address(facility));
        inventory.draw(recipient, 1_000e9);

        assertEq(ohm.balanceOf(recipient), 1_000e9, "recipient receives cap");
        assertEq(inventory.activePrincipalOhm(), 1_000e9, "active principal reaches cap");
        assertEq(inventory.availableCapacity(), 0, "capacity exhausted at cap");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                1,
                0
            )
        );
        vm.prank(address(facility));
        inventory.draw(recipient, 1);

        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        _assertInventoryInvariant();
    }

    // draw
    // [X] given the request is one above capacity, it reverts without changing accounting
    function test_givenAmountAboveCapacity_reverts(uint128 amount_) public {
        uint256 capacity = inventory.availableCapacity();
        amount_ = uint128(bound(amount_, capacity + 1, type(uint128).max));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                amount_,
                capacity
            )
        );
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal unchanged");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        _assertInventoryInvariant();
    }

    // draw
    // [X] given an unrelated caller, it reverts with the exact caller
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                caller_
            )
        );
        vm.prank(caller_);
        inventory.draw(recipient, 1);
    }

    // draw
    // [X] given zero amount, it reverts without changing accounting
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(address(facility));
        inventory.draw(recipient, 0);

        _assertInventoryInvariant();
    }

    // draw
    // [X] given a zero recipient, it reverts without changing accounting
    function test_givenZeroRecipient_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        vm.prank(address(facility));
        inventory.draw(address(0), 1);

        _assertInventoryInvariant();
    }

    // draw
    // [X] given Burner Loans Inventory is globally disabled, it blocks new funding
    function test_givenGloballyDisabled_reverts() public {
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
    }

    // draw
    // [X] given another active policy in the same Kernel, exact facility authentication rejects it
    function test_givenActiveSameKernelNonFacility_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                address(config)
            )
        );
        vm.prank(address(config));
        inventory.draw(recipient, 1);
    }
}
