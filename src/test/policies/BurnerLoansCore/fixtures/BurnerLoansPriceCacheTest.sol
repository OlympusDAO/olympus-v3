// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {Policy} from "src/Kernel.sol";
import {BurnerLoansCallbackCache} from "src/test/mocks/BurnerLoansCallbackCache.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract BurnerLoansPriceCacheTest is BurnerLoansModularTest {
    BurnerLoansCallbackCache internal _cache;

    function setUp() public virtual override {
        super.setUp();
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _cache = new BurnerLoansCallbackCache(address(_kernel));
        _cache.setPriceModule(address(_price));
        _cache.setUsdPrice(address(_asset), 1e18);
        _cache.setUsdPrice(address(_ohm), 1e18);
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.isPolicyActive, (Policy(address(_cache)))),
            abi.encode(true)
        );
        _risk.setPriceCache(address(_cache));
        _cache.cachePrice(address(_ohm), address(_asset));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(0))
        );
        vm.prank(_borrower);
        _core.setAuthorization(address(_cache), type(uint48).max);
        _asset.mint(address(_cache), 100e6);
        vm.prank(address(_cache));
        _asset.approve(address(_core), type(uint256).max);
    }
}
