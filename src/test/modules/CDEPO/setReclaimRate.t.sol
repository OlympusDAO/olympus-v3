// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

import {Module} from "src/Kernel.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract SetReclaimRateCDEPOTest is CDEPOTest {
    event ReclaimRateUpdated(uint16 newReclaimRate);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the new reclaim rate is greater than the maximum reclaim rate
    //  [X] it reverts
    // when the new reclaim rate is within bounds
    //  [X] it sets the new reclaim rate
    //  [X] it emits an event

    function test_callerNotPermissioned_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );

        // Call function
        CDEPO.setReclaimRate(100e2);
    }

    function test_aboveMax_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "Greater than 100%")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.setReclaimRate(100e2 + 1);
    }

    function test_success(uint16 newReclaimRate_) public {
        uint16 reclaimRate = uint16(bound(newReclaimRate_, 0, 100e2));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReclaimRateUpdated(reclaimRate);

        // Call function
        vm.prank(godmode);
        CDEPO.setReclaimRate(reclaimRate);

        // Assert
        assertEq(CDEPO.reclaimRate(), reclaimRate, "reclaimRate");
    }
}
