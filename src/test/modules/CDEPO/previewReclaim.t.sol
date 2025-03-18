// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {FullMath} from "src/libraries/FullMath.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract PreviewReclaimCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the reclaimed amount is zero
    //  [X] it reverts
    // when the amount is greater than zero
    //  [X] it returns the amount after applying the burn rate

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.previewReclaim(iReserveTokenTwo, 10e18);
    }

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        CDEPO.previewReclaim(iReserveToken, 0);
    }

    function test_reclaimedAmountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepository.CDEPO_InvalidArgs.selector,
                "reclaimed amount"
            )
        );

        // Call function
        CDEPO.previewReclaim(iReserveToken, 1);
    }

    function test_amountGreaterThanZero(uint256 amount_) public {
        uint256 amount = bound(amount_, 2, type(uint256).max);

        // Call function
        uint256 reclaimAmount = CDEPO.previewReclaim(iReserveToken, amount);

        // Calculate the expected reclaim amount
        uint256 expectedReclaimAmount = FullMath.mulDiv(amount, reclaimRate, 100e2);

        // Assert
        assertEq(reclaimAmount, expectedReclaimAmount, "reclaimAmount");
    }
}
