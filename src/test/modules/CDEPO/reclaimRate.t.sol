// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract ReclaimRateCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // [X] it returns the reclaim rate for the input token

    function test_notSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        CDEPO.reclaimRate(address(iReserveToken));
    }

    function test_supported() public {
        assertEq(CDEPO.reclaimRate(address(cdToken)), reclaimRate, "reclaimRate");
    }
}
