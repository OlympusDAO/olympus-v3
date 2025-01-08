// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {FullMath} from "src/libraries/FullMath.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract PreviewReclaimCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than zero
    //  [X] it returns the amount after applying the burn rate

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        CDEPO.previewReclaim(0);
    }

    function test_amountGreaterThanZero(uint256 amount_) public {
        uint256 amount = bound(amount_, 1, type(uint256).max);

        // Call function
        uint256 reclaimAmount = CDEPO.previewReclaim(amount);

        // Calculate the expected reclaim amount
        uint256 expectedReclaimAmount = FullMath.mulDiv(amount, reclaimRate, 100e2);

        // Assert
        assertEq(reclaimAmount, expectedReclaimAmount, "reclaimAmount");
    }
}
