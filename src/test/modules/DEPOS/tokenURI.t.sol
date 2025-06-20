// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {String} from "src/libraries/String.sol";

contract TokenURIDEPOSTest is DEPOSTest {
    uint48 public constant SAMPLE_CONVERSION_EXPIRY_DATE = 1737014593 + 1 days;

    // given the renderer is not set
    //  [X] it returns an empty string

    function test_rendererNotSet()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            false
        )
    {
        // Set the token renderer to zero address
        vm.prank(godmode);
        DEPOS.setTokenRenderer(address(0));

        // Check that the token URI is empty
        assertEq(DEPOS.tokenURI(0), "");
    }

    // when the position does not exist
    //  [X] it reverts

    function test_positionDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidPositionId.selector, 1)
        );

        DEPOS.tokenURI(1);
    }

    // [X] it returns the token URI from the renderer

    function test_success()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            false
        )
    {
        // Call function
        string memory tokenURI = DEPOS.tokenURI(0);

        // Check that the string begins with `data:application/json;base64,`
        assertEq(String.substring(tokenURI, 0, 29), "data:application/json;base64,", "prefix");
    }
}
