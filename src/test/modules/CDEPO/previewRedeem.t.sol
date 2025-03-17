// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract PreviewRedeemCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than zero
    //  [X] it returns the amount

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        CDEPO.previewRedeem(iReserveToken, 0);
    }

    function test_amountGreaterThanZero(uint256 amount_) public {
        uint256 amount = bound(amount_, 1, type(uint256).max);

        // Call function
        uint256 redeemAmount = CDEPO.previewRedeem(iReserveToken, amount);

        // Assert
        assertEq(redeemAmount, amount, "redeemAmount");
    }
}
