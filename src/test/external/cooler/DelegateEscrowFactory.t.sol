// SPDX-License-Identifier: MAGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";

import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";
import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";

contract DelegateEscrowFactoryTestBase is Test {
    address public immutable ALICE = makeAddr("ALICE");
    address public immutable BOB = makeAddr("BOB");
    address public immutable CHARLIE = makeAddr("CHARLIE");

    MockGohm internal gohm;
    DelegateEscrowFactory escrowFactory;

    event DelegateEscrowCreated(
        address indexed caller,
        address indexed delegate,
        address indexed escrow
    );

    event Delegate(
        address indexed escrow,
        address indexed caller,
        address indexed onBehalfOf,
        int256 delegationAmountDelta
    );

    function setUp() public virtual {
        gohm = new MockGohm("gOHM", "gOHM", 18);
        escrowFactory = new DelegateEscrowFactory(address(gohm));
    }
}

contract DelegateEscrowFactoryTest is DelegateEscrowFactoryTestBase {
    function test_create_new() public {
        vm.startPrank(ALICE);
        address expectedEscrow = 0x8d2C17FAd02B7bb64139109c6533b7C2b9CADb81;
        vm.assertEq(address(escrowFactory.escrowFor(BOB)), address(0));
        vm.assertEq(escrowFactory.created(expectedEscrow), false);

        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(ALICE, BOB, expectedEscrow);
        DelegateEscrow escrow = escrowFactory.create(BOB);
        assertEq(address(escrow), expectedEscrow);

        vm.assertEq(address(escrowFactory.escrowFor(BOB)), expectedEscrow);
        vm.assertEq(escrowFactory.created(expectedEscrow), true);
    }

    function test_create_existing() public {
        vm.startPrank(ALICE);
        address expectedEscrow = 0x8d2C17FAd02B7bb64139109c6533b7C2b9CADb81;
        DelegateEscrow escrow = escrowFactory.create(BOB);
        assertEq(address(escrow), expectedEscrow);
        escrow = escrowFactory.create(BOB);
        assertEq(address(escrow), expectedEscrow);

        vm.assertEq(address(escrowFactory.escrowFor(BOB)), expectedEscrow);
        vm.assertEq(escrowFactory.created(expectedEscrow), true);
    }

    function test_access_logDelegate() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(DelegateEscrowFactory.NotFromFactory.selector));
        escrowFactory.logDelegate(ALICE, ALICE, 123);
    }

    function test_logDelegate_failFactory() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(DelegateEscrowFactory.NotFromFactory.selector));
        escrowFactory.logDelegate(ALICE, ALICE, 123);
    }

    function test_logDelegate_success() public {
        vm.startPrank(ALICE);
        DelegateEscrow escrow = escrowFactory.create(ALICE);
        vm.startPrank(address(escrow));
        vm.expectEmit(address(escrowFactory));
        emit Delegate(address(escrow), ALICE, BOB, 123);
        escrowFactory.logDelegate(ALICE, BOB, 123);
    }
}

contract DelegateEscrowImplTest is DelegateEscrowFactoryTestBase {
    DelegateEscrow internal aliceEscrow;

    address internal immutable CALLER1 = makeAddr("CALLER1");
    address internal immutable CALLER2 = makeAddr("CALLER2");

    function delegate(
        address caller,
        uint256 amount,
        address onBehalfOf
    ) internal returns (uint256) {
        vm.startPrank(caller);
        deal(address(gohm), caller, amount);
        gohm.approve(address(aliceEscrow), amount);

        vm.expectEmit(address(escrowFactory));
        emit Delegate(address(aliceEscrow), caller, onBehalfOf, int256(amount));
        return aliceEscrow.delegate(onBehalfOf, amount);
    }

    function rescind(
        address caller,
        address onBehalfOf,
        uint256 amount
    ) internal returns (uint256 remaining) {
        vm.startPrank(caller);
        uint256 balBefore = gohm.balanceOf(caller);
        vm.expectEmit(address(escrowFactory));
        emit Delegate(address(aliceEscrow), caller, onBehalfOf, -int256(amount));
        remaining = aliceEscrow.rescindDelegation(onBehalfOf, amount);
        assertEq(gohm.balanceOf(caller) - balBefore, amount);
        return remaining;
    }

    function setUp() public override {
        DelegateEscrowFactoryTestBase.setUp();
        aliceEscrow = escrowFactory.create(ALICE);
    }

    function test_constructor() public view {
        assertEq(IVotes(address(gohm)).delegates(address(aliceEscrow)), ALICE);
        assertEq(aliceEscrow.delegateAccount(), ALICE);
        assertEq(address(aliceEscrow.factory()), address(escrowFactory));
    }

    function test_delegate() public {
        assertEq(delegate(CALLER1, 10e18, ALICE), 10e18);
        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 10e18);
        assertEq(delegate(CALLER1, 33e18, ALICE), 43e18);
        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 43e18);
        assertEq(delegate(CALLER1, 10e18, BOB), 10e18);
        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 43e18);
        assertEq(aliceEscrow.delegations(CALLER1, BOB), 10e18);

        assertEq(delegate(CALLER2, 10e18, ALICE), 10e18);
        assertEq(delegate(CALLER2, 33e18, ALICE), 43e18);
        assertEq(delegate(CALLER2, 10e18, BOB), 10e18);
        assertEq(aliceEscrow.delegations(CALLER2, ALICE), 43e18);
        assertEq(aliceEscrow.delegations(CALLER2, BOB), 10e18);

        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 43e18);
        assertEq(aliceEscrow.delegations(CALLER1, BOB), 10e18);
    }

    function test_rescindDelegation() public {
        delegate(CALLER1, 43e18, ALICE);
        delegate(CALLER1, 10e18, BOB);
        delegate(CALLER2, 43e18, ALICE);
        delegate(CALLER2, 10e18, BOB);

        vm.startPrank(CALLER1);
        vm.expectRevert(abi.encodeWithSelector(DelegateEscrow.ExceededDelegationBalance.selector));
        aliceEscrow.rescindDelegation(ALICE, 43e18 + 1);

        assertEq(rescind(CALLER1, ALICE, 5e18), 38e18);
        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 38e18);
        assertEq(rescind(CALLER1, ALICE, 5e18), 33e18);
        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 33e18);
        assertEq(rescind(CALLER1, BOB, 5e18), 5e18);
        assertEq(aliceEscrow.delegations(CALLER1, BOB), 5e18);

        assertEq(rescind(CALLER2, ALICE, 5e18), 38e18);
        assertEq(aliceEscrow.delegations(CALLER2, ALICE), 38e18);
        assertEq(rescind(CALLER2, ALICE, 5e18), 33e18);
        assertEq(aliceEscrow.delegations(CALLER2, ALICE), 33e18);
        assertEq(rescind(CALLER2, BOB, 5e18), 5e18);
        assertEq(aliceEscrow.delegations(CALLER2, BOB), 5e18);

        assertEq(aliceEscrow.delegations(CALLER1, ALICE), 33e18);
        assertEq(aliceEscrow.delegations(CALLER1, BOB), 5e18);
    }
}
