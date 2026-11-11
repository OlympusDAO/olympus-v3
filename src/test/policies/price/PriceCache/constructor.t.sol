// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";

contract PriceCacheConstructorTest is PriceCacheTest {
    // Scenarios: PCACHE-CONSTRUCTOR-P01.
    function test_whenAnyDeployerConstructs(address deployer_, uint8 decimals_) public {
        vm.prank(deployer_);
        PriceCache candidate = new PriceCache(kernel, decimals_, "USD");
        assertEq(address(candidate.kernel()), address(kernel), "constructor Kernel binding");
        assertFalse(candidate.isEnabled(), "initially disabled");
        assertEq(candidate.lastTransitionAt(), 0, "no transition history");
        assertEq(candidate.gracePeriod(), 7 days, "initial grace");
        kernel.executeAction(Actions.ActivatePolicy, address(candidate));
        assertEq(
            candidate.assetDecimals(_unitOfAccount()),
            decimals_,
            "exact constructor scale registered"
        );
        assertEq(
            candidate.assetSymbol(_unitOfAccount()),
            "USD",
            "exact constructor symbol registered"
        );
    }

    // Scenarios: PCACHE-CONSTRUCTOR-N01.
    function test_whenConstructorDecimalBoundarySeeds() public {
        test_whenAnyDeployerConstructs(address(this), 0);
        test_whenAnyDeployerConstructs(address(this), 1);
        test_whenAnyDeployerConstructs(address(this), type(uint8).max);
    }

    // Scenarios: PCACHE-CONSTRUCTOR-N03.
    function test_whenConstructorSymbolContainsArbitraryBytes(
        address deployer_,
        bytes memory symbol_
    ) public {
        vm.assume(symbol_.length > 0 && symbol_.length <= 32);
        vm.prank(deployer_);
        PriceCache candidate = new PriceCache(kernel, 18, string(symbol_));
        kernel.executeAction(Actions.ActivatePolicy, address(candidate));
        assertEq(
            candidate.assetSymbol(_unitOfAccount()),
            string(symbol_),
            "constructor symbol round-trips exact bytes"
        );
    }

    // Scenarios: PCACHE-CONSTRUCTOR-I03.
    function test_whenKernelIsZero_constructorStoresZero() public {
        PriceCache candidate = new PriceCache(Kernel(address(0)), 0, "U");
        assertEq(
            address(candidate.kernel()),
            address(0),
            "inherited adapter accepts supplied zero binding"
        );
        assertFalse(candidate.isEnabled(), "zero-bound deployment starts disabled");
    }

    // Scenarios: PCACHE-CONSTRUCTOR-I01.
    function test_whenConstructorSymbolIsEmpty_reverts() public {
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        new PriceCache(kernel, UNIT_OF_ACCOUNT_DECIMALS, "");
    }

    // Scenarios: PCACHE-CONSTRUCTOR-I02.
    function test_whenConstructorSymbolExceedsMaximumLength_reverts() public {
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        new PriceCache(kernel, UNIT_OF_ACCOUNT_DECIMALS, "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567");
    }

    // Scenarios: PCACHE-CONSTRUCTOR-N02.
    function test_whenConstructorSymbolHasMaximumLength_returnsEntireSymbol() public {
        string memory maximumSymbol = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";
        PriceCache maximumSymbolCache = new PriceCache(
            kernel,
            UNIT_OF_ACCOUNT_DECIMALS,
            maximumSymbol
        );
        kernel.executeAction(Actions.ActivatePolicy, address(maximumSymbolCache));

        assertEq(
            maximumSymbolCache.assetSymbol(_unitOfAccount()),
            maximumSymbol,
            "maximum-length constructor symbol should round-trip"
        );
    }
}
