// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ChainlinkOracleFactoryTest} from "./ChainlinkOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

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
        factory.createOracle(address(baseToken), address(quoteToken), bytes(""));
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.createOracle(address(baseToken), address(quoteToken), bytes(""));
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
        factory.createOracle(address(baseToken), address(quoteToken), bytes(""));
    }

    // when base token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenBaseTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(0), address(quoteToken), bytes(""));
    }

    // when base token is not a contract
    //  [X] it reverts with InvalidToken

    function test_whenBaseTokenIsNotAContract_reverts() public givenFactoryIsEnabled {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, nonContract)
        );

        vm.prank(admin);
        factory.createOracle(nonContract, address(quoteToken), bytes(""));
    }

    // when quote token is zero address
    //  [X] it reverts with InvalidToken

    function test_whenQuoteTokenIsZeroAddress_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, address(0))
        );

        vm.prank(admin);
        factory.createOracle(address(baseToken), address(0), bytes(""));
    }

    // when quote token is not a contract
    //  [X] it reverts with InvalidToken

    function test_whenQuoteTokenIsNotAContract_reverts() public givenFactoryIsEnabled {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidToken.selector, nonContract)
        );

        vm.prank(admin);
        factory.createOracle(address(baseToken), nonContract, bytes(""));
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
        factory.createOracle(address(unconfiguredToken), address(quoteToken), bytes(""));
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
        factory.createOracle(address(baseToken), address(unconfiguredToken), bytes(""));
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
        factory.createOracle(address(baseToken), address(quoteToken), bytes(""));
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
        address oracle = factory.createOracle(address(baseToken), address(quoteToken), bytes(""));

        // Check oracle is not zero
        assertNotEq(oracle, address(0), "Oracle address should not be zero");

        // Check oracle is stored in mapping
        assertEq(
            factory.getOracle(address(baseToken), address(quoteToken)),
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

    // when called by manager
    //  [X] it reverts

    function test_whenCalledByManager_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(manager);
        factory.createOracle(address(baseToken), address(quoteToken), bytes(""));
    }

    // when called by oracle manager
    //  [X] it succeeds

    function test_whenCalledByOracleManager_succeeds() public givenFactoryIsEnabled {
        vm.prank(oracleManager);
        address oracle = factory.createOracle(address(baseToken), address(quoteToken), bytes(""));

        assertNotEq(oracle, address(0), "Oracle address should not be zero");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
