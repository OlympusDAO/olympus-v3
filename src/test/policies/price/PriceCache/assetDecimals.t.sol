// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";
import {MockStaticMetadataToken} from "./fixtures/MockStaticMetadataToken.sol";

contract PriceCacheAssetDecimalsTest is PriceCacheTest {
    // Scenarios: PCACHE-ASSET-DECIMALS-P01.
    function test_givenAssetIsContract_returnsERC20Decimals() public view {
        assertEq(
            cache.assetDecimals(address(assetToken)),
            assetToken.decimals(),
            "Contract asset decimals should come from the token"
        );
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-P02.
    function test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredScale() public view {
        assertEq(
            cache.assetDecimals(_unitOfAccount()),
            UNIT_OF_ACCOUNT_DECIMALS,
            "Unit of account decimals should be initialized at deployment"
        );
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-I01.
    function test_givenAssetIsRegisteredNonContractAsset_givenDecimalsAreNotRegistered_reverts()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, NON_CONTRACT_PRICE_USD);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nonContractAsset
            )
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.assetDecimals(nonContractAsset);
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-I02.
    function test_givenAssetIsUnregisteredNonContractAsset_reverts() public {
        address unregisteredNonContractAsset = makeAddr("UNREGISTERED_NON_CONTRACT_ASSET");

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetNotRegistered.selector,
                unregisteredNonContractAsset
            )
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.assetDecimals(unregisteredNonContractAsset);
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-P03.
    function test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractDecimals()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        assertEq(
            cache.assetDecimals(nonContractAsset),
            NON_CONTRACT_DECIMALS,
            "Registered metadata decimals should be returned before code exists"
        );

        MockStaticMetadataToken tokenWithDifferentDecimals = new MockStaticMetadataToken();
        vm.etch(nonContractAsset, address(tokenWithDifferentDecimals).code);

        assertEq(
            cache.assetDecimals(nonContractAsset),
            6,
            "Contract decimals should take precedence once code exists at the address"
        );
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-A01.
    function test_whenAnyCallerReadsAllMetadataKinds(address caller_) public {
        address nca = _metadataAsset();
        vm.startPrank(caller_);
        assertEq(cache.assetDecimals(address(assetToken)), 18, "token metadata");
        assertEq(cache.assetDecimals(_unitOfAccount()), 18, "unit metadata");
        assertEq(cache.assetDecimals(nca), 8, "registry metadata");
        vm.stopPrank();
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-L01.
    function test_givenInactivePaused_whenMetadataQueried(
        address caller_
    ) public givenCachePaused givenCacheInactive {
        vm.prank(caller_);
        assertEq(cache.assetDecimals(address(assetToken)), 18, "metadata remains readable");
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-I03.
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetNotRegistered.selector,
                address(0)
            )
        );
        cache.assetDecimals(address(0));
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-T01.
    function test_whenTokenMetadataReverts_reverts() public {
        vm.mockCallRevert(
            address(assetToken),
            abi.encodeWithSignature("decimals()"),
            abi.encodeWithSelector(MetadataReadFailed.selector)
        );
        vm.expectRevert(MetadataReadFailed.selector);
        cache.assetDecimals(address(assetToken));
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-T02.
    function test_whenTokenMetadataAbiIsMalformed_reverts() public {
        vm.mockCall(address(assetToken), abi.encodeWithSignature("decimals()"), bytes(""));
        _expectMetadataAbiFailure();
        cache.assetDecimals(address(assetToken));
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-N01.
    function test_whenTokenDecimalsSpanUint8(address caller_, uint8 decimals_) public {
        vm.mockCall(
            address(assetToken),
            abi.encodeWithSignature("decimals()"),
            abi.encode(decimals_)
        );
        vm.prank(caller_);
        assertEq(cache.assetDecimals(address(assetToken)), decimals_, "exact token decimals");
    }

    // Scenarios: PCACHE-ASSET-DECIMALS-N01.
    function test_whenTokenDecimalsAtBoundarySeeds() public {
        test_whenTokenDecimalsSpanUint8(address(this), 0);
        test_whenTokenDecimalsSpanUint8(address(this), 1);
        test_whenTokenDecimalsSpanUint8(address(this), type(uint8).max);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
