// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract CachePriceCaller {
    IOracleFactory public factory;

    constructor(IOracleFactory factory_) {
        factory = factory_;
    }

    function cachePrice() external {
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
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        MorphoOracleCloneable(address(oracle)).cachePrice();
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
        (, , uint48 oldPairTimestamp, uint80 oldRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        MorphoOracleCloneable(address(oracle)).cachePrice();

        (, , uint48 newPairTimestamp, uint80 newRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        assertGt(newPairTimestamp, oldPairTimestamp, "Pair timestamp should be re-cached");
        assertGt(newRoundId, oldRoundId, "Pair round ID should increment");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache() public {
        (, , uint48 oldPairTimestamp, uint80 oldRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, , uint48 newPairTimestamp, uint80 newRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        assertEq(newPairTimestamp, oldPairTimestamp, "Pair timestamp should not be re-cached");
        assertEq(newRoundId, oldRoundId, "Pair round ID should not change");
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryCaches() public {
        (, , uint48 oldPairTimestamp, uint80 oldRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, , uint48 newPairTimestamp, uint80 newRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        assertGt(newPairTimestamp, oldPairTimestamp, "Pair timestamp should be re-cached");
        assertGt(newRoundId, oldRoundId, "Pair round ID should increment");
    }

    function test_whenOnlyCollateralUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair()
        public
    {
        (, , uint48 oldPairTimestamp, uint80 oldRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(collateralToken), priceModule.unitOfAccount());

        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, , uint48 newPairTimestamp, uint80 newRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        assertEq(newPairTimestamp, oldPairTimestamp, "Pair timestamp should remain unchanged");
        assertEq(newRoundId, oldRoundId, "Pair round ID should remain unchanged");
    }

    function test_whenOnlyLoanUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair() public {
        (, , uint48 oldPairTimestamp, uint80 oldRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(loanToken), priceModule.unitOfAccount());

        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        (, , uint48 newPairTimestamp, uint80 newRoundId) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        assertEq(newPairTimestamp, oldPairTimestamp, "Pair timestamp should remain unchanged");
        assertEq(newRoundId, oldRoundId, "Pair round ID should remain unchanged");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
