// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {PriceCacherTaskTest} from "../PriceCacherTaskTest.sol";
import {PriceCacherTask} from "src/policies/PriceCacherTask.sol";
import {PolicyLifecycleTest} from "src/test/policies/utils/PolicyLifecycleTest.sol";

abstract contract PriceCacherTaskLifecycleTest is PriceCacherTaskTest, PolicyLifecycleTest {
    function setUp() public virtual override {
        super.setUp();
        _lifecycleTarget = address(cacher);
        _lifecycleKernel = kernel;
        _lifecycleRoles = roles;
        _lifecycleRolesAdmin = rolesAdmin;
        _lifecycleAdmin = admin;
        _lifecycleExecutor = admin;
        _lifecycleEmergency = emergency;
        _lifecycleSecondary = makeAddr("priceAdmin");
        _lifecycleSecondaryRole = PRICE_ADMIN_ROLE;
        _grantTestRole(PRICE_ADMIN_ROLE, _lifecycleSecondary);
    }

    function _freshSubject(bool activate_) internal {
        cacher = new PriceCacherTask(kernel, priceCache);
        _lifecycleTarget = address(cacher);
        if (activate_) _setMembership(true);
    }

    function _preservedState() internal view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    cacher.kernel(),
                    cacher.ROLES(),
                    cacher.priceCache(),
                    cacher.getAssetPairs(),
                    cacher.gracePeriod(),
                    priceCache.callCount(),
                    priceCache.lastAsset(),
                    priceCache.lastQuote(),
                    priceCache.lastMaxAge()
                )
            );
    }
}
