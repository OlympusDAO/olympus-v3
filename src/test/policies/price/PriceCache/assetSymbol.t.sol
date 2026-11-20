// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";
import {MockStaticMetadataToken} from "./fixtures/MockStaticMetadataToken.sol";

contract PriceCacheAssetSymbolTest is PriceCacheTest {
    // Scenarios: PCACHE-ASSET-SYMBOL-P01.
    function test_givenAssetIsContract_returnsERC20Symbol() public view {
        assertEq(
            cache.assetSymbol(address(assetToken)),
            assetToken.symbol(),
            "Contract asset symbol should come from the token"
        );
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-P02.
    function test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredSymbol() public view {
        assertEq(
            cache.assetSymbol(_unitOfAccount()),
            UNIT_OF_ACCOUNT_SYMBOL,
            "Unit of account symbol should be initialized at deployment"
        );
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-I01.
    function test_givenAssetIsRegisteredNonContractAsset_givenSymbolIsNotRegistered_reverts()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, NON_CONTRACT_PRICE_USD);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                nonContractAsset
            )
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.assetSymbol(nonContractAsset);
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-P03.
    function test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractSymbol()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        MockStaticMetadataToken tokenWithDifferentMetadata = new MockStaticMetadataToken();
        vm.etch(nonContractAsset, address(tokenWithDifferentMetadata).code);

        assertEq(
            cache.assetSymbol(nonContractAsset),
            "LATE",
            "Contract symbol should take precedence once code exists at the address"
        );
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-A01.
    function test_whenAnyCallerReadsAllMetadataKinds(address caller_) public {
        address nca = _metadataAsset();
        vm.startPrank(caller_);
        assertEq(cache.assetSymbol(address(assetToken)), "AST", "token metadata");
        assertEq(cache.assetSymbol(_unitOfAccount()), "USD", "unit metadata");
        assertEq(cache.assetSymbol(nca), "NCA", "registry metadata");
        vm.stopPrank();
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-L01.
    function test_givenInactivePaused_whenMetadataQueried(
        address caller_
    ) public givenCachePaused givenCacheInactive {
        vm.prank(caller_);
        assertEq(cache.assetSymbol(address(assetToken)), "AST", "metadata remains readable");
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-I03.
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetNotRegistered.selector,
                address(0)
            )
        );
        cache.assetSymbol(address(0));
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-I02.
    function test_whenNonContractAssetIsUnknown_reverts() public {
        address unknown = makeAddr("unknownMetadataAsset");
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetNotRegistered.selector,
                unknown
            )
        );
        cache.assetSymbol(unknown);
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-T01.
    function test_whenTokenMetadataReverts_reverts() public {
        vm.mockCallRevert(
            address(assetToken),
            abi.encodeWithSignature("symbol()"),
            abi.encodeWithSelector(MetadataReadFailed.selector)
        );
        vm.expectRevert(MetadataReadFailed.selector);
        cache.assetSymbol(address(assetToken));
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-T02.
    function test_whenTokenMetadataAbiIsMalformed_reverts() public {
        vm.mockCall(address(assetToken), abi.encodeWithSignature("symbol()"), bytes(""));
        _expectMetadataAbiFailure();
        cache.assetSymbol(address(assetToken));
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-N01.
    function test_whenTokenSymbolHasArbitraryBytes(address caller_, string memory symbol_) public {
        vm.mockCall(address(assetToken), abi.encodeWithSignature("symbol()"), abi.encode(symbol_));
        vm.prank(caller_);
        assertEq(
            cache.assetSymbol(address(assetToken)),
            symbol_,
            "exact external token symbol without registry length restriction"
        );
    }

    // Scenarios: PCACHE-ASSET-SYMBOL-N01.
    function test_whenTokenSymbolLengthBoundarySeeds() public {
        test_whenTokenSymbolHasArbitraryBytes(address(this), "");
        test_whenTokenSymbolHasArbitraryBytes(address(this), "X");
        test_whenTokenSymbolHasArbitraryBytes(address(this), "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
