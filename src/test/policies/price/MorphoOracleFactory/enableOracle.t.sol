// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MorphoOracleFactoryEnableOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when caller does not have the admin or oracle_manager role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled givenOracleIsCreated givenOracleIsDisabled {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        vm.assume(caller_ != admin && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.enableOracle(oracle);
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.enableOracle(oracle);
    }

    // when oracle does not exist
    //  [X] it reverts with InvalidOracle

    function test_whenOracleDoesNotExist_reverts() public givenFactoryIsEnabled {
        address nonExistentOracle = makeAddr("NON_EXISTENT_ORACLE");

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidOracle.selector,
                nonExistentOracle
            )
        );

        vm.prank(admin);
        factory.enableOracle(nonExistentOracle);
    }

    // when oracle is already enabled
    //  [X] it reverts with OracleAlreadyEnabled

    function test_whenOracleIsAlreadyEnabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleAlreadyEnabled.selector,
                oracle
            )
        );

        vm.prank(admin);
        factory.enableOracle(oracle);
    }

    // when oracle is disabled
    //  [X] it enables oracle
    //  [X] it emits OracleEnabled event

    function test_whenOracleIsDisabled_enablesOracle()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        vm.expectEmit(true, false, false, false);
        emit IOracleFactory.OracleEnabled(oracle);

        vm.prank(admin);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    // when the caller has the oracle_manager role
    //  [X] it succeeds

    function test_whenCallerHasOracleManagerRole()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        vm.prank(oracleManager);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    // when the caller has the manager role
    //  [X] it reverts

    function test_whenCallerHasManagerRole_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        // Expect revert
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        // Call function
        vm.prank(manager);
        factory.enableOracle(oracle);
    }

    function test_whenOracleIsEnabledAndPricesAreFresh_doesNotRecacheConfiguredPrices(
        uint48 warpDelta_
    ) public givenFactoryIsEnabled givenOracleIsCreated givenOracleIsDisabled {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));

        vm.warp(uint256(oldTimestamp) + uint256(warpDelta));

        vm.prank(admin);
        factory.enableOracle(oracle);

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertEq(newTimestamp, oldTimestamp, "Timestamp should not be re-cached");
    }

    function test_whenOracleIsEnabledAndPricesAreStale_recachesConfiguredPrices(
        uint48 warpDelta_
    ) public givenFactoryIsEnabled givenOracleIsCreated givenOracleIsDisabled {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );

        vm.warp(uint256(oldTimestamp) + uint256(warpDelta));

        vm.prank(admin);
        factory.enableOracle(oracle);

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertGt(newTimestamp, oldTimestamp, "Timestamp should be re-cached");
    }

    function test_whenOracleIsEnabledAndBothCachedTimestampsAreZero_recachesConfiguredPrices()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        // Clear existing direct-pair snapshot so timestamp starts at zero.
        priceCache.clearCachedPrice(address(collateralToken), address(loanToken));

        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        assertEq(oldTimestamp, 0, "Timestamp should start at zero");

        vm.prank(admin);
        factory.enableOracle(oracle);

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertGt(newTimestamp, 0, "Collateral price should be re-cached");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
