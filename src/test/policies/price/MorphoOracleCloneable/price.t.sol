// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Actions} from "src/Kernel.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

contract MorphoOracleCloneablePriceTest is MorphoOracleCloneableTest {
    // The SwapMock contract is used as inspiration for how to validate that the
    // scale and value of the price are correct.
    // See: https://github.com/morpho-org/morpho-blue-snippets/blob/cf9431f320a61b1344a9936baeb71719c2e44c41/src/morpho-blue/mocks/SwapMock.sol

    // ========== TESTS ========== //

    // price
    // when factory is disabled
    //  [X] it reverts with MorphoOracle_NotEnabled

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IMorphoOracle.MorphoOracle_NotEnabled.selector);

        oracle.price();
    }

    // when oracle is not enabled
    //  [X] it reverts with MorphoOracle_NotEnabled

    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(IMorphoOracle.MorphoOracle_NotEnabled.selector);

        oracle.price();
    }

    // when collateral token price is zero
    //  [X] it reverts with PRICE_PriceZero

    function test_whenCollateralTokenPriceIsZero_reverts() public {
        // Set collateral token price to zero
        _setPRICEPrices(address(collateralToken), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(collateralToken))
        );

        oracle.price();
    }

    // when loan token price is zero
    //  [X] it reverts with PRICE_PriceZero

    function test_whenLoanTokenPriceIsZero_reverts() public {
        // Set loan token price to zero
        _setPRICEPrices(address(loanToken), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(loanToken))
        );

        oracle.price();
    }

    // [X] it calculates price correctly
    // [X] it returns price with correct scale (36 decimals + 18 - 18)

    function test_success() public view {
        // oracle.price() returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e36 (36 + 18 - 18)
        // the price is 2e18 * 1e36 / 1e18 = 2e36
        uint256 expectedPrice = 2e36;
        uint256 actualPrice = oracle.price();

        assertEq(actualPrice, expectedPrice, "Price should be calculated correctly");

        // Calculate the loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e36 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * actualPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly"
        );

        // Calculate the collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e36 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / actualPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly"
        );
    }

    // when the collateral token decimals are smaller than the loan token decimals
    //  [X] it calculates price correctly

    function test_whenCollateralTokenDecimalsAreSmallerThanLoanTokenDecimals() public {
        // Create a new collateral token with 9 decimals
        MockERC20 newCollateralToken = new MockERC20("New Collateral Token", "NEWCOL", 9);

        // Set collateral token price to 2e18
        _setPRICEPrices(address(newCollateralToken), 2e18);

        // Create the oracle with the new collateral token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(newCollateralToken),
            address(loanToken),
            bytes("")
        );

        // oracle.price() returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals, but native is 9 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e45 (36 + loanDecimals - collateralDecimals = 36 + 18 - 9)
        // the price is 2e18 * 1e45 / 1e18 = 2e45
        uint256 expectedPrice = 2e45;
        uint256 actualPrice = IMorphoOracle(newOracle).price();

        assertEq(actualPrice, expectedPrice, "Price should be calculated correctly");

        // Calculate the loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e9 * 2e45 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e9 * actualPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly"
        );

        // Calculate the collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e45 = 0.5e9
        uint256 expectedCollateralTokensPerLoanToken = 0.5e9;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / actualPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly"
        );
    }

    // when the loan token decimals are smaller than the collateral token decimals
    //  [X] it calculates price correctly

    function test_whenLoanTokenDecimalsAreSmallerThanCollateralTokenDecimals() public {
        // Create a new loan token with 9 decimals
        MockERC20 newLoanToken = new MockERC20("New Loan Token", "NEWLOAN", 9);

        // Set loan token price to 1e18
        _setPRICEPrices(address(newLoanToken), 1e18);

        // Create the oracle with the new loan token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(collateralToken),
            address(newLoanToken),
            bytes("")
        );

        // oracle.price() returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals, but native is 9 decimals)
        // scaleFactor = 1e27 (36 + 9 - 18)
        // the price is 2e18 * 1e27 / 2e18 = 2e27
        uint256 expectedPrice = 2e27;
        uint256 actualPrice = IMorphoOracle(newOracle).price();

        assertEq(actualPrice, expectedPrice, "Price should be calculated correctly");

        // Calculate the loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e27 / 1e36 = 2e9
        uint256 expectedLoanTokensPerCollateralToken = 2e9;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * actualPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly"
        );

        // Calculate the collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e9 * 1e36 / 2e27 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e9 * 1e36) / actualPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly"
        );
    }

    // when collateral price changes
    //  [X] it reflects new price

    function test_whenCollateralPriceChanges() public {
        // Initial price: 2e18 / 1e18 * 1e36 = 2e36
        uint256 initialPrice = oracle.price();
        assertEq(initialPrice, 2e36, "Initial price should be 2e36");

        // Change collateral price to 3e18
        _setPRICEPrices(address(collateralToken), 3e18);

        // New price: 3e18 / 1e18 * 1e36 = 3e36
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 3e36, "Price should reflect new collateral price");
    }

    // when loan price changes
    //  [X] it reflects new price

    function test_whenLoanPriceChanges() public {
        // Initial price: 2e18 / 1e18 * 1e36 = 2e36
        uint256 initialPrice = oracle.price();
        assertEq(initialPrice, 2e36, "Initial price should be 2e36");

        // Change loan price to 2e18
        _setPRICEPrices(address(loanToken), 2e18);

        // New price: 2e18 / 2e18 * 1e36 = 1e36
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 1e36, "Price should reflect new loan price");
    }

    // when PRICE module is updated in factory
    //  [X] it uses new PRICE module

    function test_whenPRICEModuleIsUpdatedInFactory() public {
        // Deploy new PRICE module
        MockPrice newPriceModule = new MockPrice(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);

        // Upgrade PRICE module (replace existing one)
        kernel.executeAction(Actions.UpgradeModule, address(newPriceModule));

        // Set different prices in new PRICE module
        newPriceModule.setPrice(address(collateralToken), 4e18);
        newPriceModule.setPrice(address(loanToken), 1e18);

        // Update factory dependencies to use new PRICE module
        factory.configureDependencies();

        // Oracle should now use the new PRICE module
        // Expected: 4e18 / 1e18 * 1e36 = 4e36
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 4e36, "Oracle should use new PRICE module");
    }

    // when PRICE module decimals are changed
    //  [X] it calculates price correctly

    function test_whenPRICEDecimalsAreChanged() public {
        // Initial setup: PRICE_DECIMALS = 18
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e36 (36 + 18 - 18)
        // Expected price: 2e18 * 1e36 / 1e18 = 2e36
        uint256 initialPrice = oracle.price();
        assertEq(initialPrice, 2e36, "Initial price should be 2e36");

        // Change PRICE module decimals from 18 to 9
        priceModule.setPriceDecimals(9);

        // Update prices to maintain same USD values with new decimals
        // 2e18 (18 decimals) -> 2e9 (9 decimals) for $2
        // 1e18 (18 decimals) -> 1e9 (9 decimals) for $1
        _setPRICEPrices(address(collateralToken), 2e9);
        _setPRICEPrices(address(loanToken), 1e9);

        // Update factory dependencies to refresh PRICE_DECIMALS
        factory.configureDependencies();

        // Verify factory has updated PRICE_DECIMALS
        assertEq(factory.PRICE_DECIMALS(), 9, "Factory PRICE_DECIMALS should be updated to 9");

        // Oracle should still return correct price
        // The scaleFactor is immutable and based on token decimals (36 + 18 - 18 = 36)
        // collateralPriceUsd = 2e9 (2 USD, 9 decimals)
        // loanPriceUsd = 1e9 (1 USD, 9 decimals)
        // scaleFactor = 1e36 (unchanged, based on token decimals)
        // Price calculation: 1e36 * 2e9 / 1e9 = 2e36
        // The result is still 2e36 because the ratio is preserved
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 2e36, "Price should remain 2e36 after PRICE decimals change");

        // Verify the calculation is still accurate by checking loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e36 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * newPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly after PRICE decimals change"
        );

        // Verify collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e36 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / newPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly after PRICE decimals change"
        );
    }

    // given the collateral token decimals are smaller than the loan token decimals
    //  when the PRICE module decimals are changed
    //   [X] it calculates price correctly

    function test_whenCollateralTokenDecimalsAreSmallerThanLoanTokenDecimals_whenPRICEDecimalsAreChanged()
        public
    {
        // Create a new collateral token with 9 decimals
        MockERC20 newCollateralToken = new MockERC20("New Collateral Token", "NEWCOL", 9);

        // Set collateral token price to 2e18
        _setPRICEPrices(address(newCollateralToken), 2e18);

        // Create the oracle with the new collateral token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(newCollateralToken),
            address(loanToken),
            bytes("")
        );

        // Initial setup: PRICE_DECIMALS = 18
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e45 (36 + 18 - 9)
        // Expected price: 1e45 * 2e18 / 1e18 = 2e45
        uint256 expectedPrice = 2e45;
        uint256 initialPrice = IMorphoOracle(newOracle).price();
        assertEq(initialPrice, expectedPrice, "Initial price should be 2e45");

        // Change PRICE module decimals from 18 to 9
        priceModule.setPriceDecimals(9);

        // Update prices to maintain same USD values with new decimals
        // 2e18 (18 decimals) -> 2e9 (9 decimals) for $2
        // 1e18 (18 decimals) -> 1e9 (9 decimals) for $1
        _setPRICEPrices(address(newCollateralToken), 2e9);
        _setPRICEPrices(address(loanToken), 1e9);

        // Update factory dependencies to refresh PRICE_DECIMALS
        factory.configureDependencies();

        // Verify factory has updated PRICE_DECIMALS
        assertEq(factory.PRICE_DECIMALS(), 9, "Factory PRICE_DECIMALS should be updated to 9");

        // Oracle should still return correct price
        // The scaleFactor is immutable and based on token decimals (36 + 18 - 9 = 45)
        // collateralPriceUsd = 2e9 (2 USD, 9 decimals)
        // loanPriceUsd = 1e9 (1 USD, 9 decimals)
        // scaleFactor = 1e45 (unchanged, based on token decimals)
        // Price calculation: 1e45 * 2e9 / 1e9 = 2e45
        // The result is still 2e45 because the ratio is preserved
        uint256 newPrice = IMorphoOracle(newOracle).price();
        assertEq(newPrice, expectedPrice, "Price should remain 2e45 after PRICE decimals change");

        // Verify the calculation is still accurate by checking loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e9 * 2e45 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e9 * newPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly after PRICE decimals change"
        );

        // Verify collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e45 = 0.5e9
        uint256 expectedCollateralTokensPerLoanToken = 0.5e9;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / newPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly after PRICE decimals change"
        );
    }

    // given the loan token decimals are smaller than the collateral token decimals
    //  when the PRICE module decimals are changed
    //   [X] it calculates price correctly

    function test_whenLoanTokenDecimalsAreSmallerThanCollateralTokenDecimals_whenPRICEDecimalsAreChanged()
        public
    {
        // Create a new loan token with 9 decimals
        MockERC20 newLoanToken = new MockERC20("New Loan Token", "NEWLOAN", 9);

        // Set loan token price to 1e18
        _setPRICEPrices(address(newLoanToken), 1e18);

        // Create the oracle with the new loan token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(collateralToken),
            address(newLoanToken),
            bytes("")
        );

        // Initial setup: PRICE_DECIMALS = 18
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e27 (36 + loanDecimals - collateralDecimals = 36 + 9 - 18)
        // Expected price: 1e27 * 2e18 / 1e18 = 2e27
        uint256 expectedPrice = 2e27;
        uint256 initialPrice = IMorphoOracle(newOracle).price();
        assertEq(initialPrice, expectedPrice, "Initial price should be 2e27");

        // Change PRICE module decimals from 18 to 9
        priceModule.setPriceDecimals(9);

        // Update prices to maintain same USD values with new decimals
        // 2e18 (18 decimals) -> 2e9 (9 decimals) for $2
        // 1e18 (18 decimals) -> 1e9 (9 decimals) for $1
        _setPRICEPrices(address(collateralToken), 2e9);
        _setPRICEPrices(address(newLoanToken), 1e9);

        // Update factory dependencies to refresh PRICE_DECIMALS
        factory.configureDependencies();

        // Verify factory has updated PRICE_DECIMALS
        assertEq(factory.PRICE_DECIMALS(), 9, "Factory PRICE_DECIMALS should be updated to 9");

        // Oracle should still return correct price
        // The scaleFactor is immutable and based on token decimals (36 + 9 - 18 = 27)
        // collateralPriceUsd = 2e9 (2 USD, 9 decimals)
        // loanPriceUsd = 1e9 (1 USD, 9 decimals)
        // scaleFactor = 1e27 (unchanged, based on token decimals)
        // Price calculation: 1e27 * 2e9 / 1e9 = 2e27
        // The result is still 2e27 because the ratio is preserved
        uint256 newPrice = IMorphoOracle(newOracle).price();
        assertEq(newPrice, expectedPrice, "Price should remain 2e27 after PRICE decimals change");

        // Verify the calculation is still accurate by checking loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e27 / 1e36 = 2e9
        uint256 expectedLoanTokensPerCollateralToken = 2e9;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * newPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly after PRICE decimals change"
        );

        // Verify collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e9 * 1e36 / 2e27 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e9 * 1e36) / newPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly after PRICE decimals change"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
