// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract YieldDepositFacilitySplitTest is YieldDepositFacilityTest {
    uint256 internal constant DEPOSIT_AMOUNT = 9e18;
    uint256 internal constant YIELD_AMOUNT = 1e18;
    uint256 internal constant POSITION_ID = 0;

    uint256 internal _lastYieldClaim;

    function _split(uint256 amount_) internal returns (uint256) {
        vm.prank(recipient);
        return yieldDepositFacility.split(POSITION_ID, amount_, recipientTwo, false);
    }

    // ===== TESTS ===== //

    // given the position was created by the ConvertibleDepositFacility
    //  [X] it reverts when splitting via YieldDepositFacility
    function test_whenPositionFromCDF_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Create CDF position for the recipient
        uint256 cdfPositionId = _createConvertibleDepositPosition(recipient, 1e18, 2e18);

        // Expect revert when attempting to split via YDF
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositPositionManager.DEPOS_NotOperator.selector,
                cdfPositionId
            )
        );

        vm.prank(recipient);
        yieldDepositFacility.split(cdfPositionId, 5e17, recipientTwo, false);
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_whenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        vm.prank(recipient);
        yieldDepositFacility.split(POSITION_ID, 1e18, recipientTwo, false);
    }

    // given the position does not exist
    //  [X] it reverts

    function test_whenPositionDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositPositionManager.DEPOS_InvalidPositionId.selector,
                POSITION_ID
            )
        );

        vm.prank(recipient);
        yieldDepositFacility.split(POSITION_ID, 1e18, recipientTwo, false);
    }

    // given the caller is not the owner of the position
    //  [X] it reverts

    function test_whenNotOwner_reverts(
        address caller_
    ) public givenLocallyActive givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT) {
        vm.assume(caller_ != recipient);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_NotOwner.selector, POSITION_ID)
        );

        vm.prank(caller_);
        yieldDepositFacility.split(POSITION_ID, 1e18, recipientTwo, false);
    }

    // given yield has not been claimed
    //  [X] it creates a new position with the specified amount
    //  [X] it updates the remaining deposit of the original position
    //  [X] it sets the timestamp for the initial value of the last yield claim

    function test_givenYieldNotClaimed(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, YIELD_AMOUNT)
        givenYieldFee(1000) // 10%
        givenWarpForward(1) // Requires gap between snapshots
    {
        amount_ = bound(amount_, 1, _previousDepositActualAmount);

        // Obtain the value for the last yield claim (the creation timestamp)
        _lastYieldClaim = yieldDepositFacility.positionLastYieldClaimTimestamp(POSITION_ID);

        // Warp
        vm.warp(block.timestamp + 1 days);

        // Call function
        uint256 newPositionId = _split(amount_);

        // Check the new position was created
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).remainingDeposit,
            amount_,
            "New position amount mismatch"
        );
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).owner,
            recipientTwo,
            "New position owner mismatch"
        );

        // Check the original position was updated
        assertEq(
            convertibleDepositPositions.getPosition(POSITION_ID).remainingDeposit,
            _previousDepositActualAmount - amount_,
            "Original position amount mismatch"
        );

        // Check the last yield claim timestamp was set correctly
        assertEq(
            yieldDepositFacility.positionLastYieldClaimTimestamp(POSITION_ID),
            _lastYieldClaim,
            "Position one last yield claim timestamp mismatch"
        );
        assertEq(
            yieldDepositFacility.positionLastYieldClaimTimestamp(newPositionId),
            _lastYieldClaim,
            "Position two last yield claim timestamp mismatch"
        );
    }

    // [X] it creates a new position with the specified amount
    // [X] it updates the remaining deposit of the original position
    // [X] it sets the timestamp for the last time yield was claimed

    function test_givenYieldClaimed(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, YIELD_AMOUNT)
        givenYieldFee(1000) // 10%
        givenWarpForward(1) // Requires gap between snapshots
        givenHarvest(recipient, POSITION_ID)
        givenWarpForward(1 days)
        givenVaultAccruesYield(iVault, YIELD_AMOUNT)
    {
        amount_ = bound(amount_, 1, _previousDepositActualAmount);

        // Obtain the value for the last yield claim
        _lastYieldClaim = yieldDepositFacility.positionLastYieldClaimTimestamp(POSITION_ID);

        // Warp
        vm.warp(block.timestamp + 1 days);

        // Call function
        uint256 newPositionId = _split(amount_);

        // Check the new position was created
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).remainingDeposit,
            amount_,
            "New position amount mismatch"
        );
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).owner,
            recipientTwo,
            "New position owner mismatch"
        );

        // Check the original position was updated
        assertEq(
            convertibleDepositPositions.getPosition(POSITION_ID).remainingDeposit,
            _previousDepositActualAmount - amount_,
            "Original position amount mismatch"
        );

        // Check the last yield claim timestamp was set correctly
        assertEq(
            yieldDepositFacility.positionLastYieldClaimTimestamp(POSITION_ID),
            _lastYieldClaim,
            "Position one last yield claim timestamp mismatch"
        );
        assertEq(
            yieldDepositFacility.positionLastYieldClaimTimestamp(newPositionId),
            _lastYieldClaim,
            "Position two last yield claim timestamp mismatch"
        );
    }
}
