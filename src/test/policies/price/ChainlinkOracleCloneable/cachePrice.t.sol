// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
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

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(baseToken), address(quoteToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 1,
            "Fresh cache should not be re-cached"
        );
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryCaches(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(baseToken), address(quoteToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 2,
            "Stale cache should be re-cached"
        );
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
    {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        address zeroMaxAgeOracleAddress = _createOracle(address(baseToken), address(quoteToken), 0);
        ChainlinkOracleCloneable zeroMaxAgeOracle = ChainlinkOracleCloneable(
            zeroMaxAgeOracleAddress
        );

        priceCache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        zeroMaxAgeOracle.cachePriceIfNecessary();

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 3,
            "maxAge=0 should recache pair"
        );
    }

    function test_whenOnlyBaseUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair() public {
        address unitOfAccount = UNIT_OF_ACCOUNT;
        priceCache.setUsdPrice(unitOfAccount, 1e18);

        priceCache.cachePrice(address(baseToken), address(quoteToken));
        IPriceCache.CachedPrice memory oldPair = priceCache.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(baseToken), 3e18);
        priceCache.cachePrice(address(baseToken), unitOfAccount);

        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        IPriceCache.CachedPrice memory newPair = priceCache.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );
        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(newPair.roundId, oldPair.roundId, "Pair round should remain unchanged");
        assertEq(
            newPair.updatedAt,
            oldPair.updatedAt,
            "Direct pair timestamp should remain unchanged"
        );
    }

    function test_whenPriceCachePolicyIsDisabled_cachePriceReverts() public {
        priceCache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
