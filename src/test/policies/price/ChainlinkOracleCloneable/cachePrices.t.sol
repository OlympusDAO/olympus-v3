// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract CachePricesCaller {
    IOracleFactory public factory;

    constructor(IOracleFactory factory_) {
        factory = factory_;
    }

    function cachePrices() external {
        factory.cacheOraclePrices();
    }
}

contract ChainlinkOracleCloneableCachePricesTest is ChainlinkOracleCloneableTest {
    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleDisabled.selector,
                address(oracle)
            )
        );
        ChainlinkOracleCloneable(address(oracle)).cachePrices();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrices();
    }

    function test_whenOracleAddressIsInvalid_reverts() public {
        CachePricesCaller caller = new CachePricesCaller(factory);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrices();
    }

    function test_whenOracleIsEnabled_cachesBaseAndQuotePrices() public {
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePrices();

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(newBaseTimestamp, oldBaseTimestamp, "Base token price should be re-cached");
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "Quote token price should be re-cached");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache() public {
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePricesIfNecessary();

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        assertEq(newBaseTimestamp, oldBaseTimestamp, "Base token price should not be re-cached");
        assertEq(newQuoteTimestamp, oldQuoteTimestamp, "Quote token price should not be re-cached");
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryCaches() public {
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePricesIfNecessary();

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(newBaseTimestamp, oldBaseTimestamp, "Base token price should be re-cached");
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "Quote token price should be re-cached");
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
    {
        address zeroMaxAgeOracleAddress = _createOracle(address(baseToken), address(quoteToken), 0);
        ChainlinkOracleCloneable zeroMaxAgeOracle = ChainlinkOracleCloneable(zeroMaxAgeOracleAddress);

        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        zeroMaxAgeOracle.cachePricesIfNecessary();

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(newBaseTimestamp, oldBaseTimestamp, "maxAge=0 should recache base token");
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "maxAge=0 should recache quote token");
    }

    function test_whenTimestampsAreDifferent_cachePricesIfNecessaryCaches() public {
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(baseToken));

        (, uint48 baseTimestampBefore) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 quoteTimestampBefore) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(
            baseTimestampBefore,
            quoteTimestampBefore,
            "Base timestamp should be newer before recache"
        );

        ChainlinkOracleCloneable(address(oracle)).cachePricesIfNecessary();

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        assertEq(newBaseTimestamp, newQuoteTimestamp, "Timestamps should be aligned after recache");
        assertEq(
            newBaseTimestamp,
            baseTimestampBefore,
            "Base timestamp should remain at current block"
        );
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "Quote timestamp should be updated");
        assertEq(
            oldBaseTimestamp + 1,
            baseTimestampBefore,
            "Base timestamp should have advanced by one"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
