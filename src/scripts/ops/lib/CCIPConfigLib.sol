// SPDX-License-Identifier: MIT
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Scripting
import {VmSafe} from "@forge-std-1.16.2/Vm.sol";
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolGetters} from "src/external/bridge/ICCIPTokenPoolGetters.sol";

// Libraries
import {Base58} from "@base58-solidity-1.0.3/Base58.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title CCIPConfigLib
/// @notice Shared helpers for the CCIP desired-state tooling: reading the desired config policy
///         parameters and the desired routes from `env.json`, reading the live route state from a
///         token pool, and comparing the two field by field.
/// @dev The desired state of a chain lives under `current.<chain>.olympus.config`:
///      - `CCIPBridgeConfig.{gracePeriod,timelockDelay,rebalancer,rateLimitAdmin}` are the
///        deployment and validation parameters of the config policy and its timelock;
///      - `CCIP.routes.<remoteChain>` declares one route per remote chain with `enabled`, an
///        explicit `remove` marker, `outboundRateLimit` and `inboundRateLimit`, and optional
///        `remoteToken` and `remotePools` overrides encoded as hex bytes. Without an override the
///        remote token is `current.<remoteChain>.olympus.legacy.OHM` and the remote pool is the
///        remote chain's pool (lock/release on a canonical chain, burn/mint on another EVM chain,
///        `olympus.periphery.TokenPool` on Solana), ABI-encoded for EVM chains and packed from the
///        base58 public key for SVM chains;
///      - `CCIP.routes.<remoteChain>.periphery` declares the desired periphery state toward the
///        remote chain (`gasLimit` with a defaulted `trustedRemote` for EVM, `gasLimit` and an
///        explicit `svmReceiver` for SVM, `remove` as the explicit removal marker);
///      - `CCIP.minimumPoolBacking` is the funding target of the canonical lock/release pool.
///      Every read fails closed: a missing key, a zero address, an empty or malformed encoding
///      or a disabled rate limiter reverts with a message naming the key.
library CCIPConfigLib {
    using stdJson for string;

    // ========== CONSTANTS ========== //

    VmSafe internal constant _VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant CONFIG_KEY = "olympus.config.CCIPBridgeConfig";
    string internal constant ROUTES_KEY = "olympus.config.CCIP.routes";
    string internal constant MIN_POOL_BACKING_KEY = "olympus.config.CCIP.minimumPoolBacking";
    string internal constant LOCK_RELEASE_POOL_KEY = "olympus.periphery.CCIPLockReleaseTokenPool";
    string internal constant BURN_MINT_POOL_KEY = "olympus.policies.CCIPBurnMintTokenPool";
    string internal constant SVM_POOL_KEY = "olympus.periphery.TokenPool";
    string internal constant EVM_BRIDGE_KEY = "olympus.periphery.CCIPCrossChainBridge";
    string internal constant OHM_KEY = "olympus.legacy.OHM";
    string internal constant CHAIN_SELECTOR_KEY = "external.ccip.ChainSelector";

    // ========== DATA STRUCTURES ========== //

    /// @notice The desired parameters of the config policy and its timelock.
    struct DesiredConfig {
        uint32 gracePeriod;
        uint48 timelockDelay;
        address rebalancer;
        address rateLimitAdmin;
    }

    /// @notice A route declared in `env.json`.
    struct DesiredRoute {
        string remoteChain;
        uint64 chainSelector;
        bool enabled;
        bool remove;
        bytes remoteToken;
        bytes[] remotePools;
        ICCIPRateLimiter.Config outbound;
        ICCIPRateLimiter.Config inbound;
    }

    /// @notice The state of a route read from the pool.
    struct LiveRoute {
        bool exists;
        bytes remoteToken;
        bytes[] remotePools;
        ICCIPRateLimiter.Config outbound;
        ICCIPRateLimiter.Config inbound;
    }

    /// @notice The field-by-field difference between a desired route and its live state.
    struct RouteDiff {
        bool remoteTokenDiffers;
        bytes[] poolsToAdd;
        bytes[] poolsToRemove;
        bool limitsDiffer;
    }

    /// @notice The desired periphery state toward one remote chain, declared as the `periphery`
    ///         block of a route in `env.json`.
    /// @param remoteChain The `env.json` name of the remote chain.
    /// @param chainSelector The CCIP chain selector of the remote chain.
    /// @param remove Whether the trusted remote is marked for removal; no other field is read
    ///        for a removed entry.
    /// @param isSvm Whether the remote chain is an SVM chain.
    /// @param gasLimit The `ccipReceive` gas limit toward the remote chain.
    /// @param evmTrustedRemote The trusted remote address of an EVM chain.
    /// @param svmTrustedRemote The trusted remote receiver of an SVM chain.
    struct DesiredPeriphery {
        string remoteChain;
        uint64 chainSelector;
        bool remove;
        bool isSvm;
        uint32 gasLimit;
        address evmTrustedRemote;
        bytes32 svmTrustedRemote;
    }

    // ========== DESIRED STATE ========== //

    /// @notice Reads the desired config policy parameters of a chain.
    function desiredConfig(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredConfig memory config) {
        string memory base = _path(chain_, CONFIG_KEY);
        _requireKey(env_, string.concat(base, ".gracePeriod"));
        _requireKey(env_, string.concat(base, ".timelockDelay"));
        _requireKey(env_, string.concat(base, ".rebalancer"));
        _requireKey(env_, string.concat(base, ".rateLimitAdmin"));

        config.gracePeriod = SafeCast.encodeUInt32(env_.readUint(string.concat(base, ".gracePeriod")));
        config.timelockDelay = SafeCast.encodeUInt48(
            env_.readUint(string.concat(base, ".timelockDelay"))
        );
        config.rebalancer = env_.readAddress(string.concat(base, ".rebalancer"));
        config.rateLimitAdmin = env_.readAddress(string.concat(base, ".rateLimitAdmin"));

        require(config.gracePeriod != 0, "CCIPConfigLib: gracePeriod is zero");
        require(config.timelockDelay != 0, "CCIPConfigLib: timelockDelay is zero");
    }

    /// @notice Reads the desired routes of a chain, sorted by remote chain name.
    /// @dev Returns an empty array when the chain declares no routes.
    function desiredRoutes(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredRoute[] memory routes) {
        string memory routesPath = _path(chain_, ROUTES_KEY);
        if (!_VM.keyExistsJson(env_, routesPath)) return routes;

        string[] memory names = _VM.parseJsonKeys(env_, routesPath);
        _sort(names);

        routes = new DesiredRoute[](names.length);
        for (uint256 i; i < names.length; ++i) {
            routes[i] = _desiredRoute(env_, chain_, names[i]);
        }
    }

    /// @notice Reads the desired periphery states of a chain, sorted by remote chain name: one
    ///         entry per route that carries a `periphery` block. A route without the block is not
    ///         managed by the periphery reconciler.
    /// @dev A block on an EVM route requires `gasLimit` and defaults the trusted remote to the
    ///      remote chain's `olympus.periphery.CCIPCrossChainBridge`, overridable with an explicit
    ///      `trustedRemote`; a block on an SVM route requires `gasLimit` and an explicit
    ///      `svmReceiver` (bytes32). `remove: true` on the block or on the route marks the
    ///      trusted remote for removal, and no other field is read then.
    function desiredPeripheries(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredPeriphery[] memory peripheries) {
        string memory routesPath = _path(chain_, ROUTES_KEY);
        if (!_VM.keyExistsJson(env_, routesPath)) return peripheries;

        string[] memory names = _VM.parseJsonKeys(env_, routesPath);
        _sort(names);

        DesiredPeriphery[] memory buffer = new DesiredPeriphery[](names.length);
        uint256 count;
        for (uint256 i; i < names.length; ++i) {
            string memory base = string.concat(routesPath, ".", names[i], ".periphery");
            if (!_VM.keyExistsJson(env_, base)) continue;
            buffer[count++] = _desiredPeriphery(env_, chain_, names[i], base);
        }

        peripheries = new DesiredPeriphery[](count);
        for (uint256 i; i < count; ++i) {
            peripheries[i] = buffer[i];
        }
    }

    /// @notice Reads the minimum OHM backing of the canonical lock/release pool: the OHM
    ///         outstanding on the burn/mint chains that the pool must be able to release.
    function minimumPoolBacking(
        string memory env_,
        string memory chain_
    ) internal view returns (uint256 backing) {
        string memory key = _path(chain_, MIN_POOL_BACKING_KEY);
        _requireKey(env_, key);
        backing = env_.readUint(key);
        require(backing != 0, string.concat("CCIPConfigLib: zero value for ", key));
    }

    /// @notice Returns whether a chain hosts a burn/mint pool: an EVM chain that is not
    ///         canonical. Deliveries to such a chain mint through MINTR and need the raised OHM
    ///         fee budget on the source lane.
    function isBurnMintEvmChain(string memory chain_) internal pure returns (bool isBurnMint) {
        return !ChainUtils._isSVMChain(chain_) && !ChainUtils._isCanonicalChain(chain_);
    }

    /// @notice Reads the CCIP chain selector of a chain.
    function chainSelector(
        string memory env_,
        string memory chain_
    ) internal view returns (uint64 selector) {
        string memory key = _path(chain_, CHAIN_SELECTOR_KEY);
        _requireKey(env_, key);
        selector = SafeCast.encodeUInt64(env_.readUint(key));
        require(
            selector != 0,
            string.concat("CCIPConfigLib: zero chain selector for chain ", chain_)
        );
    }

    /// @notice Returns the `env.json` key of the local token pool of a chain.
    function poolKey(string memory chain_) internal pure returns (string memory key) {
        if (ChainUtils._isSVMChain(chain_)) return SVM_POOL_KEY;
        if (ChainUtils._isCanonicalChain(chain_)) return LOCK_RELEASE_POOL_KEY;
        return BURN_MINT_POOL_KEY;
    }

    /// @notice Returns the default remote token encoding of a remote chain.
    function defaultRemoteToken(
        string memory env_,
        string memory remoteChain_
    ) internal view returns (bytes memory remoteToken) {
        return _encodedAddress(env_, remoteChain_, OHM_KEY);
    }

    /// @notice Returns the default remote pool encoding of a remote chain.
    function defaultRemotePool(
        string memory env_,
        string memory remoteChain_
    ) internal view returns (bytes memory remotePool) {
        return _encodedAddress(env_, remoteChain_, poolKey(remoteChain_));
    }

    /// @notice Encodes a base58 SVM public key as the 32 packed bytes that the pool expects.
    function encodeSvmAddress(
        string memory base58_
    ) internal pure returns (bytes memory encoded) {
        bytes memory decoded = Base58.decodeFromString(base58_);
        require(
            decoded.length == 32,
            string.concat("CCIPConfigLib: base58 value is not 32 bytes: ", base58_)
        );
        // casting to 'bytes32' is safe because the length is checked to be 32 bytes above
        // forge-lint: disable-next-line(unsafe-typecast)
        return abi.encodePacked(bytes32(decoded));
    }

    /// @notice Encodes an EVM address as the ABI-encoded bytes that the pool expects.
    function encodeEvmAddress(address address_) internal pure returns (bytes memory encoded) {
        return abi.encode(address_);
    }

    // ========== LIVE STATE ========== //

    /// @notice Reads the pending owner of a pool. `Ownable2Step` exposes no getter and keeps
    ///         `s_pendingOwner` and `s_owner` in two consecutive storage slots whose position
    ///         depends on the bases declared before it: slot 0 for `LockReleaseTokenPool` and
    ///         slot 2 for `CCIPBurnMintTokenPool` (after `kernel`, `ROLES` and `isEnabled`). The
    ///         slot is confirmed by checking that the following slot holds the owner.
    function pendingOwner(address pool_) internal view returns (address pending) {
        address owner = ICCIPTokenPoolGetters(pool_).owner();
        uint256[2] memory pendingSlots = [uint256(0), 2];
        for (uint256 i; i < pendingSlots.length; ++i) {
            uint256 slot = pendingSlots[i];
            if (_toAddress(_VM.load(pool_, bytes32(slot + 1))) == owner) {
                return _toAddress(_VM.load(pool_, bytes32(slot)));
            }
        }
        revert(
            string.concat(
                "CCIPConfigLib: unexpected Ownable2Step storage layout for pool ",
                _VM.toString(pool_)
            )
        );
    }

    /// @notice Reads the state of a route from the pool.
    function liveRoute(
        ICCIPTokenPoolGetters pool_,
        uint64 chainSelector_
    ) internal view returns (LiveRoute memory route) {
        route.exists = pool_.isSupportedChain(chainSelector_);
        if (!route.exists) return route;

        route.remoteToken = pool_.getRemoteToken(chainSelector_);
        route.remotePools = pool_.getRemotePools(chainSelector_);
        route.outbound = toConfig(pool_.getCurrentOutboundRateLimiterState(chainSelector_));
        route.inbound = toConfig(pool_.getCurrentInboundRateLimiterState(chainSelector_));
    }

    /// @notice Extracts the configuration fields of a bucket.
    function toConfig(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (ICCIPRateLimiter.Config memory config) {
        return
            ICCIPRateLimiter.Config({
                isEnabled: bucket_.isEnabled,
                capacity: bucket_.capacity,
                rate: bucket_.rate
            });
    }

    // ========== COMPARISON ========== //

    /// @notice Compares a desired route with its live state. Only meaningful when the live route
    ///         exists.
    function diffRoute(
        DesiredRoute memory desired_,
        LiveRoute memory live_
    ) internal pure returns (RouteDiff memory diff) {
        diff.remoteTokenDiffers = keccak256(desired_.remoteToken) != keccak256(live_.remoteToken);
        diff.poolsToAdd = _difference(desired_.remotePools, live_.remotePools);
        diff.poolsToRemove = _difference(live_.remotePools, desired_.remotePools);
        diff.limitsDiffer =
            !sameConfig(desired_.outbound, live_.outbound) ||
            !sameConfig(desired_.inbound, live_.inbound);
    }

    /// @notice Returns whether a diff carries any change.
    function hasChanges(RouteDiff memory diff_) internal pure returns (bool changed) {
        return
            diff_.remoteTokenDiffers ||
            diff_.poolsToAdd.length > 0 ||
            diff_.poolsToRemove.length > 0 ||
            diff_.limitsDiffer;
    }

    /// @notice Compares the `isEnabled`, `capacity` and `rate` fields of two configurations.
    function sameConfig(
        ICCIPRateLimiter.Config memory a_,
        ICCIPRateLimiter.Config memory b_
    ) internal pure returns (bool same) {
        return a_.isEnabled == b_.isEnabled && a_.capacity == b_.capacity && a_.rate == b_.rate;
    }

    /// @notice Returns whether a set of encoded addresses contains an entry.
    function containsBytes(
        bytes[] memory set_,
        bytes memory item_
    ) internal pure returns (bool contained) {
        bytes32 itemHash = keccak256(item_);
        for (uint256 i; i < set_.length; ++i) {
            if (keccak256(set_[i]) == itemHash) return true;
        }
        return false;
    }

    /// @notice Reverts unless the configuration is an enabled limiter accepted by the config
    ///         policy and the pool: `isEnabled` with `0 < rate < capacity`.
    function requireEnabledConfig(
        ICCIPRateLimiter.Config memory config_,
        string memory label_
    ) internal pure {
        require(config_.isEnabled, string.concat("CCIPConfigLib: ", label_, " is disabled"));
        require(config_.rate != 0, string.concat("CCIPConfigLib: ", label_, " has a zero rate"));
        require(
            config_.rate < config_.capacity,
            string.concat("CCIPConfigLib: ", label_, " rate is not below its capacity")
        );
    }

    // ========== FORMATTING ========== //

    /// @notice Formats a configuration for logs.
    function describe(
        ICCIPRateLimiter.Config memory config_
    ) internal pure returns (string memory text) {
        return
            string.concat(
                config_.isEnabled ? "enabled" : "disabled",
                " capacity=",
                _VM.toString(config_.capacity),
                " rate=",
                _VM.toString(config_.rate)
            );
    }

    /// @notice Formats a set of encoded addresses for logs.
    function describe(bytes[] memory set_) internal pure returns (string memory text) {
        text = "[";
        for (uint256 i; i < set_.length; ++i) {
            text = string.concat(text, i == 0 ? "" : ", ", _VM.toString(set_[i]));
        }
        text = string.concat(text, "]");
    }

    // ========== INTERNAL ========== //

    function _desiredRoute(
        string memory env_,
        string memory chain_,
        string memory remoteChain_
    ) private view returns (DesiredRoute memory route) {
        string memory base = string.concat(_path(chain_, ROUTES_KEY), ".", remoteChain_);
        route.remoteChain = remoteChain_;
        route.chainSelector = chainSelector(env_, remoteChain_);

        _requireKey(env_, string.concat(base, ".enabled"));
        route.enabled = env_.readBool(string.concat(base, ".enabled"));
        route.remove =
            _VM.keyExistsJson(env_, string.concat(base, ".remove")) &&
            env_.readBool(string.concat(base, ".remove"));

        string memory tokenKey = string.concat(base, ".remoteToken");
        route.remoteToken = _VM.keyExistsJson(env_, tokenKey)
            ? env_.readBytes(tokenKey)
            : defaultRemoteToken(env_, remoteChain_);
        require(
            route.remoteToken.length != 0,
            string.concat("CCIPConfigLib: empty remote token for route ", remoteChain_)
        );

        string memory poolsKey = string.concat(base, ".remotePools");
        if (_VM.keyExistsJson(env_, poolsKey)) {
            route.remotePools = env_.readBytesArray(poolsKey);
        } else {
            route.remotePools = new bytes[](1);
            route.remotePools[0] = defaultRemotePool(env_, remoteChain_);
        }
        require(
            route.remotePools.length != 0,
            string.concat("CCIPConfigLib: no remote pools for route ", remoteChain_)
        );
        for (uint256 i; i < route.remotePools.length; ++i) {
            require(
                route.remotePools[i].length != 0,
                string.concat("CCIPConfigLib: empty remote pool for route ", remoteChain_)
            );
        }

        // A route that is to be removed or is not enabled needs no limits
        if (!route.enabled || route.remove) return route;

        route.outbound = _readConfig(env_, string.concat(base, ".outboundRateLimit"));
        route.inbound = _readConfig(env_, string.concat(base, ".inboundRateLimit"));
        requireEnabledConfig(
            route.outbound,
            string.concat("outbound rate limit of route ", remoteChain_)
        );
        requireEnabledConfig(
            route.inbound,
            string.concat("inbound rate limit of route ", remoteChain_)
        );
    }

    function _desiredPeriphery(
        string memory env_,
        string memory chain_,
        string memory remoteChain_,
        string memory base_
    ) private view returns (DesiredPeriphery memory periphery) {
        periphery.remoteChain = remoteChain_;
        periphery.chainSelector = chainSelector(env_, remoteChain_);
        periphery.isSvm = ChainUtils._isSVMChain(remoteChain_);

        string memory routeRemoveKey = string.concat(
            _path(chain_, ROUTES_KEY),
            ".",
            remoteChain_,
            ".remove"
        );
        periphery.remove =
            (_VM.keyExistsJson(env_, routeRemoveKey) && env_.readBool(routeRemoveKey)) ||
            (_VM.keyExistsJson(env_, string.concat(base_, ".remove")) &&
                env_.readBool(string.concat(base_, ".remove")));
        if (periphery.remove) return periphery;

        string memory gasKey = string.concat(base_, ".gasLimit");
        _requireKey(env_, gasKey);
        periphery.gasLimit = SafeCast.encodeUInt32(env_.readUint(gasKey));

        if (periphery.isSvm) {
            string memory receiverKey = string.concat(base_, ".svmReceiver");
            _requireKey(env_, receiverKey);
            periphery.svmTrustedRemote = env_.readBytes32(receiverKey);
            return periphery;
        }

        // A zero gas limit is meaningful only toward an SVM chain (a token-only transfer with
        // no receiver call); the EVM periphery always delivers data, which a zero budget would
        // make undeliverable.
        require(
            periphery.gasLimit != 0,
            string.concat(
                "CCIPConfigLib: zero gas limit for the EVM periphery of route ",
                remoteChain_
            )
        );

        string memory overrideKey = string.concat(base_, ".trustedRemote");
        if (_VM.keyExistsJson(env_, overrideKey)) {
            periphery.evmTrustedRemote = env_.readAddress(overrideKey);
            require(
                periphery.evmTrustedRemote != address(0),
                string.concat("CCIPConfigLib: zero trusted remote override for ", remoteChain_)
            );
            return periphery;
        }
        string memory bridgeKey = _path(remoteChain_, EVM_BRIDGE_KEY);
        _requireKey(env_, bridgeKey);
        periphery.evmTrustedRemote = env_.readAddress(bridgeKey);
        require(
            periphery.evmTrustedRemote != address(0),
            string.concat("CCIPConfigLib: zero address for ", bridgeKey)
        );
    }

    function _readConfig(
        string memory env_,
        string memory base_
    ) private view returns (ICCIPRateLimiter.Config memory config) {
        _requireKey(env_, string.concat(base_, ".isEnabled"));
        _requireKey(env_, string.concat(base_, ".capacity"));
        _requireKey(env_, string.concat(base_, ".rate"));
        config.isEnabled = env_.readBool(string.concat(base_, ".isEnabled"));
        config.capacity = SafeCast.encodeUInt128(env_.readUint(string.concat(base_, ".capacity")));
        config.rate = SafeCast.encodeUInt128(env_.readUint(string.concat(base_, ".rate")));
    }

    function _encodedAddress(
        string memory env_,
        string memory chain_,
        string memory key_
    ) private view returns (bytes memory encoded) {
        string memory path = _path(chain_, key_);
        _requireKey(env_, path);
        if (ChainUtils._isSVMChain(chain_)) {
            string memory base58 = env_.readString(path);
            require(
                bytes(base58).length != 0,
                string.concat("CCIPConfigLib: empty value for ", path)
            );
            return encodeSvmAddress(base58);
        }

        address value = env_.readAddress(path);
        require(value != address(0), string.concat("CCIPConfigLib: zero address for ", path));
        return encodeEvmAddress(value);
    }

    function _difference(
        bytes[] memory left_,
        bytes[] memory right_
    ) private pure returns (bytes[] memory result) {
        bytes[] memory buffer = new bytes[](left_.length);
        uint256 count;
        for (uint256 i; i < left_.length; ++i) {
            if (!containsBytes(right_, left_[i])) buffer[count++] = left_[i];
        }
        result = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            result[i] = buffer[i];
        }
    }

    function _toAddress(bytes32 word_) private pure returns (address value) {
        return address(uint160(uint256(word_)));
    }

    function _path(
        string memory chain_,
        string memory key_
    ) private pure returns (string memory path) {
        return string.concat(".current.", chain_, ".", key_);
    }

    function _requireKey(string memory env_, string memory path_) private view {
        require(
            _VM.keyExistsJson(env_, path_),
            string.concat("CCIPConfigLib: missing env.json key ", path_)
        );
    }

    /// @dev Insertion sort by byte-wise comparison, for a deterministic route order.
    function _sort(string[] memory values_) private pure {
        for (uint256 i = 1; i < values_.length; ++i) {
            string memory current = values_[i];
            uint256 j = i;
            while (j > 0 && _lessThan(current, values_[j - 1])) {
                values_[j] = values_[j - 1];
                --j;
            }
            values_[j] = current;
        }
    }

    function _lessThan(string memory a_, string memory b_) private pure returns (bool less) {
        bytes memory a = bytes(a_);
        bytes memory b = bytes(b_);
        uint256 length = a.length < b.length ? a.length : b.length;
        for (uint256 i; i < length; ++i) {
            if (a[i] != b[i]) return a[i] < b[i];
        }
        return a.length < b.length;
    }
}
