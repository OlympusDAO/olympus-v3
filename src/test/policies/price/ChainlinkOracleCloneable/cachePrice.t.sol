// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract CachePriceCaller {
    IOracleFactory public factory;

    constructor(IOracleFactory factory_) {
        factory = factory_;
    }

    function cachePrice() external {
        factory.cacheOraclePrices();
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
        CachePriceCaller caller = new CachePriceCaller(factory);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrice();
    }

    function test_whenOracleIsEnabled_cachesDirectPair() public {
        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 oldRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 newRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        assertGt(newPairTimestamp, oldPairTimestamp, "Pair timestamp should be re-cached");
        assertGt(newRoundId, oldRoundId, "Pair round ID should increment");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache() public {
        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 oldRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 newRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        assertEq(newPairTimestamp, oldPairTimestamp, "Pair timestamp should not be re-cached");
        assertEq(newRoundId, oldRoundId, "Pair round ID should not change");
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryCaches() public {
        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 oldRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 newRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        assertGt(newPairTimestamp, oldPairTimestamp, "Pair timestamp should be re-cached");
        assertGt(newRoundId, oldRoundId, "Pair round ID should increment");
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
    {
        address zeroMaxAgeOracleAddress = _createOracle(address(baseToken), address(quoteToken), 0);
        ChainlinkOracleCloneable zeroMaxAgeOracle = ChainlinkOracleCloneable(
            zeroMaxAgeOracleAddress
        );

        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 oldRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + 1);
        zeroMaxAgeOracle.cachePriceIfNecessary();

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 newRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        assertGt(newPairTimestamp, oldPairTimestamp, "maxAge=0 should recache pair timestamp");
        assertGt(newRoundId, oldRoundId, "maxAge=0 should increment pair round ID");
    }

    function test_whenOnlyBaseUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair() public {
        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 oldRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(baseToken), priceModule.unitOfAccount());

        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 newRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        assertEq(newPairTimestamp, oldPairTimestamp, "Pair timestamp should remain unchanged");
        assertEq(newRoundId, oldRoundId, "Pair round ID should remain unchanged");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
