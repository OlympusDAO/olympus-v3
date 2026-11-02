// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSnapshotTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-SNAPSHOT-L03.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-L04.
    function test_givenDisabled_whenCalled_reverts(address caller_) public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-L05.
    function test_givenInactive_whenCalled_reverts(address caller_) public givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-L06.
    function test_givenInactiveAndDisabled_whenCalled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-L03.
    function test_givenReEnabled_whenCalled(address caller_) public givenReEnabled {
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-I01.
    function test_givenNoCache_whenPricesRead(address caller_) public {
        uint256 count = _cache.cachePriceIfNecessaryCallCount();
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
        assertEq(_cache.cachePriceIfNecessaryCallCount(), count, "no refresh on direct branch");
    }

    // Scenarios: BLRISK-SNAPSHOT-L01.
    function test_givenInactiveCache_whenPricesRead(address caller_) public givenCache {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        uint256 count = _cache.cachePriceIfNecessaryCallCount();
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
        assertEq(_cache.cachePriceIfNecessaryCallCount(), count, "no refresh on direct branch");
    }

    // Scenarios: BLRISK-SNAPSHOT-L02.
    function test_givenDisabledCache_whenPricesRead(address caller_) public givenCache {
        _cache.disable("");
        uint256 count = _cache.cachePriceIfNecessaryCallCount();
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
        assertEq(_cache.cachePriceIfNecessaryCallCount(), count, "no refresh on direct branch");
    }

    function _cached(uint256 ohm_, uint256 asset_, uint48 at_) private {
        IPriceCache.CachedPrice memory cached = IPriceCache.CachedPrice(ohm_, asset_, at_, 1);
        vm.mockCall(
            address(_cache),
            abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
            abi.encode(cached)
        );
    }

    // Scenarios: BLRISK-SNAPSHOT-I02.
    function test_givenCacheTimestampZero_whenPricesRead(address caller_) public givenCache {
        _cached(3e18, 4e18, 0);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-I03.
    function test_givenCachedOhmZero_whenPricesRead_reverts(address caller_) public givenCache {
        _cached(0, 4e18, uint48(block.timestamp));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I04.
    function test_givenCachedCollateralZero_whenPricesRead_reverts(
        address caller_
    ) public givenCache {
        _cached(3e18, 0, uint48(block.timestamp));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I05.
    function test_givenDirectOhmZero_whenPricesRead_reverts(address caller_) public {
        _mockDirectPrice(address(_ohm), 0, uint48(block.timestamp));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I06.
    function test_givenDirectCollateralZero_whenPricesRead_reverts(address caller_) public {
        _mockDirectPrice(address(_asset), 0, uint48(block.timestamp));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I07.
    function test_givenOhmTimestampZero_whenPricesRead_reverts(address caller_) public {
        _mockDirectPrice(address(_ohm), 1e18, 0);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I08.
    function test_givenOhmStale_whenPricesRead_reverts(address caller_) public {
        _mockDirectPrice(address(_ohm), 1e18, uint48(block.timestamp - 8 hours - 1));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I09.
    function test_givenCollateralTimestampZero_whenPricesRead_reverts(address caller_) public {
        _mockDirectPrice(address(_asset), 2e18, 0);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I10.
    function test_givenCollateralStale_whenPricesRead_reverts(address caller_) public {
        _mockDirectPrice(address(_asset), 2e18, uint48(block.timestamp - 8 hours - 1));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-I11.
    function test_givenZeroBacking_whenPricesRead_reverts(address caller_) public {
        _oracle.setBacking(0);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-P01.
    function test_givenCacheFresh_whenPricesRead(address caller_) public givenCache {
        _cached(3e18, 4e18, uint48(block.timestamp - 59));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 3e18, 4e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-P02.
    function test_givenCacheAtDeadline_whenPricesRead(address caller_) public givenCache {
        _cached(3e18, 4e18, uint48(block.timestamp - 60));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 3e18, 4e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-P03.
    function test_givenCacheExpired_whenPricesRead(address caller_) public givenCache {
        _cached(3e18, 4e18, uint48(block.timestamp - 61));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-P04.
    function test_givenCacheFuture_whenPricesRead(address caller_) public givenCache {
        _cached(3e18, 4e18, uint48(block.timestamp + 1));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 3e18, 4e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-P05.
    function test_givenOhmAtObservationDeadline_whenPricesRead(address caller_) public {
        _mockDirectPrice(address(_ohm), 1e18, uint48(block.timestamp - 8 hours));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-P06.
    function test_givenCollateralAtObservationDeadline_whenPricesRead(address caller_) public {
        _mockDirectPrice(address(_asset), 2e18, uint48(block.timestamp - 8 hours));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBackingUses0PriceDecimals(uint256 backing_, address caller_) public {
        uint256 backing = bound(backing_, 1, type(uint256).max);
        _price.setPriceDecimals(0);
        _oracle.setBacking(backing);
        vm.expectCall(
            address(_oracle),
            abi.encodeCall(IOlympusBackingOracle.backing, ()),
            uint64(1)
        );
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            (backing - 1) / 1000000000000000000 + 1
        );
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBacking0BoundarySeeds(address caller_) public {
        _price.setPriceDecimals(0);
        _oracle.setBacking(1);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1);
        _oracle.setBacking(999999999999999999);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1);
        _oracle.setBacking(1000000000000000000);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1);
        _oracle.setBacking(1000000000000000001);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 2);
        _oracle.setBacking(
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            115792089237316195423570985008687907853269984665640564039458
        );
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBackingUses6PriceDecimals(uint256 backing_, address caller_) public {
        uint256 backing = bound(backing_, 1, type(uint256).max);
        _price.setPriceDecimals(6);
        _oracle.setBacking(backing);
        vm.expectCall(
            address(_oracle),
            abi.encodeCall(IOlympusBackingOracle.backing, ()),
            uint64(1)
        );
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            (backing - 1) / 1000000000000 + 1
        );
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBacking6BoundarySeeds(address caller_) public {
        _price.setPriceDecimals(6);
        _oracle.setBacking(1);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1);
        _oracle.setBacking(999999999999999999);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1000000);
        _oracle.setBacking(1000000000000000000);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1000000);
        _oracle.setBacking(1000000000000000001);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1000001);
        _oracle.setBacking(
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            115792089237316195423570985008687907853269984665640564039457584008
        );
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBackingUses18PriceDecimals(uint256 backing_, address caller_) public {
        uint256 backing = bound(backing_, 1, type(uint256).max);
        _price.setPriceDecimals(18);
        _oracle.setBacking(backing);
        vm.expectCall(
            address(_oracle),
            abi.encodeCall(IOlympusBackingOracle.backing, ()),
            uint64(1)
        );
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, backing);
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBacking18BoundarySeeds(address caller_) public {
        _price.setPriceDecimals(18);
        _oracle.setBacking(1);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1);
        _oracle.setBacking(999999999999999999);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 999999999999999999);
        _oracle.setBacking(1000000000000000000);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1000000000000000000);
        _oracle.setBacking(1000000000000000001);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1000000000000000001);
        _oracle.setBacking(
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBackingUses36PriceDecimals(uint256 backing_, address caller_) public {
        uint256 backing = bound(backing_, 1, type(uint256).max / 1000000000000000000);
        _price.setPriceDecimals(36);
        _oracle.setBacking(backing);
        vm.expectCall(
            address(_oracle),
            abi.encodeCall(IOlympusBackingOracle.backing, ()),
            uint64(1)
        );
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, backing * 1000000000000000000);
    }

    // Scenarios: BLRISK-SNAPSHOT-N01.
    function test_whenBacking36BoundarySeeds(address caller_) public {
        _price.setPriceDecimals(36);
        _oracle.setBacking(1);
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1000000000000000000);
        _oracle.setBacking(999999999999999999);
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            999999999999999999000000000000000000
        );
        _oracle.setBacking(1000000000000000000);
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            1000000000000000000000000000000000000
        );
        _oracle.setBacking(1000000000000000001);
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            1000000000000000001000000000000000000
        );
        _oracle.setBacking(115792089237316195423570985008687907853269984665640564039457);
        vm.prank(caller_);
        _assertSnapshot(
            _risk.snapshot(address(_asset)),
            1e18,
            2e18,
            115792089237316195423570985008687907853269984665640564039457000000000000000000
        );
    }

    function _unsupportedScale(uint8 decimals_, address caller_) private {
        _price.setPriceDecimals(decimals_);
        vm.expectRevert(
            abi.encodeWithSelector(LoanMath.LoanMath_UnsupportedDecimals.selector, decimals_)
        );
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-N02.
    function test_whenPriceScaleCannotFit_reverts(uint8 decimals_, address caller_) public {
        _unsupportedScale(uint8(bound(decimals_, 78, type(uint8).max)), caller_);
    }

    // Scenarios: BLRISK-SNAPSHOT-N02.
    function test_whenUnsupportedScaleBoundaries_reverts(address caller_) public {
        _unsupportedScale(78, caller_);
        _unsupportedScale(type(uint8).max, caller_);
    }

    // Scenarios: BLRISK-SNAPSHOT-P07.
    function test_whenBackingConversionOverflows_reverts(address caller_) public {
        _price.setPriceDecimals(36);
        _oracle.setBacking(type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-P08.
    function test_givenCacheFailure_whenPricesRead_reverts(address caller_) public givenCache {
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(DependencyReadFailed.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-P09.
    function test_givenPriceFailure_whenPricesRead_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_price),
            abi.encodeWithSelector(bytes4(keccak256("getPrice(address,uint8)"))),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(DependencyReadFailed.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-P10.
    function test_givenOracleFailure_whenPricesRead_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeCall(IOlympusBackingOracle.backing, ()),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(DependencyReadFailed.selector);
        vm.prank(caller_);
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BLRISK-SNAPSHOT-P11.
    function test_givenPriceModuleUpgrade_whenPricesRead(address caller_) public {
        _assertSnapshot(_risk.snapshot(address(_asset)), 1e18, 2e18, 1e18);
        MockPrice replacement = new MockPrice(_kernel, 18, 8 hours);
        replacement.setPrice(address(_ohm), 7e18);
        replacement.setPrice(address(_asset), 8e18);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.prank(caller_);
        _assertSnapshot(_risk.snapshot(address(_asset)), 7e18, 8e18, 1e18);
    }
}
