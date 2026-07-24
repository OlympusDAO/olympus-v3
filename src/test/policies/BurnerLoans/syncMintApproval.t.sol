// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansSyncMintApprovalTest is BurnerLoansSeizureTestBase {
    // syncMintApproval
    // given the caller lacks the burner loans admin role
    //  when approval is synchronized
    //   then it reverts
    function test_givenCallerWithoutBurnerLoansAdminRole_reverts_fuzz(address caller_) public {
        vm.assume(caller_ != burnerLoansAdmin);
        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        burnerLoans.syncMintApproval();
    }

    // syncMintApproval
    // given MINTR approval exceeds the cap less active principal
    //  when approval is synchronized
    //   then excess approval is removed
    function test_givenApprovalAboveActiveCapacity_decreasesToExactCapacity() public {
        vm.prank(address(minterAdminPolicy));
        minterAdminPolicy.approveMinter(address(burnerLoans), 123e9);

        uint256 expectedApproval = burnerLoans.globalDebtCapOhm();
        vm.prank(burnerLoansAdmin);
        uint256 approval = burnerLoans.syncMintApproval();

        assertEq(approval, expectedApproval, "returned approval");
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
