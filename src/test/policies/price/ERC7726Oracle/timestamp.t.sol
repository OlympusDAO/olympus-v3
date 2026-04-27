// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

contract ERC7726OracleTimestampTest is ERC7726OracleTest {
    // given the pair has a consistent cached timestamp
    //  [X] it returns the timestamp

    function test_givenConsistentTimestamps_returnsTimestamp() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        vm.warp(block.timestamp + 1);
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

    // given only the base/USD cache changes
    //  [X] it returns the cached pair timestamp

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

    // given only the quote/USD cache changes
    //  [X] it returns the cached pair timestamp

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

    // given the base asset is not approved
    //  [X] it reverts

    function test_givenBaseAssetIsNotApproved_reverts() public {
        address unapprovedBase = makeAddr("UNAPPROVED_BASE");

        vm.expectRevert(abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unapprovedBase));
        oracle.timestamp(unapprovedBase, address(loanToken));
    }

    // given the quote asset is not approved
    //  [X] it reverts

    function test_givenQuoteAssetIsNotApproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unapprovedQuote));
        oracle.timestamp(address(collateralToken), unapprovedQuote);
    }

    // given the base asset is unit of account
    //  [X] it returns the timestamp

    function test_givenBaseAssetIsUnitOfAccount_returnsTimestamp() public givenOracleIsEnabled {
        priceCache.cachePrice(UNIT_OF_ACCOUNT, address(loanToken));
        vm.warp(block.timestamp + 1);

        uint48 expectedTimestamp = priceCache
            .getCachedPrice(UNIT_OF_ACCOUNT, address(loanToken))
            .updatedAt;
        assertEq(
            oracle.timestamp(UNIT_OF_ACCOUNT, address(loanToken)),
            expectedTimestamp,
            "Timestamp should work for the unit of account"
        );
    }

    // given the quote asset is unit of account
    //  [X] it returns the timestamp

    function test_givenQuoteAssetIsUnitOfAccount_returnsTimestamp() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);
        vm.warp(block.timestamp + 1);

        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), UNIT_OF_ACCOUNT)
            .updatedAt;
        assertEq(
            oracle.timestamp(address(collateralToken), UNIT_OF_ACCOUNT),
            expectedTimestamp,
            "Timestamp should work for the unit of account"
        );
    }

    // given the base asset is a registered non-contract asset
    //  given non-contract asset decimals are not set
    //   [X] it reverts
    //  given non-contract asset decimals are set
    //   [X] it returns the timestamp
    //  given the asset is no longer approved in PRICE
    //   [X] it reverts

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreNotSet_reverts()
        public
        givenOracleIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));
        priceCache.removeNonContractAssetMetadata(registeredNonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                registeredNonContractAsset
            )
        );
        oracle.timestamp(registeredNonContractAsset, address(loanToken));
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreSet_returnsTimestamp()
        public
        givenOracleIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));
        vm.warp(block.timestamp + 1);

        uint48 expectedTimestamp = priceCache
            .getCachedPrice(registeredNonContractAsset, address(loanToken))
            .updatedAt;
        assertEq(
            oracle.timestamp(registeredNonContractAsset, address(loanToken)),
            expectedTimestamp,
            "Timestamp should work for registered non-contract assets"
        );
    }

    // given the quote asset is a registered non-contract asset
    //  given non-contract asset decimals are not set
    //   [X] it reverts
    //  given non-contract asset decimals are set
    //   [X] it returns the timestamp
    //  given the asset is no longer approved in PRICE
    //   [X] it reverts

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreNotSet_reverts()
        public
        givenOracleIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);
        priceCache.removeNonContractAssetMetadata(registeredNonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                registeredNonContractAsset
            )
        );
        oracle.timestamp(address(collateralToken), registeredNonContractAsset);
    }

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreSet_returnsTimestamp()
        public
        givenOracleIsEnabled
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);
        vm.warp(block.timestamp + 1);

        uint48 expectedTimestamp = priceCache
            .getCachedPrice(address(collateralToken), registeredNonContractAsset)
            .updatedAt;
        assertEq(
            oracle.timestamp(address(collateralToken), registeredNonContractAsset),
            expectedTimestamp,
            "Timestamp should work for registered non-contract assets"
        );
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenAssetIsNoLongerApprovedInPRICE_reverts()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));
        priceCache.setAssetApproval(registeredNonContractAsset, false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, registeredNonContractAsset)
        );
        oracle.timestamp(registeredNonContractAsset, address(loanToken));
    }

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenAssetIsNoLongerApprovedInPRICE_reverts()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);
        priceCache.setAssetApproval(registeredNonContractAsset, false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, registeredNonContractAsset)
        );
        oracle.timestamp(address(collateralToken), registeredNonContractAsset);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
