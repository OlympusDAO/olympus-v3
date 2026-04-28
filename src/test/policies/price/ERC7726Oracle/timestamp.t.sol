// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";

contract ERC7726OracleTimestampTest is ERC7726OracleTest {
    function test_givenConsistentTimestamps_returnsTimestamp() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        uint48 actualTimestamp = oracle.timestamp(address(collateralToken), address(loanToken));
        assertEq(actualTimestamp, expectedTimestamp, "Timestamp should match cached timestamp");
    }

    function test_givenConsistentTimestamps_gasSnapshot() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        vm.startSnapshotGas("ERC7726OracleCloneable.timestamp");
        oracle.timestamp(address(collateralToken), address(loanToken));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenOnlyBaseUsdCacheChanges_returnsCachedPairTimestamp()
        public
        givenOracleIsEnabled
    {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        assertEq(
            oracle.timestamp(address(collateralToken), address(loanToken)),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenOnlyQuoteUsdCacheChanges_returnsCachedPairTimestamp()
        public
        givenOracleIsEnabled
    {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);

        assertEq(
            oracle.timestamp(address(collateralToken), address(loanToken)),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenBaseAssetIsNotApproved_reverts() public {
        address unapprovedBase = makeAddr("UNAPPROVED_BASE");

        vm.expectRevert(abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unapprovedBase));
        oracle.timestamp(unapprovedBase, address(loanToken));
    }

    function test_givenQuoteAssetIsNotApproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unapprovedQuote));
        oracle.timestamp(address(collateralToken), unapprovedQuote);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
