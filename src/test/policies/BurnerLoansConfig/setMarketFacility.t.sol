// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetMarketFacilityTest is BurnerLoansTest {
    // setMarketFacility
    // given admin
    //  when setMarketFacility is called
    //   then it moves market to new facility
    function test_givenAdmin_setMarketFacility_movesMarketToNewFacility() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(burnerLoans), address(usds));
        address newFacility = makeAddr("newFacility");

        vm.prank(admin);
        burnerLoansConfig.setMarketFacility(marketId, newFacility);

        assertEq(floan.getMarket(marketId).facility, newFacility, "facility");
        assertFalse(
            burnerLoansConfig.isAssetConfigured(address(burnerLoans), address(usds)),
            "old facility lookup"
        );
        assertTrue(
            burnerLoansConfig.isAssetConfigured(newFacility, address(usds)),
            "new facility lookup"
        );
    }

    // setMarketFacility
    // given non admin
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenNonAdmin_setMarketFacility_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(burnerLoans), address(usds));

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoansConfig.setMarketFacility(marketId, makeAddr("newFacility"));
    }

    // setMarketFacility
    // given zero facility
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenZeroFacility_setMarketFacility_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(burnerLoans), address(usds));

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoansConfig.setMarketFacility(marketId, address(0));
    }
}
