// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

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

    function test_success()
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

    function test_whenOracleIsEnabledAndPricesAreFresh_doesNotRecacheConfiguredPrices()
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

        (, uint48 oldCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);

        vm.prank(admin);
        factory.enableOracle(oracle);

        (, uint48 newCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        assertEq(
            newCollateralTimestamp,
            oldCollateralTimestamp,
            "Collateral price should not be re-cached"
        );
        assertEq(newLoanTimestamp, oldLoanTimestamp, "Loan price should not be re-cached");
    }

    function test_whenOracleIsEnabledAndPricesAreStale_recachesConfiguredPrices()
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

        (, uint48 oldCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);

        vm.prank(admin);
        factory.enableOracle(oracle);

        (, uint48 newCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(
            newCollateralTimestamp,
            oldCollateralTimestamp,
            "Collateral price should be re-cached"
        );
        assertGt(newLoanTimestamp, oldLoanTimestamp, "Loan price should be re-cached");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
