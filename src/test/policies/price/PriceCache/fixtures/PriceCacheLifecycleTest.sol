// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacheTest} from "../PriceCacheTest.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {PolicyLifecycleTest} from "src/test/policies/utils/PolicyLifecycleTest.sol";

abstract contract PriceCacheLifecycleTest is PriceCacheTest, PolicyLifecycleTest {
    bytes32[] private _cacheSlots;

    function setUp() public virtual override {
        super.setUp();
        _lifecycleTarget = address(cache);
        _lifecycleKernel = kernel;
        _lifecycleRoles = roles;
        _lifecycleRolesAdmin = rolesAdmin;
        _lifecycleAdmin = admin;
        _lifecycleExecutor = address(this);
        _lifecycleEmergency = makeAddr("emergency");
        _lifecycleSecondary = priceManager;
        _lifecycleSecondaryRole = PRICE_ADMIN_ROLE;
        _grantLifecycleRole(EMERGENCY_ROLE, _lifecycleEmergency);

        address nonContractAsset = makeAddr("nonContractAsset");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, NON_CONTRACT_PRICE_USD);

        // Remember authoritative metadata and snapshot slots, including asset invalidation epochs.
        vm.record();
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");
        _cachePair();
        _cachePair();
        cache.cachePrice(nonContractAsset, address(quoteToken));
        cache.cachePrice(address(assetToken), _unitOfAccount());
        (, _cacheSlots) = vm.accesses(address(cache));
    }

    function _freshSubject(bool activate_) internal {
        cache = new PriceCache(kernel, UNIT_OF_ACCOUNT_DECIMALS, UNIT_OF_ACCOUNT_SYMBOL);
        _lifecycleTarget = address(cache);
        if (activate_) _setMembership(true);
    }

    function _preservedState() internal view override returns (bytes32) {
        bytes32[] memory values = new bytes32[](_cacheSlots.length);
        for (uint256 i; i < values.length; ++i) {
            values[i] = vm.load(address(cache), _cacheSlots[i]);
        }
        return
            keccak256(
                abi.encode(
                    cache.kernel(),
                    cache.PRICE(),
                    cache.ROLES(),
                    cache.gracePeriod(),
                    values
                )
            );
    }
}
