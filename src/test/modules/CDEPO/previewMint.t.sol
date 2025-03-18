// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract PreviewMintCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than zero
    //  [X] it returns the same amount

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.previewMint(iReserveTokenTwo, 10e18);
    }

    function test_zeroAmount_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        CDEPO.previewMint(iReserveToken, 0);
    }

    function test_success(uint256 amount_) public {
        uint256 amount = bound(amount_, 1, type(uint256).max);

        // Call function
        uint256 amountOut = CDEPO.previewMint(iReserveToken, amount);

        // Assert
        assertEq(amountOut, amount, "amountOut");
    }
}
