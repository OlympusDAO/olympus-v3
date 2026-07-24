// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

contract BurnerLoansConfigSetMarketFacilityTest is BurnerLoansTest {
    function _createActiveFacility(Kernel kernel_) internal returns (MockBurnerLoansPolicy policy) {
        policy = new MockBurnerLoansPolicy(kernel_);
        vm.prank(admin);
        kernel_.executeAction(Actions.ActivatePolicy, address(policy));
    }

    // setMarketFacility
    // given admin
    //  when setMarketFacility is called
    //   then it moves market to new facility
    function test_givenAdmin_setMarketFacility_movesMarketToNewFacility() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        address newFacility = address(_createActiveFacility(kernel));

        vm.prank(admin);
        burnerLoansConfig.setMarketFacility(marketId, newFacility);

        assertEq(floan.getMarket(marketId).facility, newFacility, "facility");
        assertFalse(burnerLoansConfig.isAssetConfigured(address(usds)), "old facility lookup");
    }

    // setMarketFacility
    // given the market ID does not exist
    //  when admin attempts to set its facility
    //   then FLOAN rejects the invalid market
    function test_givenInvalidMarketId_reverts(uint32 marketId_) public {
        marketId_ = uint32(bound(marketId_, floan.getMarketCount(), type(uint32).max));
        address newFacility = address(_createActiveFacility(kernel));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        burnerLoansConfig.setMarketFacility(marketId_, newFacility);
    }

    // asset configuration getters
    // given no market exists for the bound facility and collateral asset
    //  when either asset configuration getter is called
    //   then it reverts instead of returning a zero-valued configuration
    function test_givenUnconfiguredAsset_gettersRevert(address asset_) public {
        vm.assume(asset_ != address(usds));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoansConfig.getAssetConfig(asset_);

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoansConfig.getAssetFeeConfig(asset_);
    }

    // setMarketFacility
    // given two markets make a facility and asset lookup ambiguous
    //  when one market is moved to another facility
    //   then both facility indexes resolve to their respective market
    function test_givenAmbiguousMarkets_setMarketFacility_resolvesBothIndexes() public {
        _addDefaultUsdsAsset();
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();

        assertTrue(
            burnerLoansConfig.isAssetConfigured(address(usds)),
            "ambiguous pair remains configured"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.marketId(address(usds));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.getAssetConfig(address(usds));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.getAssetFeeConfig(address(usds));

        address newFacility = address(_createActiveFacility(kernel));
        vm.prank(admin);
        burnerLoansConfig.setMarketFacility(secondMarketId, newFacility);

        assertEq(burnerLoansConfig.marketId(address(usds)), 0, "original market id");
        assertEq(floan.getMarket(secondMarketId).facility, newFacility, "moved market facility");
        assertEq(
            abi.encode(burnerLoansConfig.getAssetConfig(address(usds))),
            abi.encode(_defaultAssetConfig(_collateralDecimals())),
            "original asset config"
        );
        assertEq(
            abi.encode(floan.getMarketConfigData(secondMarketId)),
            abi.encode(floan.getMarketConfigData(0)),
            "moved market config data"
        );
    }

    // setMarketFacility
    // given non admin
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenNonAdmin_setMarketFacility_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoansConfig.setMarketFacility(marketId, makeAddr("newFacility"));
    }

    // setMarketFacility
    // given the config policy is disabled
    //  when setMarketFacility is called by admin
    //   then it reverts
    function test_givenConfigDisabled_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        address newFacility = address(_createActiveFacility(kernel));

        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setMarketFacility(marketId, newFacility);
    }

    // setMarketFacility
    // given zero facility
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenZeroFacility_setMarketFacility_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoansConfig.setMarketFacility(marketId, address(0));
    }

    // setMarketFacility
    // given the target facility is a compatible but inactive policy
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenInactiveFacility_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        MockBurnerLoansPolicy inactiveFacility = new MockBurnerLoansPolicy(kernel);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(inactiveFacility)
            )
        );
        burnerLoansConfig.setMarketFacility(marketId, address(inactiveFacility));
    }

    // setMarketFacility
    // given the target is not a compatible policy
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenTargetIsNotPolicy_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(usds)
            )
        );
        burnerLoansConfig.setMarketFacility(marketId, address(usds));
    }

    // setMarketFacility
    // given the target facility is active on a different Kernel
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenFacilityUsesDifferentKernel_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        Kernel otherKernel = new Kernel();
        MockBurnerLoansPolicy foreignFacility = new MockBurnerLoansPolicy(otherKernel);
        otherKernel.executeAction(Actions.ActivatePolicy, address(foreignFacility));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(foreignFacility)
            )
        );
        burnerLoansConfig.setMarketFacility(marketId, address(foreignFacility));
    }
}
