// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Contracts
import {Actions, Module, Permissions} from "src/Kernel.sol";
import {ModuleTestFixture} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketManagerTest is FLOANTest {
    uint32 internal _marketId;

    modifier givenMarketExists(address manager_, address facility_) {
        _marketId = _createMarket(manager_, facility_, collateralToken, debtToken, 1_000e9);
        _;
    }

    // setMarketManager
    // given caller without kernel permission
    //  when setMarketManager is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts(
        address caller_
    ) public givenMarketExists(manager, facility) {
        _expectKernelPermissionRevert(caller_);
        floan.setMarketManager(_marketId, otherManager);
    }

    // setMarketManager
    // given the current facility lacks Kernel permission
    //  when setMarketManager is called
    //   then it reverts at the Kernel boundary
    function test_givenCurrentFacilityWithoutKernelPermission_reverts() public {
        address facilityWithoutPermission = makeAddr("facilityWithoutPermission");
        uint32 marketId = _createMarket(
            manager,
            facilityWithoutPermission,
            collateralToken,
            debtToken,
            1_000e9
        );

        vm.prank(facilityWithoutPermission);
        vm.expectRevert(
            abi.encodeWithSelector(
                Module.Module_PolicyNotPermitted.selector,
                facilityWithoutPermission
            )
        );
        floan.setMarketManager(marketId, otherManager);
    }

    // setMarketManager
    // given the zero address caller
    //  when setMarketManager is called
    //   then it reverts at the Kernel boundary
    function test_givenZeroAddressCaller_reverts() public givenMarketExists(manager, facility) {
        vm.prank(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(0))
        );
        floan.setMarketManager(_marketId, otherManager);
    }

    // setMarketManager
    // given invalid market ID
    //  when setMarketManager is called
    //   then it reverts
    function test_givenInvalidMarket_reverts(uint32 marketId_) public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketManager(marketId_, otherManager);
    }

    // setMarketManager
    // given a Kernel-permissioned caller that is neither the market manager nor facility
    //  when setMarketManager is called
    //   then it reverts
    function test_givenCallerIsNeitherMarketManagerNorFacility_reverts(
        bytes32 salt_
    ) public givenMarketExists(manager, facility) {
        Permissions[] memory requests = new Permissions[](1);
        requests[0] = Permissions({
            keycode: floan.KEYCODE(),
            funcSelector: IFLOANv1.setMarketManager.selector
        });
        address caller = address(new ModuleTestFixture{salt: salt_}(kernel, floan, requests));
        vm.assume(caller != manager);
        vm.assume(caller != facility);
        kernel.executeAction(Actions.ActivatePolicy, caller);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, _marketId, caller)
        );
        floan.setMarketManager(_marketId, otherManager);
    }

    // setMarketManager
    // given the caller services a different market
    //  when setMarketManager is called
    //   then it reverts
    function test_givenCallerServicesDifferentMarket_reverts()
        public
        givenMarketExists(manager, facility)
    {
        uint32 otherMarketId = _createMarket(
            manager,
            otherFacility,
            otherCollateralToken,
            debtToken,
            1_000e9
        );

        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, _marketId, otherFacility)
        );
        floan.setMarketManager(_marketId, otherManager);

        assertEq(floan.getMarket(_marketId).manager, manager, "target market manager");
        assertEq(floan.getMarket(otherMarketId).manager, manager, "serviced market manager");
    }

    // setMarketManager
    // given the current manager
    //  when the new manager is zero
    //   then it reverts
    function test_givenCurrentManager_whenNewManagerIsZero_reverts()
        public
        givenMarketExists(manager, facility)
    {
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketManager(_marketId, address(0));
    }

    // setMarketManager
    // given the current facility
    //  when the new manager is zero
    //   then it reverts
    function test_givenCurrentFacility_whenNewManagerIsZero_reverts()
        public
        givenMarketExists(manager, facility)
    {
        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketManager(_marketId, address(0));
    }

    // setMarketManager
    // given the current manager
    //  when setMarketManager is called
    //   then it transfers configuration authority
    function test_givenCurrentManager() public givenMarketExists(manager, facility) {
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketManagerSet(_marketId, manager, otherManager);
        vm.prank(manager);
        floan.setMarketManager(_marketId, otherManager);

        assertEq(floan.getMarket(_marketId).manager, otherManager, "market manager");
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, _marketId, manager)
        );
        floan.setMarketManager(_marketId, manager);
        vm.prank(otherManager);
        floan.setMarketManager(_marketId, manager);
        assertEq(floan.getMarket(_marketId).manager, manager, "restored market manager");
    }

    // setMarketManager
    // given the current facility
    //  when setMarketManager is called
    //   then it transfers configuration authority
    function test_givenCurrentFacility() public givenMarketExists(manager, facility) {
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketManagerSet(_marketId, manager, otherManager);
        vm.prank(facility);
        floan.setMarketManager(_marketId, otherManager);

        assertEq(floan.getMarket(_marketId).manager, otherManager, "market manager");
    }

    // setMarketManager
    // given the current manager is also the current facility
    //  when setMarketManager is called
    //   then it transfers configuration authority
    function test_givenCurrentManagerIsCurrentFacility()
        public
        givenMarketExists(manager, manager)
    {
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketManagerSet(_marketId, manager, otherManager);
        vm.prank(manager);
        floan.setMarketManager(_marketId, otherManager);

        assertEq(floan.getMarket(_marketId).manager, otherManager, "market manager");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
