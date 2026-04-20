// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ERC7726OracleFactoryCreateOracleTest is ERC7726OracleFactoryTest {
    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.createOracle(DEFAULT_MAX_AGE, bytes(""));
    }

    function test_whenFactoryIsDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenFactoryIsDisabled
    {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.createOracle(DEFAULT_MAX_AGE, bytes(""));
    }

    function test_whenCreationIsDisabled_reverts() public givenFactoryIsEnabled {
        vm.prank(admin);
        factory.disableCreation();

        vm.expectRevert(IERC7726OracleFactory.ERC7726OracleFactory_CreationDisabled.selector);
        vm.prank(admin);
        factory.createOracle(DEFAULT_MAX_AGE, bytes(""));
    }

    function test_whenOracleAlreadyExistsForMaxAge_reverts() public givenFactoryIsEnabled {
        vm.prank(admin);
        factory.createOracle(DEFAULT_MAX_AGE, bytes(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_OracleAlreadyExists.selector,
                DEFAULT_MAX_AGE
            )
        );
        vm.prank(admin);
        factory.createOracle(DEFAULT_MAX_AGE, bytes(""));
    }

    function test_whenCustomParamsLengthIsInvalid_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidCustomParams.selector,
                1
            )
        );
        vm.prank(admin);
        factory.createOracle(DEFAULT_MAX_AGE, hex"00");
    }

    function test_whenAllConditionsAreMet_createsOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(DEFAULT_MAX_AGE, bytes(""));

        assertNotEq(oracle, address(0), "Oracle address should not be zero");
        assertEq(factory.getOracle(DEFAULT_MAX_AGE), oracle, "Oracle should be mapped for maxAge");
        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
        assertEq(factory.getOracles().length, 1, "Oracle array length should be one");
    }

    function test_whenMaxAgeIsZero_succeeds() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(0, bytes(""));

        assertNotEq(oracle, address(0), "Oracle address should not be zero");
        assertEq(factory.getOracle(0), oracle, "Oracle should be mapped for zero maxAge");
        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    function test_whenOracleIsCreated_itCanQuoteWithConfiguredMaxAge()
        public
        givenFactoryIsEnabled
    {
        vm.prank(admin);
        address oracle = factory.createOracle(DEFAULT_MAX_AGE, bytes(""));

        // Seed cache for both assets for mock PRICE Variant.LAST path.
        priceModule.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        uint256 outAmount = IERC7726Oracle(oracle).getQuote(
            1e18,
            address(baseToken),
            address(quoteToken)
        );

        // 1 BASE = 2 USD, 1 QUOTE = 1 USD => 1 BASE = 2 QUOTE
        assertEq(outAmount, 2e18, "Quote amount should be 2 quote tokens");
    }

    function test_whenOracleIsDisabled_getQuoteReverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.prank(admin);
        factory.disableOracle(oracle);

        vm.expectRevert(IERC7726Oracle.ERC7726Oracle_NotEnabled.selector);
        IERC7726Oracle(oracle).getQuote(1e18, address(baseToken), address(quoteToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
