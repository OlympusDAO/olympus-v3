// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract CachePriceCaller {
    IOracleFactory public factory;
    address public baseToken;
    address public quoteToken;

    constructor(IOracleFactory factory_, address baseToken_, address quoteToken_) {
        factory = factory_;
        baseToken = baseToken_;
        quoteToken = quoteToken_;
    }

    function cachePrice() external {
        factory.cachePrice(baseToken, quoteToken);
    }
}

contract ChainlinkOracleCloneableCachePriceTest is ChainlinkOracleCloneableTest {
    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleDisabled.selector,
                address(oracle)
            )
        );
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenOracleAddressIsInvalid_reverts() public {
        CachePriceCaller caller = new CachePriceCaller(
            factory,
            address(baseToken),
            address(quoteToken)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrice();
    }

    function test_whenOracleIsEnabled_cachesDirectPair() public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        ChainlinkOracleCloneable(address(oracle)).cachePrice();

        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 1,
            "Price cache should receive direct cache write"
        );
        assertEq(priceCache.lastAsset(), address(baseToken), "Asset should match oracle base");
        assertEq(priceCache.lastQuote(), address(quoteToken), "Quote should match oracle quote");
    }

    function test_whenPriceCachePolicyIsDisabled_cachePriceReverts() public {
        priceCache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
