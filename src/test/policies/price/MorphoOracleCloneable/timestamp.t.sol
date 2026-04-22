// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableTimestampTest is MorphoOracleCloneableTest {
    function test_givenConsistentTimestamps_returnsTimestamp() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        uint48 actualTimestamp = oracle.timestamp();
        assertEq(actualTimestamp, expectedTimestamp, "Timestamp should match cached timestamp");
    }

    function test_givenOnlyCollateralUsdCacheChanges_returnsCachedPairTimestamp() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        assertEq(
            oracle.timestamp(),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenOnlyLoanUsdCacheChanges_returnsCachedPairTimestamp() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);

        assertEq(
            oracle.timestamp(),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenConsistentTimestamps_gasSnapshot() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        vm.startSnapshotGas("MorphoOracleCloneable.timestamp");
        oracle.timestamp();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenLoanTokenRemovedFromPRICE_reverts() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        priceCache.setAssetApproval(address(loanToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, address(loanToken))
        );
        oracle.timestamp();
    }

    function test_givenCollateralTokenRemovedFromPRICE_reverts() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        priceCache.setAssetApproval(address(collateralToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, address(collateralToken))
        );
        oracle.timestamp();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
