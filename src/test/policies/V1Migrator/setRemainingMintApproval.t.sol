// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {V1MigratorTest} from "./V1MigratorTest.sol";
import {IV1Migrator} from "src/policies/interfaces/IV1Migrator.sol";

contract V1MigratorSetRemainingMintApprovalTest is V1MigratorTest {
    event RemainingMintApprovalUpdated(uint256 indexed newApproval, uint256 indexed oldApproval);

    uint256 internal constant NEW_CAP = 20000e9;

    // ========== HELPERS ========== //

    /// @notice Calculate expected OHM v2 amount from OHM v1 amount using gOHM conversion
    /// @param ohmV1Amount_ The OHM v1 amount (9 decimals)
    /// @return ohmV2Amount_ The expected OHM v2 amount (9 decimals)
    function _expectedOHMv2(uint256 ohmV1Amount_) internal view returns (uint256 ohmV2Amount_) {
        uint256 gohmAmount = gOHM.balanceTo(ohmV1Amount_);
        ohmV2Amount_ = gOHM.balanceFrom(gohmAmount);
    }

    // ========== SET REMAINING MINT APPROVAL TESTS ========== //

    //  given contract is disabled
    //   [X] admin can still set remaining mint approval

    function test_givenDisabled_succeeds() public givenContractDisabled {
        // Call function - should succeed even when disabled
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(NEW_CAP);

        // Assert state
        assertEq(
            migrator.remainingMintApproval(),
            NEW_CAP,
            "Remaining mint approval should be updated"
        );
    }

    // given caller does not have admin role
    //  [X] it reverts

    function test_givenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != adminUser);

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(caller_);
        migrator.setRemainingMintApproval(NEW_CAP);
    }

    // given caller has admin role
    //  given new approval is higher than old approval
    //   [X] it increases MINTR approval
    //   [X] it sets the remaining mint approval

    function test_givenAdmin_setsHigherApproval_increasesApproval() public {
        uint256 newCap = INITIAL_CAP + 1000e9;

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit RemainingMintApprovalUpdated(newCap, INITIAL_CAP);

        // Call function
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(newCap);

        // Assert state
        assertEq(
            migrator.remainingMintApproval(),
            newCap,
            "Remaining mint approval should be updated"
        );
    }

    //  given new approval is lower than old approval
    //   [X] it decreases MINTR approval
    //   [X] it sets the remaining mint approval

    function test_givenAdmin_setsLowerApproval_decreasesApproval() public {
        uint256 newCap = INITIAL_CAP - 1000e9;

        vm.expectEmit(true, true, true, true);
        emit RemainingMintApprovalUpdated(newCap, INITIAL_CAP);

        vm.prank(adminUser);
        migrator.setRemainingMintApproval(newCap);

        assertEq(
            migrator.remainingMintApproval(),
            newCap,
            "Remaining mint approval should be updated"
        );
    }

    // given any uint256 approval value
    //  [X] admin can set it as remaining mint approval

    function test_givenAdmin_fuzz(uint256 newCap_) public {
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(newCap_);

        assertEq(
            migrator.remainingMintApproval(),
            newCap_,
            "Remaining mint approval should match input"
        );
    }

    // ========== APPROVAL SYNC TESTS ========== //

    // given the approval is set to 0
    //  [X] migrations are blocked

    function test_givenApprovalSetToZero_migrationsBlocked() public givenAliceApproved {
        // Set approval to 0
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(0);

        // Verify MINTR approval is 0
        assertEq(MINTR.mintApproval(address(migrator)), 0, "MINTR approval should be 0");

        // Expect revert when trying to migrate
        uint256 amount = 100e9;
        uint256 expectedOHMv2 = _expectedOHMv2(amount);
        bytes memory err = abi.encodeWithSelector(
            IV1Migrator.CapExceeded.selector,
            expectedOHMv2,
            0
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(amount, aliceProof, ALICE_ALLOWANCE);
    }

    // given the approval is set to a specific value X
    //  [X] migrations up to X work
    //  [X] migrations exceeding X fail

    function test_givenApprovalSetToX_amountXWorks_amountXPlusOneFails() public givenAliceApproved {
        uint256 X = 200e9;
        uint256 expectedOHMv2 = _expectedOHMv2(X);
        uint256 remaining = X - expectedOHMv2; // Rounding loss leaves some approval

        // Set approval to X
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(X);

        // Alice can migrate exactly X OHM v1 (which mints expectedOHMv2 OHM v2)
        vm.prank(alice);
        migrator.migrate(X, aliceProof, ALICE_ALLOWANCE);

        // MINTR approval is now the remaining amount due to rounding loss
        assertEq(
            MINTR.mintApproval(address(migrator)),
            remaining,
            "MINTR approval should be remaining amount"
        );

        // Trying to migrate more should fail
        // Note: Using a larger amount since small values may round to 0
        uint256 extraAmount = 100e9;
        uint256 extraExpected = _expectedOHMv2(extraAmount);

        bytes memory err = abi.encodeWithSelector(
            IV1Migrator.CapExceeded.selector,
            extraExpected,
            remaining
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(extraAmount, aliceProof, ALICE_ALLOWANCE);
    }

    // given the approval is set multiple times
    //  [X] remainingMintApproval always reflects current MINTR approval

    function test_givenMultipleApprovalChanges_remainingMintApprovalReflectsMINTR() public {
        // Initially, remainingMintApproval should equal INITIAL_CAP
        assertEq(migrator.remainingMintApproval(), INITIAL_CAP, "Initial approval should match");
        assertEq(MINTR.mintApproval(address(migrator)), INITIAL_CAP, "MINTR should match");

        // Set approval to a lower value
        uint256 lowerCap = INITIAL_CAP - 500e9;
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(lowerCap);
        assertEq(migrator.remainingMintApproval(), lowerCap, "Approval should be lower");
        assertEq(MINTR.mintApproval(address(migrator)), lowerCap, "MINTR should match");

        // Set approval to a higher value
        uint256 higherCap = lowerCap + 1000e9;
        vm.prank(adminUser);
        migrator.setRemainingMintApproval(higherCap);
        assertEq(migrator.remainingMintApproval(), higherCap, "Approval should be higher");
        assertEq(MINTR.mintApproval(address(migrator)), higherCap, "MINTR should match");
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
