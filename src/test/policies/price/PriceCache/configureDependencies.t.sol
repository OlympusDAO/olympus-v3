// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";
import {Policy, Keycode} from "src/Kernel.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

contract PriceCacheConfigureDependenciesTest is PriceCacheLifecycleTest {
    bytes5 private constant _PRICE_KEYCODE = "PRICE";
    bytes5 private constant _ROLES_KEYCODE = "ROLES";

    // Scenarios: PCACHE-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured(address caller_) public {
        bytes32 beforeState = _preservedState();
        vm.prank(caller_);
        Keycode[] memory dependencies = cache.configureDependencies();
        assertEq(dependencies.length, 2, "dependency count");
        assertEq(Keycode.unwrap(dependencies[1]), _ROLES_KEYCODE, "ROLES dependency");
        assertEq(Keycode.unwrap(dependencies[0]), _PRICE_KEYCODE, "PRICE dependency");
        assertEq(address(cache.PRICE()), address(priceModule), "cached PRICE binding");
        assertEq(address(cache.ROLES()), address(roles), "cached ROLES binding");
        assertEq(_preservedState(), beforeState, "reconfiguration preserves existing data");
    }

    // Scenarios: PCACHE-DEPENDENCIES-P02.
    function test_givenUnconfigured_whenDependenciesConfigured(address caller_) public {
        _freshSubject(false);
        vm.prank(caller_);
        Keycode[] memory dependencies = cache.configureDependencies();
        assertEq(dependencies.length, 2, "dependency count");
        assertEq(address(cache.ROLES()), address(roles), "ROLES binding initialized");
        assertFalse(cache.isEnabled(), "configuration does not enable");
        assertFalse(cache.isActive(), "configuration does not activate");
    }

    // Scenarios: PCACHE-DEPENDENCIES-I01.
    function test_givenMissingRoles_whenConfigured_reverts() public {
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", _ROLES_KEYCODE),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, _ROLES_KEYCODE)
        );
        cache.configureDependencies();
    }

    // Scenarios: PCACHE-DEPENDENCIES-L01.
    function test_givenPaused_whenDependenciesConfigured(
        address caller_
    ) public givenLifecycleDisabled {
        bytes32 beforeState = _preservedState();
        vm.prank(caller_);
        Keycode[] memory dependencies = cache.configureDependencies();
        assertEq(dependencies.length, 2, "both dependencies returned");
        assertEq(
            _preservedState(),
            beforeState,
            "configuration and lifecycle-independent data preserved"
        );
    }

    // Scenarios: PCACHE-DEPENDENCIES-L02.
    function test_givenInactive_whenDependenciesConfigured(
        address caller_
    ) public givenLifecycleInactive {
        bytes32 beforeState = _preservedState();
        vm.prank(caller_);
        Keycode[] memory dependencies = cache.configureDependencies();
        assertEq(dependencies.length, 2, "both dependencies returned");
        assertEq(
            _preservedState(),
            beforeState,
            "configuration and lifecycle-independent data preserved"
        );
    }

    // Scenarios: PCACHE-DEPENDENCIES-I02.
    function test_whenRolesMajorUnsupported_reverts(uint8 major_, uint8 minor_) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, minor_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_UnsupportedModuleVersion.selector,
                _ROLES_KEYCODE,
                major_,
                minor_
            )
        );
        cache.configureDependencies();
    }

    // Scenarios: PCACHE-DEPENDENCIES-I02.
    function test_whenRolesMajorBoundarySeeds_reverts() public {
        test_whenRolesMajorUnsupported_reverts(0, type(uint8).max);
        test_whenRolesMajorUnsupported_reverts(2, type(uint8).max);
        test_whenRolesMajorUnsupported_reverts(type(uint8).max, type(uint8).max);
    }

    // Scenarios: PCACHE-DEPENDENCIES-I03.
    function test_givenPriceModuleMissing_whenConfigured_reverts() public {
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", _PRICE_KEYCODE),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, _PRICE_KEYCODE)
        );
        cache.configureDependencies();
    }

    // Scenarios: PCACHE-DEPENDENCIES-D01.
    function test_whenPriceMajorZero_reverts(uint8 minor_) public {
        vm.mockCall(
            address(priceModule),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(0), minor_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_UnsupportedModuleVersion.selector,
                _PRICE_KEYCODE,
                uint8(0),
                minor_
            )
        );
        cache.configureDependencies();
    }

    // Scenarios: PCACHE-DEPENDENCIES-D01.
    function test_whenPriceOneMinorBelowTwo_reverts(uint8 minor_) public {
        uint8 minor = SafeCast.toUint8(bound(minor_, 0, 1));
        vm.mockCall(
            address(priceModule),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(1), minor)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_UnsupportedModuleVersion.selector,
                _PRICE_KEYCODE,
                uint8(1),
                minor
            )
        );
        cache.configureDependencies();
    }

    // Scenarios: PCACHE-DEPENDENCIES-D02.
    function test_givenPriceInterfaceMissing_whenConfigured_reverts() public {
        vm.mockCall(
            address(priceModule),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IPRICEv2).interfaceId),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_UnsupportedModuleInterface.selector,
                _PRICE_KEYCODE,
                type(IPRICEv2).interfaceId
            )
        );
        cache.configureDependencies();
    }

    // Scenarios: PCACHE-DEPENDENCIES-P03.
    function test_whenPriceUpgradeInvalidatesEveryOrientation() public {
        address nca = _metadataAsset();
        cache.cachePrice(address(assetToken), address(quoteToken));
        cache.cachePrice(address(assetToken), nca);
        _upgradePriceModuleAndReconfigure(18);
        priceModule = MockPrice(address(cache.PRICE()));
        priceModule.registerNonContractAsset(nca);
        priceModule.setPrice(nca, 3e18);
        _assertUncached(address(assetToken), address(quoteToken));
        _assertUncached(address(quoteToken), address(assetToken));
        _assertUncached(address(assetToken), nca);
        _assertUncached(nca, address(assetToken));
        cache.cachePrice(address(assetToken), address(quoteToken));
        assertEq(_cachedPair().roundId, 1, "new epoch starts new round");
    }

    // Scenarios: PCACHE-DEPENDENCIES-P04.
    function test_whenRepeatedConfigurationPreservesCustomUnitMetadata() public {
        address unit = _unitOfAccount();
        _setNonContractAssetMetadata(unit, 6, "CUSTOM");
        cache.cachePrice(address(assetToken), unit);
        IPriceCache.CachedPrice memory beforeSnapshot = cache.getCachedPrice(
            address(assetToken),
            unit
        );
        Keycode[] memory dependencies = cache.configureDependencies();
        assertEq(dependencies.length, 2, "dependency count");
        assertEq(cache.assetDecimals(unit), 6, "custom unit decimals retained");
        assertEq(cache.assetSymbol(unit), "CUSTOM", "custom unit symbol retained");
        _assertCachedPriceEq(cache.getCachedPrice(address(assetToken), unit), beforeSnapshot);
    }
}
