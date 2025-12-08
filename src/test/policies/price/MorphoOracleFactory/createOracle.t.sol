// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IMorphoOracleFactory} from "src/policies/interfaces/price/IMorphoOracleFactory.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";

contract MorphoOracleFactoryCreateOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // createOracle
    // when caller does not have required role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin && caller_ != manager && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.createOracle(address(collateralToken), address(loanToken));
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(loanToken));
    }

    // when creation is disabled
    //  [X] it reverts with CreationDisabled

    function test_whenCreationIsDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.expectRevert(IMorphoOracleFactory.MorphoOracleFactory_CreationDisabled.selector);

        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(loanToken));
    }

    // when collateral token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenCollateralTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_InvalidToken.selector,
                address(0)
            )
        );

        vm.prank(admin);
        factory.createOracle(address(0), address(loanToken));
    }

    // when collateral token is not a contract
    //  [X] it reverts with InvalidToken

    function test_whenCollateralTokenIsNotAContract_reverts() public givenFactoryIsEnabled {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_InvalidToken.selector,
                nonContract
            )
        );

        vm.prank(admin);
        factory.createOracle(nonContract, address(loanToken));
    }

    // when loan token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenLoanTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_InvalidToken.selector,
                address(0)
            )
        );

        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(0));
    }

    // when loan token is not a contract
    //  [X] it reverts with InvalidToken

    function test_whenLoanTokenIsNotAContract_reverts() public givenFactoryIsEnabled {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_InvalidToken.selector,
                nonContract
            )
        );

        vm.prank(admin);
        factory.createOracle(address(collateralToken), nonContract);
    }

    // when collateral token is not in PRICE module
    //  [X] it reverts with PRICE error

    function test_whenCollateralTokenIsNotInPRICEModule_reverts() public givenFactoryIsEnabled {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        // Don't set price for this token

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(newToken))
        );

        vm.prank(admin);
        factory.createOracle(address(newToken), address(loanToken));
    }

    // when loan token is not in PRICE module
    //  [X] it reverts with PRICE error

    function test_whenLoanTokenIsNotInPRICEModule_reverts() public givenFactoryIsEnabled {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        // Don't set price for this token

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(newToken))
        );

        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(newToken));
    }

    // when oracle already exists
    //  [X] it reverts with OracleAlreadyExists

    function test_whenOracleAlreadyExists_reverts() public givenFactoryIsEnabled {
        // Create first oracle
        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(loanToken));

        // Try to create duplicate
        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_OracleAlreadyExists.selector,
                address(collateralToken),
                address(loanToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(loanToken));
    }

    // when token decimals cause overflow
    //  [X] it reverts with TokenDecimalsOutOfBounds

    function test_whenTokenDecimalsCauseOverflow_reverts() public givenFactoryIsEnabled {
        // Create tokens with decimals that would cause overflow
        // loanDecimals - collateralDecimals + 36 > 77
        // For example: collateralDecimals = 0, loanDecimals = 42
        // 42 - 0 + 36 = 78 > 77
        MockERC20 highDecimalsToken = new MockERC20("High Decimals", "HIGH", 42);
        MockERC20 lowDecimalsToken = new MockERC20("Low Decimals", "LOW", 0);

        _setPRICEPrices(address(highDecimalsToken), 1e18);
        _setPRICEPrices(address(lowDecimalsToken), 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_TokenDecimalsOutOfBounds.selector,
                address(lowDecimalsToken),
                address(highDecimalsToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(address(lowDecimalsToken), address(highDecimalsToken));
    }

    // when token decimals are valid
    //  [X] it deploys oracle clone
    //  [X] it stores oracle in mapping
    //  [X] it adds oracle to array
    //  [X] it sets isOracle to true
    //  [X] it sets oracle enabled to true
    //  [X] it emits OracleCreated event
    //  [X] it emits OracleEnabled event
    //  [X] it calculates scale factor correctly

    function test_success() public givenFactoryIsEnabled {
        vm.expectEmit(false, false, false, false);
        emit IMorphoOracleFactory.OracleCreated(
            address(0), // Will be set to actual oracle address
            address(collateralToken),
            address(loanToken)
        );

        vm.expectEmit(false, false, false, false);
        emit IMorphoOracleFactory.OracleEnabled(address(0)); // Will match any address

        vm.prank(admin);
        address oracle = factory.createOracle(address(collateralToken), address(loanToken));

        // Verify oracle is deployed
        assertNotEq(oracle, address(0), "Oracle should be deployed");

        // Verify oracle is stored in mapping
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken)),
            oracle,
            "Oracle should be stored in mapping"
        );

        // Verify that there is no oracle for a different ordering
        assertEq(
            factory.getOracle(address(loanToken), address(collateralToken)),
            address(0),
            "There should be no oracle for a different ordering"
        );

        // Verify oracle is in array
        address[] memory oracles = factory.getOracles();
        assertEq(oracles.length, 1, "Should have one oracle");
        assertEq(oracles[0], oracle, "Oracle should be in array");

        // Verify isOracle is true
        assertTrue(factory.isOracle(oracle), "isOracle should be true");

        // Verify oracle is enabled
        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");

        // Verify scale factor calculation
        // Scale factor = 10^(36 + loanDecimals - collateralDecimals)
        MorphoOracleCloneable oracleContract = MorphoOracleCloneable(oracle);
        uint256 expectedScaleFactor = 10 ** (36 + 18 - 18); // 10^36
        assertEq(
            oracleContract.scaleFactor(),
            expectedScaleFactor,
            "Scale factor should be calculated correctly"
        );

        // Verify collateral token is stored in oracle
        assertEq(
            oracleContract.collateralToken(),
            address(collateralToken),
            "Collateral token should be stored in oracle"
        );

        // Verify loan token is stored in oracle
        assertEq(
            oracleContract.loanToken(),
            address(loanToken),
            "Loan token should be stored in oracle"
        );

        // Verify factory is stored in oracle
        assertEq(
            address(oracleContract.factory()),
            address(factory),
            "Factory should be stored in oracle"
        );
    }

    function test_whenTokenDecimalsAreValid_calculatesScaleFactorWithDifferentDecimals()
        public
        givenFactoryIsEnabled
    {
        // Test with different decimals: collateral 6, loan 18
        MockERC20 col6 = new MockERC20("Collateral 6", "COL6", 6);
        MockERC20 loan18 = new MockERC20("Loan 18", "LOAN18", 18);

        _setPRICEPrices(address(col6), 2e18);
        _setPRICEPrices(address(loan18), 1e18);

        vm.prank(admin);
        address oracle = factory.createOracle(address(col6), address(loan18));

        // Verify scale factor calculation
        // Scale factor = 10^(36 + loanDecimals - collateralDecimals)
        IMorphoOracle oracleContract = IMorphoOracle(oracle);
        uint256 expectedScaleFactor = 10 ** (36 + 18 - 6); // 10^48
        assertEq(
            oracleContract.scaleFactor(),
            expectedScaleFactor,
            "Scale factor should be calculated correctly for different decimals"
        );
    }

    // when the caller has the oracle_manager role
    //  [X] it succeeds

    function test_whenCallerHasOracleManagerRole() public givenFactoryIsEnabled {
        vm.prank(oracleManager);
        address oracle = factory.createOracle(address(collateralToken), address(loanToken));

        // Verify oracle is deployed
        assertNotEq(oracle, address(0), "Oracle should be deployed");

        // Verify oracle is stored in mapping
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken)),
            oracle,
            "Oracle should be stored in mapping"
        );
    }

    // when the caller has the manager role
    //  [X] it succeeds

    function test_whenCallerHasManagerRole() public givenFactoryIsEnabled {
        vm.prank(manager);
        address oracle = factory.createOracle(address(collateralToken), address(loanToken));

        // Verify oracle is deployed
        assertNotEq(oracle, address(0), "Oracle should be deployed");

        // Verify oracle is stored in mapping
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken)),
            oracle,
            "Oracle should be stored in mapping"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
