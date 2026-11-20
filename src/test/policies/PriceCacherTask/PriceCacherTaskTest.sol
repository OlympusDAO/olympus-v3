// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockPriceCacherTaskCache} from "./MockPriceCacherTaskCache.sol";
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {PriceCacherTask} from "src/policies/PriceCacherTask.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

abstract contract PriceCacherTaskTest is Test {
    /// @notice Delegated role permitted to manage the task's pair set.
    bytes32 internal constant PRICE_ADMIN_ROLE = "price_admin";

    address internal admin;
    address internal emergency;
    address internal heart;
    address internal alice;
    address internal ohm;
    address internal usds;
    address internal usde;

    Kernel internal kernel;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    MockPriceCacherTaskCache internal priceCache;
    PriceCacherTask internal cacher;

    function setUp() public virtual {
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        heart = makeAddr("heart");
        alice = makeAddr("alice");
        ohm = makeAddr("ohm");
        usds = makeAddr("usds");
        usde = makeAddr("usde");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        priceCache = new MockPriceCacherTaskCache(kernel);
        cacher = new PriceCacherTask(kernel, priceCache);

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(priceCache));
        kernel.executeAction(Actions.ActivatePolicy, address(cacher));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole(HEART_ROLE, heart);
        priceCache.enable("");
        cacher.addAssetPair(ohm, usds);
        cacher.addAssetPair(ohm, usde);
        cacher.enable("");
        vm.stopPrank();
    }

    function _pairKey(address asset_, address quote_) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, quote_));
    }

    function _grantTestRole(bytes32 role_, address caller_) internal {
        if (roles.hasRole(caller_, role_)) return;
        vm.prank(admin);
        rolesAdmin.grantRole(role_, caller_);
    }

    function _setCacheMembership(bool active_) internal {
        if (kernel.isPolicyActive(Policy(address(priceCache))) == active_) return;
        vm.prank(admin);
        kernel.executeAction(
            active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
            address(priceCache)
        );
    }

    function _setTaskEnabled(bool enabled_) internal {
        if (cacher.isEnabled() == enabled_) return;
        vm.prank(admin);
        if (enabled_) cacher.enable("");
        else cacher.disable("");
    }

    function _setTaskMembership(bool active_) internal {
        if (kernel.isPolicyActive(Policy(address(cacher))) == active_) return;
        vm.prank(admin);
        kernel.executeAction(
            active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
            address(cacher)
        );
    }

    function _setCacheState(MockPriceCacherTaskCache cache_, bool active_, bool enabled_) internal {
        if (cache_.isEnabled() != enabled_) {
            if (enabled_) cache_.enable("");
            else cache_.disable("");
        }
        if (kernel.isPolicyActive(Policy(address(cache_))) != active_) {
            vm.prank(admin);
            kernel.executeAction(
                active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
                address(cache_)
            );
        }
    }

    function _forbidCacheVersionReads(MockPriceCacherTaskCache cache_) internal {
        bytes memory getter = abi.encodeWithSignature("VERSION()");
        vm.expectCall(address(cache_), getter, uint64(0));
        vm.mockCallRevert(address(cache_), getter, hex"deadbeef");
    }

    function _seedPairs(uint256 count_) internal {
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        IPriceCacherTask.AssetPair[] memory expected = new IPriceCacherTask.AssetPair[](count_);
        vm.startPrank(admin);
        for (uint256 i; i < pairs.length; ++i)
            cacher.removeAssetPair(pairs[i].asset, pairs[i].quote);
        for (uint256 i; i < count_; ++i) {
            expected[i] = IPriceCacherTask.AssetPair(
                address(uint160(0x1000 + i * 2)),
                address(uint160(0x1001 + i * 2))
            );
            cacher.addAssetPair(expected[i].asset, expected[i].quote);
        }
        vm.stopPrank();
        _assertPairs(expected);
    }

    function _configurationDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    cacher.kernel(),
                    cacher.ROLES(),
                    cacher.priceCache(),
                    cacher.getAssetPairs(),
                    cacher.isEnabled(),
                    cacher.lastTransitionAt(),
                    cacher.gracePeriod(),
                    priceCache.callCount()
                )
            );
    }

    function _expectConfigRejected(
        address caller_,
        bytes memory call_,
        bytes memory reason_
    ) internal {
        bytes32 beforeState = _configurationDigest();
        vm.prank(caller_);
        (bool ok, bytes memory reason) = address(cacher).call(call_);
        assertFalse(ok, "configuration rejects");
        assertEq(reason, reason_, "exact configuration error");
        assertEq(
            _configurationDigest(),
            beforeState,
            "binding, pairs, lifecycle and cache state preserved"
        );
    }

    function _invalidCache(address cache_) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_InvalidPriceCache.selector,
                cache_
            );
    }

    function _assertPairs(IPriceCacherTask.AssetPair[] memory expected_) internal view {
        assertEq(
            abi.encode(cacher.getAssetPairs()),
            abi.encode(expected_),
            "exact ordered pair set"
        );
    }

    function _assertAttempts(
        MockPriceCacherTaskCache cache_,
        IPriceCacherTask.AssetPair[] memory pairs_
    ) internal view {
        assertEq(cache_.callCount(), pairs_.length, "one successful call per pair");
        for (uint256 i; i < pairs_.length; ++i) {
            (address asset, address quote, uint48 maxAge) = cache_.recordedCalls(i);
            assertEq(asset, pairs_[i].asset, "asset forwarded in stored order");
            assertEq(quote, pairs_[i].quote, "quote forwarded in stored order");
            assertEq(maxAge, 0, "every pair uses maxAge zero");
            assertEq(
                cache_.pairCallCount(_pairKey(asset, quote)),
                1,
                "pair attempted exactly once"
            );
        }
        _assertPairs(pairs_);
    }
}
