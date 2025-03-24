// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract SetReclaimRateCDEPOTest is CDEPOTest {
    event ReclaimRateUpdated(address indexed inputToken, uint16 newReclaimRate);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the input token is not supported
    //  [X] it reverts
    // when the new reclaim rate is greater than the maximum reclaim rate
    //  [X] it reverts
    // when the new reclaim rate is within bounds
    //  [X] it sets the new reclaim rate
    //  [X] it emits an event

    function test_callerNotPermissioned_reverts() public {
        // Expect revert
        _expectRevertPolicyNotPermitted(address(this));

        // Call function
        CDEPO.setReclaimRate(cdToken, 100e2);
    }

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        vm.prank(godmode);
        CDEPO.setReclaimRate(IConvertibleDepositERC20(address(iReserveToken)), 100e2);
    }

    function test_aboveMax_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepository.CDEPO_InvalidArgs.selector,
                "Greater than 100%"
            )
        );

        // Call function
        vm.prank(godmode);
        CDEPO.setReclaimRate(cdToken, 100e2 + 1);
    }

    function test_success(uint16 newReclaimRate_) public {
        uint16 reclaimRate = uint16(bound(newReclaimRate_, 0, 100e2));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReclaimRateUpdated(address(cdToken), reclaimRate);

        // Call function
        vm.prank(godmode);
        CDEPO.setReclaimRate(cdToken, reclaimRate);

        // Assert
        assertEq(CDEPO.reclaimRate(address(cdToken)), reclaimRate, "reclaimRate");
    }
}
