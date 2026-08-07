// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

// Contracts
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_SetFacility is YRFTimelockTestBase {
    // setFacility
    // given the caller does not hold the admin role
    //  when setting the facility
    //   then it reverts with ROLES_RequireRole(admin)
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != guardian);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        yrfTimelock.setFacility(address(yieldRepo));
    }

    // setFacility
    // given the facility address is zero
    //  when the admin sets the facility
    //   then it reverts with IYRFTimelock_InvalidAddress("facility")
    function test_givenZeroFacility_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IYRFTimelock.IYRFTimelock_InvalidAddress.selector, "facility")
        );
        yrfTimelock.setFacility(address(0));
    }

    // setFacility
    // given the facility is not an active policy of the timelock's kernel
    //  when the admin sets the facility
    //   then it reverts with IYRFTimelock_InvalidFacility
    function test_givenFacilityNotActivePolicy_reverts() public {
        // A fully valid facility pinned to this timelock, deployed but never activated.
        YieldRepurchaseFacilityV2 inactiveFacility = new YieldRepurchaseFacilityV2(
            kernel,
            address(ohm),
            address(backingOracle),
            address(auctioneer),
            address(yrfTimelock),
            gracePeriod
        );
        vm.label(address(inactiveFacility), "inactiveFacility");

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_InvalidFacility.selector,
                address(inactiveFacility)
            )
        );
        yrfTimelock.setFacility(address(inactiveFacility));
    }

    // setFacility
    // given the candidate is an active policy that does not implement ERC165
    //  when the admin sets the facility
    //   then it reverts with IYRFTimelock_InvalidFacility
    function test_givenFacilityDoesNotImplementErc165_reverts() public {
        MockActivePolicyWithoutErc165 candidate = new MockActivePolicyWithoutErc165(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(candidate));

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_InvalidFacility.selector,
                address(candidate)
            )
        );
        yrfTimelock.setFacility(address(candidate));
    }

    // setFacility
    // given the candidate is an active policy implementing ERC165 but not
    //   IYieldRepurchaseFacilityV2
    //  when the admin sets the facility
    //   then it reverts with IYRFTimelock_InvalidFacility
    function test_givenFacilityDoesNotSupportInterface_reverts() public {
        MockActivePolicyWithoutFacilityInterface candidate = new MockActivePolicyWithoutFacilityInterface(
                kernel
            );
        kernel.executeAction(Actions.ActivatePolicy, address(candidate));

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_InvalidFacility.selector,
                address(candidate)
            )
        );
        yrfTimelock.setFacility(address(candidate));
    }

    // setFacility
    // given the facility does not pin this policy as its timelock
    //  when the admin sets the facility
    //   then it reverts with IYRFTimelock_InvalidFacility
    function test_givenFacilityTimelockMismatch_reverts() public {
        // The harness facility is active and advertises IYieldRepurchaseFacilityV2, but
        // pins the harness.
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_InvalidFacility.selector,
                address(harnessFacility)
            )
        );
        yrfTimelock.setFacility(address(harnessFacility));
    }

    // setFacility
    // given a valid active facility
    //  when the admin sets the facility
    //   then the slot is updated and FacilitySet is emitted
    function test_givenAdminCaller_setsFacilityAndEmitsEvent() public {
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(yrfTimelock));

        vm.expectEmit(true, false, false, true, address(yrfTimelock));
        emit IYRFTimelock.FacilitySet(address(newFacility));
        vm.prank(guardian);
        yrfTimelock.setFacility(address(newFacility));

        assertEq(yrfTimelock.facility(), address(newFacility), "facility slot");
    }

    // setFacility
    // given the timelock policy is disabled
    //  when the admin sets a valid facility
    //   then the slot is updated (wiring is allowed while disabled)
    function test_givenTimelockDisabled_setsFacility() public {
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(yrfTimelock));
        vm.prank(guardian);
        yrfTimelock.disable("");

        vm.prank(guardian);
        yrfTimelock.setFacility(address(newFacility));

        assertEq(yrfTimelock.facility(), address(newFacility), "facility slot");
    }

    // setFacility
    // given a facility is already set
    //  when the admin sets another valid facility
    //   then the slot is replaced and subsequent queues validate against the new facility
    function test_givenFacilityRotated_replacesSlot() public {
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(yrfTimelock));
        // The vault is registered only on the new facility, so the queue below can only
        // pass validation against the rotated slot.
        _registerBackingAsset(newFacility, 0);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                address(sReserve)
            )
        );
        yrfTimelock.queueSetYieldBuybackShare(address(sReserve), 5e17);

        vm.prank(guardian);
        yrfTimelock.setFacility(address(newFacility));

        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);

        assertEq(yrfTimelock.facility(), address(newFacility), "facility slot");
        assertEq(actionId, 1, "action id");
        (address target, , ) = yrfTimelock.getQueuedSubAction(actionId, 0);
        assertEq(target, address(newFacility), "queued target");
    }

    // setFacility
    // given a locked-parameter action is queued against the previous facility
    //  when the facility slot is rotated
    //   then the pending parameter slot is still held by the stale action until cancellation
    function test_givenFacilityRotated_pendingSlotOfOldActionStillHeld() public {
        uint64 staleActionId = _queueSetInitialDiscount(1e16);
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(yrfTimelock));

        vm.prank(guardian);
        yrfTimelock.setFacility(address(newFacility));

        assertEq(
            yrfTimelock.pendingInitialDiscountActionId(),
            staleActionId,
            "pending slot holder"
        );
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_ConflictingActionPending.selector,
                IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
                staleActionId
            )
        );
        yrfTimelock.queueSetInitialDiscount(2e16);
    }
}

/// @notice An activatable policy without an ERC165 surface.
contract MockActivePolicyWithoutErc165 is Policy {
    constructor(Kernel kernel_) Policy(kernel_) {}
}

/// @notice An activatable policy advertising only the bare IERC165 interface.
contract MockActivePolicyWithoutFacilityInterface is Policy {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return interfaceId_ == type(IERC165).interfaceId;
    }
}
