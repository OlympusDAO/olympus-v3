// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansSyncMintApprovalTest is BurnerLoansSeizureTestBase {
    // syncMintApproval
    // given the caller lacks the burner loans admin and seizer roles
    //  when approval is synchronized
    //   then it reverts
    function test_givenUnauthorizedCaller_reverts_fuzz(address caller_) public {
        vm.assume(caller_ != burnerLoansAdmin);
        vm.assume(caller_ != protocolSeizer);
        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.syncMintApproval();
    }

    // syncMintApproval
    // given the caller has the burner loans seizer role
    //  when approval is synchronized
    //   then it succeeds
    function test_givenCallerHasBurnerLoansSeizerRole_succeeds() public {
        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.MintApprovalSynchronized(burnerLoans.globalDebtCapOhm());

        vm.prank(protocolSeizer);
        uint256 approval = burnerLoans.syncMintApproval();

        assertEq(approval, burnerLoans.globalDebtCapOhm(), "returned approval");
    }

    // syncMintApproval
    // given MINTR approval exceeds the cap less active principal
    //  when approval is synchronized
    //   then excess approval is removed
    function test_givenApprovalAboveActiveCapacity_decreasesToExactCapacity() public {
        _borrow(alice, 2_000e18, 100e9);
        vm.prank(address(minterAdminPolicy));
        minterAdminPolicy.approveMinter(address(burnerLoans), 123e9);

        uint256 expectedApproval = burnerLoans.globalDebtCapOhm() - 100e9;
        vm.prank(burnerLoansAdmin);
        uint256 approval = burnerLoans.syncMintApproval();

        assertEq(approval, expectedApproval, "returned approval");
        assertEq(mintr.mintApproval(address(burnerLoans)), expectedApproval, "stored approval");
    }

    // syncMintApproval
    // given MINTR approval is below the cap less active principal
    //  when approval is synchronized
    //   then approval increases to the exact capacity
    function test_givenApprovalBelowActiveCapacity_increasesToExactCapacity() public {
        _borrow(alice, 2_000e18, 100e9);
        uint256 expectedApproval = burnerLoans.globalDebtCapOhm() - 100e9;
        vm.prank(address(burnerLoans));
        mintr.decreaseMintApproval(address(burnerLoans), 1);

        vm.prank(burnerLoansAdmin);
        uint256 approval = burnerLoans.syncMintApproval();

        assertEq(approval, expectedApproval, "returned approval");
        assertEq(mintr.mintApproval(address(burnerLoans)), expectedApproval, "stored approval");
    }

    // syncMintApproval
    // given MINTR approval already equals the cap less active principal
    //  when approval is synchronized repeatedly
    //   then approval remains unchanged
    function test_givenApprovalAtActiveCapacity_isIdempotent() public {
        uint256 expectedApproval = burnerLoans.globalDebtCapOhm();

        vm.startPrank(burnerLoansAdmin);
        assertEq(burnerLoans.syncMintApproval(), expectedApproval, "first approval");
        assertEq(burnerLoans.syncMintApproval(), expectedApproval, "second approval");
        vm.stopPrank();

        assertEq(mintr.mintApproval(address(burnerLoans)), expectedApproval, "stored approval");
    }

    // syncMintApproval
    // given a fully utilized cap and a defaulted position
    //  when approval is synchronized
    //   then the released capacity can be borrowed again
    function test_givenDefault_releasesCapacityForAnotherBorrower() public {
        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(100e9);

        _makeUnhealthy(alice);
        assertEq(mintr.mintApproval(address(burnerLoans)), 0, "cap fully utilized");

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "default clears active principal");
        assertEq(mintr.mintApproval(address(burnerLoans)), 0, "seizure leaves approval unchanged");

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.MintApprovalSynchronized(100e9);
        vm.prank(burnerLoansAdmin);
        assertEq(burnerLoans.syncMintApproval(), 100e9, "restored approval");

        _configurePrice(address(ohm), 10e18);
        _borrow(bob, 2_000e18, 100e9);

        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "capacity borrowed again");
        assertEq(mintr.mintApproval(address(burnerLoans)), 0, "approval consumed once");
    }
}
