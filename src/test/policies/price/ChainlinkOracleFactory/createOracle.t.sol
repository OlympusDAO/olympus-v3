// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;
import {Actions} from "src/Kernel.sol";

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {ChainlinkOracleFactoryTest} from "./ChainlinkOracleFactoryTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract ChainlinkOracleFactoryCreateOracleTest is ChainlinkOracleFactoryTest {
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
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
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
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when base token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenBaseTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(0), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when base token is unit of account
    //  [X] it creates the oracle

    function test_whenBaseTokenIsUnitOfAccount_createsOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(
            UNIT_OF_ACCOUNT,
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle should be created for unit-of-account base");
    }

    // when quote token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenQuoteTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(baseToken), address(0), DEFAULT_MAX_AGE, bytes(""));
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

    // when quote token is unit of account
    //  [X] it creates the oracle

    function test_whenQuoteTokenIsUnitOfAccount_createsOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(
            address(baseToken),
            UNIT_OF_ACCOUNT,
            DEFAULT_MAX_AGE,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle should be created for unit-of-account quote");
    }

    // when base token is a registered non-contract asset
    //  given metadata is not registered
    //   [X] it reverts
    //  given metadata is registered
    //   [X] it creates the oracle

    function test_whenBaseTokenIsRegisteredNonContractAsset_givenMetadataIsNotRegistered_reverts()
        public
        givenFactoryIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, BASE_PRICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                registeredNonContractAsset
            )
        );

        vm.prank(admin);
        factory.createOracle(
            registeredNonContractAsset,
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    function test_whenBaseTokenIsRegisteredNonContractAsset_givenMetadataIsRegistered_createsOracle()
        public
        givenFactoryIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, BASE_PRICE);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "RNCA");

        vm.prank(admin);
        address oracle = factory.createOracle(
            registeredNonContractAsset,
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle should be created for registered NCA base");
    }

    // when quote token is a registered non-contract asset
    //  given metadata is not registered
    //   [X] it reverts
    //  given metadata is registered
    //   [X] it creates the oracle

    function test_whenQuoteTokenIsRegisteredNonContractAsset_givenMetadataIsNotRegistered_reverts()
        public
        givenFactoryIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, QUOTE_PRICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                registeredNonContractAsset
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(baseToken),
            registeredNonContractAsset,
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    function test_whenQuoteTokenIsRegisteredNonContractAsset_givenMetadataIsRegistered_createsOracle()
        public
        givenFactoryIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, QUOTE_PRICE);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "RNCA");

        vm.prank(admin);
        address oracle = factory.createOracle(
            address(baseToken),
            registeredNonContractAsset,
            DEFAULT_MAX_AGE,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle should be created for registered NCA quote");
    }

    // when base token equals quote token
    //  [X] it reverts with InvalidTokenPair

    function test_whenBaseEqualsQuote_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidTokenPair.selector,
                address(baseToken),
                address(baseToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(address(baseToken), address(baseToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when base token is not configured in PRICE module
    //  [X] it reverts

    function test_whenBaseTokenIsNotConfiguredInPRICE_reverts() public givenFactoryIsEnabled {
        MockERC20 unconfiguredToken = new MockERC20("Unconfigured", "UNC", 18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_AssetNotApproved.selector,
                address(unconfiguredToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(unconfiguredToken),
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when quote token is not configured in PRICE module
    //  [X] it reverts

    function test_whenQuoteTokenIsNotConfiguredInPRICE_reverts() public givenFactoryIsEnabled {
        MockERC20 unconfiguredToken = new MockERC20("Unconfigured", "UNC", 18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_AssetNotApproved.selector,
                address(unconfiguredToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(
            address(baseToken),
            address(unconfiguredToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );
    }

    // when oracle already exists
    //  [X] it reverts with OracleAlreadyExists

    function test_whenOracleAlreadyExists_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleAlreadyExists.selector,
                address(baseToken),
                address(quoteToken)
            )
        );

        vm.prank(admin);
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when oracle exists for one maxAge
    //  [X] creating oracle with a different maxAge should succeed
    //  [X] each maxAge should map to a different oracle

    function test_whenDifferentMaxAge_createsDistinctOracle() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle1 = factory.createOracle(
            address(baseToken),
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        uint48 secondMaxAge = DEFAULT_MAX_AGE + 1;
        vm.prank(admin);
        address oracle2 = factory.createOracle(
            address(baseToken),
            address(quoteToken),
            secondMaxAge,
            bytes("")
        );

        assertNotEq(oracle1, address(0), "First oracle should be created");
        assertNotEq(oracle2, address(0), "Second oracle should be created");
        assertNotEq(oracle1, oracle2, "Oracles should be different for different maxAge");

        assertEq(
            factory.getOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE),
            oracle1,
            "First oracle should be stored at first maxAge"
        );
        assertEq(
            factory.getOracle(address(baseToken), address(quoteToken), secondMaxAge),
            oracle2,
            "Second oracle should be stored at second maxAge"
        );
    }

    // when all conditions are met
    //  [X] it creates oracle and returns address
    //  [X] it stores oracle in mapping
    //  [X] it adds oracle to oracles array
    //  [X] it marks oracle as valid
    //  [X] it enables oracle by default
    //  [X] it emits OracleCreated event
    //  [X] it emits OracleEnabled event

    function test_whenAllConditionsAreMet_createsOracle() public givenFactoryIsEnabled {
        vm.expectEmit(false, false, false, false);
        emit IOracleFactory.OracleCreated(
            address(0), // oracle address (will be checked separately)
            address(baseToken),
            address(quoteToken)
        );

        vm.expectEmit(false, false, false, false);
        emit IOracleFactory.OracleEnabled(address(0)); // oracle address (will be checked separately)

        vm.prank(admin);
        address oracle = factory.createOracle(
            address(baseToken),
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Check oracle is not zero
        assertNotEq(oracle, address(0), "Oracle address should not be zero");

        // Check oracle is stored in mapping
        assertEq(
            factory.getOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE),
            oracle,
            "Oracle should be stored in mapping"
        );

        // Check oracle is in oracles array
        address[] memory oracles = factory.getOracles();
        assertEq(oracles.length, 1, "Oracles array should have one element");
        assertEq(oracles[0], oracle, "Oracle should be in oracles array");

        // Check oracle is marked as valid
        assertTrue(factory.isOracle(oracle), "Oracle should be marked as valid");

        // Check oracle is enabled by default
        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled by default");

        // Check oracle implements IChainlinkOracle
        IChainlinkOracle chainlinkOracle = IChainlinkOracle(oracle);
        assertEq(chainlinkOracle.baseToken(), address(baseToken), "Base token should match");
        assertEq(chainlinkOracle.quoteToken(), address(quoteToken), "Quote token should match");
        assertEq(
            chainlinkOracle.decimals(),
            PRICE_DECIMALS,
            "Decimals should match PRICE decimals"
        );
    }

    function test_whenOracleIsCreated_cachesBaseAndQuotePrices() public givenFactoryIsEnabled {
        vm.prank(admin);
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));

        uint48 timestamp = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;

        assertGt(timestamp, 0, "Asset price should be cached");
    }

    // when called by manager
    //  [X] it reverts

    function test_whenCalledByManager_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(manager);
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
    }

    // when called by oracle manager
    //  [X] it succeeds

    function test_whenCalledByOracleManager_succeeds() public givenFactoryIsEnabled {
        vm.prank(oracleManager);
        address oracle = factory.createOracle(
            address(baseToken),
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle address should not be zero");
    }

    // when maxAge is zero
    //  [X] it creates oracle successfully

    function test_whenMaxAgeIsZero_succeeds() public givenFactoryIsEnabled {
        vm.prank(admin);
        address oracle = factory.createOracle(
            address(baseToken),
            address(quoteToken),
            0,
            bytes("")
        );

        assertNotEq(oracle, address(0), "Oracle address should not be zero");
        assertEq(
            factory.getOracle(address(baseToken), address(quoteToken), 0),
            oracle,
            "Oracle should be stored for maxAge=0"
        );
    }

    function test_whenPriceCacheDecimalsChange_newOracleUsesCacheDecimals()
        public
        givenFactoryIsEnabled
    {
        priceCache.setPriceDecimals(9);

        vm.prank(admin);
        address oracle = factory.createOracle(
            address(baseToken),
            address(quoteToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        assertEq(IChainlinkOracle(oracle).decimals(), 9, "Oracle decimals should come from cache");
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
            address(baseToken),
            address(quoteToken),
            maxAge_,
            bytes("")
        );
        assertEq(
            IChainlinkOracle(created).maxAge(),
            maxAge_,
            "Immutable age round-trips the full uint48 domain"
        );
        assertEq(
            IChainlinkOracle(created).name(),
            string.concat("BASE/QUOTE CL ", vm.toString(uint256(maxAge_)), "s"),
            "Immutable age does not overwrite the display name"
        );
    }

    function test_givenLongSymbol_whenCreated_thenNameUsesFirstThirtyTwoBytes()
        public
        givenFactoryIsEnabled
    {
        string memory symbol = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456EXTRA";
        MockERC20 longToken = new MockERC20("Long symbol", symbol, 18);
        _setPRICEPrices(address(longToken), 1e18);
        vm.prank(admin);
        address created = factory.createOracle(
            address(longToken),
            address(quoteToken),
            1,
            bytes("")
        );
        assertEq(
            IChainlinkOracle(created).name(),
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
                address(baseToken),
                address(quoteToken),
                uint8(18),
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
        IChainlinkOracle(malformed).maxAge();
    }

    function test_whenMalformedAgeBoundariesSeeded_reverts() public {
        test_givenMalformedImmutableAge_whenRead_reverts(uint64(type(uint48).max) + 1);
        test_givenMalformedImmutableAge_whenRead_reverts(type(uint64).max);
    }

    // Scenarios: CHAINLINK-CREATE-ORACLE-L01.
    function test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst(
        address caller_,
        bool enabled_
    ) public {
        if (enabled_) _enableFactory();
        vm.prank(kernel.executor());
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));
        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);

        vm.prank(caller_);
        factory.createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE, bytes(""));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
