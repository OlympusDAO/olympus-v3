// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract CachePriceCaller {
    IOracleFactory public factory;
    address public collateralToken;
    address public loanToken;

    constructor(IOracleFactory factory_, address collateralToken_, address loanToken_) {
        factory = factory_;
        collateralToken = collateralToken_;
        loanToken = loanToken_;
    }

    function cachePrice() external {
        factory.cachePrice(collateralToken, loanToken);
    }
}

contract MorphoOracleCloneableCachePricesTest is MorphoOracleCloneableTest {
    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleDisabled.selector,
                address(oracle)
            )
        );
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenOracleAddressIsInvalid_reverts() public {
        CachePriceCaller caller = new CachePriceCaller(
            factory,
            address(collateralToken),
            address(loanToken)
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
        MorphoOracleCloneable(address(oracle)).cachePrice();

        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 1,
            "Price cache should receive direct cache write"
        );
        assertEq(
            priceCache.lastAsset(),
            address(collateralToken),
            "Asset should match oracle collateral"
        );
        assertEq(priceCache.lastQuote(), address(loanToken), "Quote should match oracle loan");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

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
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

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

    function test_whenOnlyCollateralUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair()
        public
    {
        address unitOfAccount = UNIT_OF_ACCOUNT;
        priceCache.setUsdPrice(unitOfAccount, 1e18);

        priceCache.cachePrice(address(collateralToken), address(loanToken));
        IPriceCache.CachedPrice memory oldPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), unitOfAccount);

        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        IPriceCache.CachedPrice memory newPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
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

    function test_whenOnlyLoanUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair() public {
        address unitOfAccount = UNIT_OF_ACCOUNT;
        priceCache.setUsdPrice(unitOfAccount, 1e18);

        priceCache.cachePrice(address(collateralToken), address(loanToken));
        IPriceCache.CachedPrice memory oldPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), unitOfAccount);

        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        IPriceCache.CachedPrice memory newPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
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
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
