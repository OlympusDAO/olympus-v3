// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
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

contract MorphoOracleCloneableCachePriceTest is MorphoOracleCloneableTest {
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

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
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

    function test_whenPriceCachePolicyIsDisabled_cachePriceReverts() public {
        priceCache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
