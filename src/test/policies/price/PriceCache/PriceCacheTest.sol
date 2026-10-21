// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity ^0.8.15;

import {Test} from "@forge-std-1.16.2/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

abstract contract PriceCacheTest is Test {
    uint8 internal constant PRICE_DECIMALS = 18;
    uint8 internal constant UNIT_OF_ACCOUNT_DECIMALS = 18;
    string internal constant UNIT_OF_ACCOUNT_SYMBOL = "USD";
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint256 internal constant ASSET_PRICE_USD = 2e18;
    uint256 internal constant QUOTE_PRICE_USD = 1e18;
    uint256 internal constant NON_CONTRACT_PRICE_USD = 3e18;
    uint8 internal constant NON_CONTRACT_DECIMALS = 8;
    uint8 internal constant UPDATED_NON_CONTRACT_DECIMALS = 9;
    uint8 internal constant UPDATED_PRICE_DECIMALS = 9;
    uint48 internal constant LONG_MAX_AGE = 365 days;
    uint48 internal constant SHORT_MAX_AGE = 1 hours;
    uint256 internal constant UPGRADED_ASSET_PRICE_FACTOR = 4;
    uint256 internal constant UPGRADED_QUOTE_PRICE_FACTOR = 2;
    uint256 internal constant DECIMAL_BASE = 10;

    Kernel internal kernel;
    MockPrice internal priceModule;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    PriceCache internal cache;

    MockERC20 internal assetToken;
    MockERC20 internal quoteToken;
    address internal unapprovedAsset;
    address internal admin;
    address internal priceManager;

    bytes32 internal constant PRICE_ADMIN_ROLE = "price_admin";

    function setUp() public virtual {
        admin = makeAddr("ADMIN");
        priceManager = makeAddr("PRICE_MANAGER");
        unapprovedAsset = makeAddr("UNAPPROVED");

        kernel = new Kernel();
        priceModule = new MockPrice(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        cache = new PriceCache(kernel, UNIT_OF_ACCOUNT_DECIMALS, UNIT_OF_ACCOUNT_SYMBOL);

        kernel.executeAction(Actions.InstallModule, address(priceModule));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(cache));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(PRICE_ADMIN_ROLE, priceManager);

        vm.prank(admin);
        cache.enable("");

        assetToken = new MockERC20("Asset Token", "AST", PRICE_DECIMALS);
        quoteToken = new MockERC20("Quote Token", "QTE", PRICE_DECIMALS);

        // Configure approved assets in PRICE mock.
        priceModule.setPrice(address(assetToken), ASSET_PRICE_USD);
        priceModule.setPrice(address(quoteToken), QUOTE_PRICE_USD);
    }

    function _cachePair() internal {
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

    function _setPriceTimestampAtCurrentBlock() internal {
        priceModule.setTimestamp(SafeCast.toUint48(block.timestamp));
    }

    function _deactivateCachePolicy() internal {
        kernel.executeAction(Actions.DeactivatePolicy, address(cache));
    }

    function _unitOfAccount() internal view returns (address) {
        return priceModule.unitOfAccount();
    }

    function _cachedPair() internal view returns (IPriceCache.CachedPrice memory cachedPrice_) {
        return cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    function _assertCachedPriceEq(
        IPriceCache.CachedPrice memory actual_,
        IPriceCache.CachedPrice memory expected_
    ) internal pure {
        assertEq(actual_.assetPriceUsd, expected_.assetPriceUsd, "asset price");
        assertEq(actual_.quotePriceUsd, expected_.quotePriceUsd, "quote price");
        assertEq(actual_.updatedAt, expected_.updatedAt, "updated at");
        assertEq(actual_.roundId, expected_.roundId, "round id");
    }

    function _registerNonContractAsset(address asset_) internal {
        priceModule.registerNonContractAsset(asset_);
    }

    function _setNonContractAssetMetadata(
        address asset_,
        uint8 decimals_,
        string memory symbol_
    ) internal {
        vm.prank(admin);
        cache.setNonContractAssetMetadata(asset_, decimals_, symbol_);
    }

    function _removeNonContractAssetMetadata(address asset_) internal {
        vm.prank(admin);
        cache.removeNonContractAssetMetadata(asset_);
    }

    function _upgradePriceModuleAndReconfigure(
        uint8 decimals_
    ) internal returns (MockPrice newPrice_) {
        newPrice_ = new MockPrice(kernel, decimals_, OBSERVATION_FREQUENCY);
        newPrice_.setPrice(
            address(assetToken),
            UPGRADED_ASSET_PRICE_FACTOR * DECIMAL_BASE ** decimals_
        );
        newPrice_.setPrice(
            address(quoteToken),
            UPGRADED_QUOTE_PRICE_FACTOR * DECIMAL_BASE ** decimals_
        );

        kernel.executeAction(Actions.UpgradeModule, address(newPrice_));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
