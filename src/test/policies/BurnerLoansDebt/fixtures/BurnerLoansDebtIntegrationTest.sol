// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(unused-return)

abstract contract BurnerLoansDebtIntegrationTest is BurnerLoansDebtTest {
    function _openRealDebt(uint128 collateral_, uint128 principal_) internal {
        _openRealDebtFor(_asset, _borrower, collateral_, principal_);
    }

    function _openRealDebtFor(
        MockERC20 asset_,
        address borrower_,
        uint128 collateral_,
        uint128 principal_
    ) internal {
        asset_.mint(borrower_, uint256(collateral_) + 1000e6);
        vm.startPrank(borrower_);
        asset_.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(asset_), collateral_, borrower_);
        _debt.borrow(
            address(asset_),
            principal_,
            borrower_,
            borrower_,
            type(uint256).max,
            address(0)
        );
        vm.stopPrank();
    }

    function _admitSecondAsset() internal returns (MockERC20 asset) {
        asset = new MockERC20("Second", "SECOND", 6);
        _price.setPrice(address(asset), 1e18);
        _admit(address(asset));
    }

    function _assertMarketTotals(
        address asset_,
        uint128 principal_,
        uint256 collateral_,
        uint256 borrowers_
    ) internal view {
        uint32 market = _core.marketId(asset_);
        assertEq(_floan.getMarketPrincipalDue(market), principal_, "FLOAN market principal");
        assertEq(_lens.assetActiveDebtOhm(asset_), principal_, "Lens market principal");
        assertEq(_floan.getMarketCollateral(market), collateral_, "FLOAN market collateral");
        assertEq(_lens.getActiveBorrowers(asset_).length, borrowers_, "Active debt borrowers");
    }

    function _installPriceCache() internal returns (PriceCache cache) {
        cache = new PriceCache(_kernel, 18, "USD");
        _kernel.executeAction(Actions.ActivatePolicy, address(cache));
        cache.enable("");
        _risk.setPriceCache(address(cache));
        _risk.setPriceCacheMaxAge(60);
        cache.cachePrice(address(_ohm), address(_asset));
    }

    function _expireCacheAndHalveCollateralPrice() internal {
        vm.warp(vm.getBlockTimestamp() + 61);
        _price.setTimestamp(SafeCast.toUint48(block.timestamp));
        _price.setPrice(address(_asset), 0.5e18);
    }
}

// forge-lint: disable-end(unused-return)
