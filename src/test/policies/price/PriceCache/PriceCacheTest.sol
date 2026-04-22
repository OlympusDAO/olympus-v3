// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

abstract contract PriceCacheTest is Test {
    uint8 internal constant PRICE_DECIMALS = 18;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;

    Kernel internal kernel;
    MockPrice internal priceModule;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    PriceCache internal cache;

    MockERC20 internal assetToken;
    MockERC20 internal quoteToken;
    address internal unapprovedAsset;
    address internal admin;

    function setUp() public virtual {
        admin = makeAddr("ADMIN");
        unapprovedAsset = makeAddr("UNAPPROVED");

        kernel = new Kernel();
        priceModule = new MockPrice(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        cache = new PriceCache(kernel);

        kernel.executeAction(Actions.InstallModule, address(priceModule));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(cache));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);

        vm.prank(admin);
        cache.enable("");

        assetToken = new MockERC20("Asset Token", "AST", 18);
        quoteToken = new MockERC20("Quote Token", "QTE", 18);

        // Configure approved assets in PRICE mock.
        priceModule.setPrice(address(assetToken), 2e18);
        priceModule.setPrice(address(quoteToken), 1e18);
    }

    function _cachePair() internal {
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

    function _unitOfAccount() internal view returns (address) {
        return priceModule.unitOfAccount();
    }

    function _cachedPair() internal view returns (IPriceCache.CachedPrice memory cachedPrice_) {
        return cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    function _upgradePriceModuleAndReconfigure(
        uint8 decimals_
    ) internal returns (MockPrice newPrice_) {
        newPrice_ = new MockPrice(kernel, decimals_, OBSERVATION_FREQUENCY);
        newPrice_.setPrice(address(assetToken), 4 * 10 ** decimals_);
        newPrice_.setPrice(address(quoteToken), 2 * 10 ** decimals_);

        kernel.executeAction(Actions.UpgradeModule, address(newPrice_));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
