// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract CachePricesCaller {
    IOracleFactory public factory;

    constructor(IOracleFactory factory_) {
        factory = factory_;
    }

    function cachePrices() external {
        factory.cacheOraclePrices();
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
        MorphoOracleCloneable(address(oracle)).cachePrices();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        MorphoOracleCloneable(address(oracle)).cachePrices();
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

    function test_whenOracleIsEnabled_cachesCollateralAndLoanPrices() public {
        (, uint48 oldCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        MorphoOracleCloneable(address(oracle)).cachePrices();

        (, uint48 newCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(
            newCollateralTimestamp,
            oldCollateralTimestamp,
            "Collateral price should be re-cached"
        );
        assertGt(newLoanTimestamp, oldLoanTimestamp, "Loan price should be re-cached");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache() public {
        (, uint48 oldCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        MorphoOracleCloneable(address(oracle)).cachePricesIfNecessary();

        (, uint48 newCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        assertEq(
            newCollateralTimestamp,
            oldCollateralTimestamp,
            "Collateral price should not be re-cached"
        );
        assertEq(newLoanTimestamp, oldLoanTimestamp, "Loan price should not be re-cached");
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryCaches() public {
        (, uint48 oldCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        MorphoOracleCloneable(address(oracle)).cachePricesIfNecessary();

        (, uint48 newCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(
            newCollateralTimestamp,
            oldCollateralTimestamp,
            "Collateral price should be re-cached"
        );
        assertGt(newLoanTimestamp, oldLoanTimestamp, "Loan price should be re-cached");
    }

    function test_whenTimestampsAreDifferent_cachePricesIfNecessaryCaches() public {
        (, uint48 oldCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(collateralToken));

        (, uint48 collateralTimestampBefore) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 loanTimestampBefore) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(
            collateralTimestampBefore,
            loanTimestampBefore,
            "Collateral timestamp should be newer before recache"
        );

        MorphoOracleCloneable(address(oracle)).cachePricesIfNecessary();

        (, uint48 newCollateralTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newLoanTimestamp) = priceModule.getPrice(
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        assertEq(
            newCollateralTimestamp,
            newLoanTimestamp,
            "Timestamps should be aligned after recache"
        );
        assertEq(
            newCollateralTimestamp,
            collateralTimestampBefore,
            "Collateral timestamp should remain at current block"
        );
        assertGt(newLoanTimestamp, oldLoanTimestamp, "Loan timestamp should be updated");
        assertEq(
            oldCollateralTimestamp + 1,
            collateralTimestampBefore,
            "Collateral timestamp should have advanced by one"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
