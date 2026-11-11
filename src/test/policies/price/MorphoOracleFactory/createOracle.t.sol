// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;
import {Actions} from "src/Kernel.sol";

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract MorphoOracleFactoryCreateOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // createOracle
    // when caller does not have required role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when creation is disabled
    //  [X] it reverts with CreationDisabled

    function test_whenCreationIsDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.expectRevert(IOracleFactory.OracleFactory_CreationDisabled.selector);

        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when collateral token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenCollateralTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(0), address(loanToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when collateral token is unit of account
    //  [X] it creates the oracle

    function test_whenCollateralTokenIsUnitOfAccount_createsOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(
            UNIT_OF_ACCOUNT,
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        _assertOracleConfigured(oracle, UNIT_OF_ACCOUNT, address(loanToken), DEFAULT_MAX_AGE, 1e36);
        assertEq(IMorphoOracle(oracle).price(), 1e36, "Oracle price should use unit collateral");
    }

    // when loan token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenLoanTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(collateralToken), address(0), DEFAULT_MAX_AGE, bytes(""));
    }

    // when both tokens are zero addresses
    //  [X] it reverts with InvalidToken

    function test_whenBothTokensAreZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(0), address(0), DEFAULT_MAX_AGE, bytes(""));
    }

    // when loan token is unit of account
    //  [X] it creates the oracle

    function test_whenLoanTokenIsUnitOfAccount_createsOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(
            address(collateralToken),
            UNIT_OF_ACCOUNT,
            DEFAULT_MAX_AGE,
            bytes("")
        );

        _assertOracleConfigured(
            oracle,
            address(collateralToken),
            UNIT_OF_ACCOUNT,
            DEFAULT_MAX_AGE,
            1e36
        );
        assertEq(IMorphoOracle(oracle).price(), 2e36, "Oracle price should use unit loan");
    }

    // when collateral token is a registered non-contract asset
    //  given metadata is not registered
    //   [X] it reverts
    //  given metadata is registered
    //   [X] it creates the oracle

    function test_whenCollateralTokenIsRegisteredNonContractAsset_givenMetadataIsNotRegistered_reverts()
        public
        givenFactoryIsEnabled
    {
        _setCachePrice(registeredNonContractAsset, 2e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                registeredNonContractAsset
            )
        );

        vm.prank(admin);
        factory.createOracle(
            registeredNonContractAsset,
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    function test_whenCollateralTokenIsRegisteredNonContractAsset_givenMetadataIsRegistered_createsOracle()
        public
        givenFactoryIsEnabled
    {
        _setCachePrice(registeredNonContractAsset, 2e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "RNCA");

        vm.prank(admin);
        address oracle = factory.createOracle(
            registeredNonContractAsset,
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        _assertOracleConfigured(
            oracle,
            registeredNonContractAsset,
            address(loanToken),
            DEFAULT_MAX_AGE,
            1e46
        );
        assertEq(IMorphoOracle(oracle).price(), 2e46, "Oracle price should use NCA collateral");
    }

    // when loan token is a registered non-contract asset
    //  given metadata is not registered
    //   [X] it reverts
    //  given metadata is registered
    //   [X] it creates the oracle

    function test_whenLoanTokenIsRegisteredNonContractAsset_givenMetadataIsNotRegistered_reverts()
        public
        givenFactoryIsEnabled
    {
        _setCachePrice(registeredNonContractAsset, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                registeredNonContractAsset
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            registeredNonContractAsset,
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    function test_whenLoanTokenIsRegisteredNonContractAsset_givenMetadataIsRegistered_createsOracle()
        public
        givenFactoryIsEnabled
    {
        _setCachePrice(registeredNonContractAsset, 1e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "RNCA");

        vm.prank(admin);
        address oracle = factory.createOracle(
            address(collateralToken),
            registeredNonContractAsset,
            DEFAULT_MAX_AGE,
            bytes("")
        );

        _assertOracleConfigured(
            oracle,
            address(collateralToken),
            registeredNonContractAsset,
            DEFAULT_MAX_AGE,
            1e26
        );
        assertEq(IMorphoOracle(oracle).price(), 2e26, "Oracle price should use NCA loan");
    }

    // when collateral token equals loan token
    //  [X] it reverts with InvalidTokenPair

    function test_whenCollateralEqualsLoan_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidTokenPair.selector,
                address(collateralToken),
                address(collateralToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(collateralToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when collateral token is not in PRICE module
    //  [X] it reverts with PRICE error

    function test_whenCollateralTokenIsNotInPRICEModule_reverts() public givenFactoryIsEnabled {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        // Don't set price for this token

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(newToken))
        );

        vm.prank(admin);
        factory.createOracle(address(newToken), address(loanToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when loan token is not in PRICE module
    //  [X] it reverts with PRICE error

    function test_whenLoanTokenIsNotInPRICEModule_reverts() public givenFactoryIsEnabled {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        // Don't set price for this token

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(newToken))
        );

        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(newToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when oracle already exists
    //  [X] it reverts with OracleAlreadyExists

    function test_whenOracleAlreadyExists_reverts() public givenFactoryIsEnabled {
        // Create first oracle
        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Try to create duplicate
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleAlreadyExists.selector,
                address(collateralToken),
                address(loanToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when oracle exists for one maxAge
    //  [X] creating oracle with a different maxAge should succeed
    //  [X] each maxAge should map to a different oracle

    function test_whenDifferentMaxAge_createsDistinctOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle1 = factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        uint48 secondMaxAge = DEFAULT_MAX_AGE + 1;
        vm.prank(admin);
        address oracle2 = factory.createOracle(
            address(collateralToken),
            address(loanToken),
            secondMaxAge,
            bytes("")
        );

        assertNotEq(oracle1, address(0), "First oracle should be created");
        assertNotEq(oracle2, address(0), "Second oracle should be created");
        assertNotEq(oracle1, oracle2, "Oracles should be different for different maxAge");

        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE),
            oracle1,
            "First oracle should be stored at first maxAge"
        );
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), secondMaxAge),
            oracle2,
            "Second oracle should be stored at second maxAge"
        );
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

        _setCachePrice(address(highDecimalsToken), 1e18);
        _setCachePrice(address(lowDecimalsToken), 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                MorphoOracleFactory.MorphoOracleFactory_TokenDecimalsOutOfBounds.selector,
                address(lowDecimalsToken),
                address(highDecimalsToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(lowDecimalsToken),
            address(highDecimalsToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
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

    function test_whenAllConditionsAreMet_createsOracle() public givenFactoryIsEnabled {
        vm.expectEmit(false, false, false, false);
        emit IOracleFactory.OracleCreated(
            address(0), // Will be set to actual oracle address
            address(collateralToken),
            address(loanToken)
        );

        vm.expectEmit(false, false, false, false);
        emit IOracleFactory.OracleEnabled(address(0)); // Will match any address

        vm.prank(admin);
        address oracle = factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Verify oracle is deployed
        assertNotEq(oracle, address(0), "Oracle should be deployed");

        // Verify oracle is stored in mapping
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE),
            oracle,
            "Oracle should be stored in mapping"
        );

        // Verify that there is no oracle for a different ordering
        assertEq(
            factory.getOracle(address(loanToken), address(collateralToken), DEFAULT_MAX_AGE),
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

        // Verify name is stored in oracle
        assertEq(oracleContract.name(), "COL/LOAN M 3600s", "Name should be stored in oracle");
    }

    function test_whenOracleIsCreated_cachesCollateralAndLoanPrices() public givenFactoryIsEnabled {
        vm.prank(admin);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        uint48 timestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertGt(timestamp, 0, "Token price should be cached");
    }

    function test_whenCachePriceCalledByNonOracle_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidOracle.selector, admin)
        );

        vm.prank(admin);
        factory.cachePrice(address(collateralToken), address(loanToken));
    }

    function test_whenTokenDecimalsAreValid_calculatesScaleFactorWithDifferentDecimals()
        public
        givenFactoryIsEnabled
    {
        // Test with different decimals: collateral 6, loan 18
        MockERC20 col6 = new MockERC20("Collateral 6", "COL6", 6);
        MockERC20 loan18 = new MockERC20("Loan 18", "LOAN18", 18);

        _setCachePrice(address(col6), 2e18);
        _setCachePrice(address(loan18), 1e18);

        vm.prank(admin);
        address oracle = factory.createOracle(
            address(col6),
            address(loan18),
            DEFAULT_MAX_AGE,
            bytes("")
        );

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
        address oracle = factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Verify oracle is deployed
        assertNotEq(oracle, address(0), "Oracle should be deployed");

        // Verify oracle is stored in mapping
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE),
            oracle,
            "Oracle should be stored in mapping"
        );
    }

    // when maxAge is zero
    //  [X] it creates oracle successfully

    function test_whenMaxAgeIsZero_succeeds() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(
            address(collateralToken),
            address(loanToken),
            0,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle should be deployed");
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), 0),
            oracle,
            "Oracle should be stored for maxAge=0"
        );
    }

    function _assertOracleConfigured(
        address oracle_,
        address collateralToken_,
        address loanToken_,
        uint48 maxAge_,
        uint256 scaleFactor_
    ) internal view {
        IMorphoOracle oracle = IMorphoOracle(oracle_);

        assertNotEq(oracle_, address(0), "Oracle should be created");
        assertEq(oracle.collateralToken(), collateralToken_, "Collateral token should match");
        assertEq(oracle.loanToken(), loanToken_, "Loan token should match");
        assertEq(oracle.maxAge(), maxAge_, "Max age should match");
        assertEq(oracle.scaleFactor(), scaleFactor_, "Scale factor should match");
    }

    // when the caller has the manager role
    //  [X] it reverts

    function test_whenCallerHasManagerRole_reverts() public givenFactoryIsEnabled {
        // Expect revert
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        // Call function
        vm.prank(manager);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    function test_whenMaxAgeInUint48Range_thenImmutableMetadataRoundTrips(
        uint48 maxAge_
    ) public givenFactoryIsEnabled {
        _assertImmutableMetadata(maxAge_);
    }

    function test_whenMaxAgeBoundariesSeeded_thenImmutableMetadataRoundTrips()
        public
        givenFactoryIsEnabled
    {
        _assertImmutableMetadata(0);
        _assertImmutableMetadata(1);
        _assertImmutableMetadata(type(uint48).max);
    }

    function _assertImmutableMetadata(uint48 maxAge_) private {
        vm.prank(admin);
        address created = factory.createOracle(
            address(collateralToken),
            address(loanToken),
            maxAge_,
            bytes("")
        );
        assertEq(
            IMorphoOracle(created).maxAge(),
            maxAge_,
            "Immutable age round-trips the full uint48 domain"
        );
        assertEq(
            MorphoOracleCloneable(created).name(),
            string.concat("COL/LOAN M ", vm.toString(uint256(maxAge_)), "s"),
            "Immutable age does not overwrite the display name"
        );
    }

    function test_givenLongSymbol_whenCreated_thenNameUsesFirstThirtyTwoBytes()
        public
        givenFactoryIsEnabled
    {
        string memory symbol = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456EXTRA";
        MockERC20 longToken = new MockERC20("Long symbol", symbol, 18);
        _setCachePrice(address(longToken), 1e18);
        vm.prank(admin);
        address created = factory.createOracle(
            address(longToken),
            address(loanToken),
            1,
            bytes("")
        );
        assertEq(
            MorphoOracleCloneable(created).name(),
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456",
            "Display names retain exactly the first 32 bytes"
        );
    }

    function test_givenMalformedImmutableAge_whenRead_reverts(uint64 rawAge_) public {
        rawAge_ = SafeCast.toUint64(
            bound(rawAge_, uint256(type(uint48).max) + 1, type(uint64).max)
        );
        address malformed = ClonesWithImmutableArgs.clone(
            address(factory.ORACLE_IMPLEMENTATION()),
            abi.encodePacked(
                address(factory),
                address(collateralToken),
                address(loanToken),
                rawAge_,
                bytes32("BOUNDARY")
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(rawAge_)
            )
        );
        IMorphoOracle(malformed).maxAge();
    }

    function test_whenMalformedAgeBoundariesSeeded_reverts() public {
        test_givenMalformedImmutableAge_whenRead_reverts(uint64(type(uint48).max) + 1);
        test_givenMalformedImmutableAge_whenRead_reverts(type(uint64).max);
    }

    // Scenarios: MORPHO-CREATE-ORACLE-L01.
    function test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst(
        address caller_,
        bool enabled_
    ) public {
        if (enabled_) _enableFactory();
        vm.prank(kernel.executor());
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));
        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);

        vm.prank(caller_);
        factory.createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
