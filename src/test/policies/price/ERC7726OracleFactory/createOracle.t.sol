// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;
import {Actions} from "src/Kernel.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";

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

        // Seed direct pair cache in configured price cache policy.
        priceCache.cachePrice(address(baseToken), address(quoteToken));

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

    function test_whenMaxAgeInUint48Range_thenImmutableAgeRoundTrips(
        uint48 maxAge_
    ) public givenFactoryIsEnabled {
        _assertImmutableAge(maxAge_);
    }

    function test_whenMaxAgeBoundariesSeeded_thenImmutableAgeRoundTrips()
        public
        givenFactoryIsEnabled
    {
        _assertImmutableAge(0);
        _assertImmutableAge(1);
        _assertImmutableAge(type(uint48).max);
    }

    function _assertImmutableAge(uint48 maxAge_) private {
        vm.prank(admin);
        address created = factory.createOracle(maxAge_, bytes(""));
        assertEq(
            IERC7726Oracle(created).maxAge(),
            maxAge_,
            "Immutable age round-trips the full uint48 domain"
        );
    }

    function test_givenMalformedImmutableAge_whenRead_reverts(uint64 rawAge_) public {
        rawAge_ = SafeCast.toUint64(
            bound(rawAge_, uint256(type(uint48).max) + 1, type(uint64).max)
        );
        address malformed = ClonesWithImmutableArgs.clone(
            address(factory.ORACLE_IMPLEMENTATION()),
            abi.encodePacked(address(factory), rawAge_, bytes32("BOUNDARY"))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(rawAge_)
            )
        );
        IERC7726Oracle(malformed).maxAge();
    }

    function test_whenMalformedAgeBoundariesSeeded_reverts() public {
        test_givenMalformedImmutableAge_whenRead_reverts(uint64(type(uint48).max) + 1);
        test_givenMalformedImmutableAge_whenRead_reverts(type(uint64).max);
    }

    // Scenarios: ERC7726-CREATE-ORACLE-L01.
    function test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst(
        address caller_,
        bool enabled_
    ) public givenFactoryIsEnabled givenFactoryIsDisabled {
        if (enabled_) _enableFactory();
        vm.prank(kernel.executor());
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));
        vm.expectRevert(IERC7726OracleFactory.ERC7726OracleFactory_PolicyNotActive.selector);

        vm.prank(caller_);
        factory.createOracle(DEFAULT_MAX_AGE, bytes(""));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
