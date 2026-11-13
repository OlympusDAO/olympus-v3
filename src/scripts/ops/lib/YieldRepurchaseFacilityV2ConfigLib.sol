// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

// Scripting
import {VmSafe} from "@forge-std-1.16.2/Vm.sol";
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2Constants.sol";

/// @title YieldRepurchaseFacilityV2ConfigLib
/// @notice Reads the desired state of the YieldRepurchaseFacilityV2 stack (the facility, its
///         configuration policy and its config timelock) from `env.json` for the desired-state
///         tooling.
/// @dev The desired state of a chain lives under
///      `current.<chain>.olympus.config.YieldRepurchaseFacilityV2`:
///      - `gracePeriod` (seconds) is the re-enable grace window of the facility, of the
///        configuration policy and of the config timelock;
///      - `stepGasLimit` (gas units) is the gas limit of one isolated step of the facility;
///      - `timelockDelay` (seconds) is the delay of the config timelock;
///      - `initialDiscount` and `maxPricePremium` (`1e18` = 100%) are the bond market
///        parameters;
///      - `assets.<name>` declares one registered vault with `enabled`, `sellShares` and
///        `yieldBuybackShare` (`1e18` = 100%); the vault address is
///        `current.<chain>.external.tokens.<name>`;
///      - `backingVault` names the asset that is the backing vault;
///      - `clearinghouses` is an array with one `{address, included, offset}` entry per
///        Clearinghouse of the CHREG registry, `offset` in the units of the receivables.
///      The price feed that the launch registers for USDe in the PRICE module is
///      `current.<chain>.external.chainlink.usdeUsdPriceFeed`.
///
///      Every read fails closed with a message naming the key: a missing key, a zero address,
///      a value outside the bound that the contracts enforce, an asset name without an address
///      under `external.tokens`, two asset names with one vault address, a Clearinghouse listed
///      twice, a `backingVault` that names no declared asset, and a backing vault declared with
///      `enabled: false` or `sellShares: true`, both of which the facility rejects for the
///      backing vault. The library reads `env.json` only: the comparison with the live state
///      belongs to the batches.
///
///      The bounds are the constants of `YieldRepurchaseFacilityV2Constants` and the comparisons
///      of `YieldRepurchaseFacilityV2ValidationLib`; the bound of the timelock delay is declared
///      here, since the timelock holds it as its own public constants.
library YieldRepurchaseFacilityV2ConfigLib {
    using stdJson for string;

    // ========== CONSTANTS ========== //

    VmSafe internal constant _VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant CONFIG_KEY = "olympus.config.YieldRepurchaseFacilityV2";
    string internal constant TOKENS_KEY = "external.tokens";
    string internal constant USDE_USD_PRICE_FEED_KEY = "external.chainlink.usdeUsdPriceFeed";

    /// @notice The smallest desired `timelockDelay`, in seconds: the value of
    ///         `MIN_TIMELOCK_DELAY` of `YieldRepurchaseFacilityV2ConfigTimelock`, whose
    ///         constructor and delay setter enforce the bound.
    uint48 internal constant MIN_TIMELOCK_DELAY = 1 days;

    /// @notice The largest desired `timelockDelay`, in seconds: the value of
    ///         `MAX_TIMELOCK_DELAY` of `YieldRepurchaseFacilityV2ConfigTimelock`.
    uint48 internal constant MAX_TIMELOCK_DELAY = 30 days;

    // ========== DATA STRUCTURES ========== //

    /// @notice A vault declared under `assets` in `env.json`.
    /// @param name The key of the asset, which is also its key under `external.tokens`.
    /// @param vault The vault address.
    /// @param enabled Whether the asset participates in the weekly and daily cycles.
    /// @param sellShares Whether the bond markets of the vault pay out the vault shares.
    /// @param yieldBuybackShare The share of the projected yield routed to buybacks
    ///        (`1e18` = 100%).
    struct DesiredAsset {
        string name;
        address vault;
        bool enabled;
        bool sellShares;
        uint256 yieldBuybackShare;
    }

    /// @notice A Clearinghouse declared under `clearinghouses` in `env.json`.
    /// @param clearinghouse The Clearinghouse address.
    /// @param included Whether the Clearinghouse is included in the backing yield regardless
    ///        of its reserve token.
    /// @param offset The cumulative receivables offset, in the units of the receivables.
    struct DesiredClearinghouse {
        address clearinghouse;
        bool included;
        uint256 offset;
    }

    /// @notice The desired scalar parameters of the facility stack.
    /// @param gracePeriod The re-enable grace window of the three policies, in seconds.
    /// @param stepGasLimit The gas limit of one isolated step, in gas units.
    /// @param timelockDelay The delay of the config timelock, in seconds.
    /// @param initialDiscount The discount applied to the oracle price when a bond market
    ///        opens (`1e18` = 100%).
    /// @param maxPricePremium The premium over the oracle price at which the minimum price of
    ///        a bond market is placed (`1e18` = 100%).
    struct DesiredParameters {
        uint32 gracePeriod;
        uint32 stepGasLimit;
        uint48 timelockDelay;
        uint256 initialDiscount;
        uint256 maxPricePremium;
    }

    /// @notice The desired state of the facility stack.
    /// @param parameters The scalar parameters.
    /// @param backingVault The vault of the asset named by `backingVault`.
    /// @param assets The declared assets, sorted by name.
    /// @param clearinghouses The declared Clearinghouses, in the order of `env.json`.
    struct DesiredConfig {
        DesiredParameters parameters;
        address backingVault;
        DesiredAsset[] assets;
        DesiredClearinghouse[] clearinghouses;
    }

    // ========== DESIRED STATE ========== //

    /// @notice Reads the desired state of the facility stack of a chain: the scalar parameters,
    ///         the assets with the backing vault, and the Clearinghouses.
    /// @dev Reverts if `desiredParameters`, `desiredAssets` or `desiredClearinghouses` reverts.
    /// @param env_ The content of `env.json`.
    /// @param chain_ The `env.json` name of the chain.
    /// @return config The desired state.
    function desiredConfig(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredConfig memory config) {
        config.parameters = desiredParameters(env_, chain_);
        (config.assets, config.backingVault) = desiredAssets(env_, chain_);
        config.clearinghouses = desiredClearinghouses(env_, chain_);
    }

    /// @notice Reads the desired scalar parameters of the facility stack of a chain.
    /// @dev Reverts with a message naming the key if:
    ///      - A key is missing.
    ///      - `gracePeriod` is zero or not below `MAX_GRACE_PERIOD` (7 days).
    ///      - `stepGasLimit` is outside `[MIN_STEP_GAS_LIMIT, MAX_STEP_GAS_LIMIT]`.
    ///      - `timelockDelay` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    ///      - `initialDiscount` is not below 100%.
    ///      - `maxPricePremium` is above `MAX_PRICE_PREMIUM_LIMIT` (1,000%).
    /// @param env_ The content of `env.json`.
    /// @param chain_ The `env.json` name of the chain.
    /// @return parameters The desired scalar parameters.
    function desiredParameters(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredParameters memory parameters) {
        string memory base = _path(chain_, CONFIG_KEY);

        parameters.gracePeriod = _readGracePeriod(env_, string.concat(base, ".gracePeriod"));
        parameters.stepGasLimit = _readStepGasLimit(env_, string.concat(base, ".stepGasLimit"));
        parameters.timelockDelay = _readTimelockDelay(
            env_,
            string.concat(base, ".timelockDelay")
        );
        parameters.initialDiscount = _readInitialDiscount(
            env_,
            string.concat(base, ".initialDiscount")
        );
        parameters.maxPricePremium = _readMaxPricePremium(
            env_,
            string.concat(base, ".maxPricePremium")
        );
    }

    /// @notice Reads the desired assets of a chain, sorted by name, and the backing vault.
    /// @dev Reverts with a message naming the key if:
    ///      - `assets` or `backingVault` is missing, or an asset lacks a field.
    ///      - The `yieldBuybackShare` of an asset is above 100%.
    ///      - An asset has no non-zero address under `external.tokens`, or shares its vault
    ///        address with another asset.
    ///      - `backingVault` names no declared asset, or an asset declared with
    ///        `enabled: false` or `sellShares: true`.
    /// @param env_ The content of `env.json`.
    /// @param chain_ The `env.json` name of the chain.
    /// @return assets The declared assets, sorted by name.
    /// @return backingVault The vault of the asset named by `backingVault`.
    function desiredAssets(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredAsset[] memory assets, address backingVault) {
        string memory base = _path(chain_, CONFIG_KEY);
        string memory assetsPath = string.concat(base, ".assets");

        assets = _readAssets(env_, chain_, assetsPath);
        backingVault = _readBackingVault(
            env_,
            string.concat(base, ".backingVault"),
            assetsPath,
            assets
        );
    }

    /// @notice Reads the desired Clearinghouses of a chain, in the order of `env.json`.
    /// @dev Reverts with a message naming the key if:
    ///      - `clearinghouses` is missing or is an object.
    ///      - An entry lacks a field, carries the zero address or repeats the address of an
    ///        earlier entry.
    /// @param env_ The content of `env.json`.
    /// @param chain_ The `env.json` name of the chain.
    /// @return clearinghouses The declared Clearinghouses.
    // One of the three readers that `desiredConfig` composes, kept callable on its own
    // forge-lint: disable-next-item(internal-function-used-once)
    function desiredClearinghouses(
        string memory env_,
        string memory chain_
    ) internal view returns (DesiredClearinghouse[] memory clearinghouses) {
        return
            _readClearinghouses(
                env_,
                string.concat(_path(chain_, CONFIG_KEY), ".clearinghouses")
            );
    }

    /// @notice Reads the address of the USDe/USD price feed of a chain.
    /// @dev Reverts with a message naming the key if the key is missing or holds the zero
    ///      address.
    /// @param env_ The content of `env.json`.
    /// @param chain_ The `env.json` name of the chain.
    /// @return feed The price feed address.
    function usdeUsdPriceFeed(
        string memory env_,
        string memory chain_
    ) internal view returns (address feed) {
        return _readAddress(env_, _path(chain_, USDE_USD_PRICE_FEED_KEY));
    }

    // ========== LOOKUPS ========== //

    /// @notice Returns the declared asset of a vault.
    /// @param assets_ The declared assets.
    /// @param vault_ The vault address.
    /// @return declared Whether an asset is declared for the vault.
    /// @return asset The declared asset; empty when `declared` is false.
    function findAsset(
        DesiredAsset[] memory assets_,
        address vault_
    ) internal pure returns (bool declared, DesiredAsset memory asset) {
        for (uint256 i = 0; i < assets_.length; ++i) {
            if (assets_[i].vault != vault_) continue;
            asset = assets_[i];
            declared = true;
            break;
        }
    }

    /// @notice Returns the declared asset of a name.
    /// @param assets_ The declared assets.
    /// @param name_ The asset name.
    /// @return declared Whether an asset is declared under the name.
    /// @return asset The declared asset; empty when `declared` is false.
    // The lookup by name of the args files, kept beside the lookup by vault
    // forge-lint: disable-next-item(internal-function-used-once)
    function findAssetByName(
        DesiredAsset[] memory assets_,
        string memory name_
    ) internal pure returns (bool declared, DesiredAsset memory asset) {
        uint256 index;
        (declared, index) = _indexOfName(assets_, name_);
        if (declared) asset = assets_[index];
    }

    /// @notice Returns the declared entry of a Clearinghouse.
    /// @param clearinghouses_ The declared Clearinghouses.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return declared Whether the Clearinghouse is declared.
    /// @return entry The declared entry; empty when `declared` is false.
    function findClearinghouse(
        DesiredClearinghouse[] memory clearinghouses_,
        address clearinghouse_
    ) internal pure returns (bool declared, DesiredClearinghouse memory entry) {
        for (uint256 i = 0; i < clearinghouses_.length; ++i) {
            if (clearinghouses_[i].clearinghouse != clearinghouse_) continue;
            entry = clearinghouses_[i];
            declared = true;
            break;
        }
    }

    // ========== INTERNAL: SCALARS ========== //

    /// @dev The facility, the configuration policy and the config timelock reject a zero
    ///      window (`GracePeriod_ZeroPeriod`) and a window at or above `MAX_GRACE_PERIOD`.
    function _readGracePeriod(
        string memory env_,
        string memory key_
    ) private view returns (uint32 gracePeriod) {
        uint256 value = _readUint(env_, key_);
        require(
            value != 0 && value < YieldRepurchaseFacilityV2Constants.MAX_GRACE_PERIOD,
            _outOfBound(
                key_,
                value,
                string.concat(
                    "a grace period is non-zero and below ",
                    _VM.toString(uint256(YieldRepurchaseFacilityV2Constants.MAX_GRACE_PERIOD)),
                    " seconds"
                )
            )
        );
        return SafeCast.encodeUInt32(value);
    }

    function _readStepGasLimit(
        string memory env_,
        string memory key_
    ) private view returns (uint32 stepGasLimit) {
        uint256 value = _readUint(env_, key_);
        require(
            value >= YieldRepurchaseFacilityV2Constants.MIN_STEP_GAS_LIMIT &&
                value <= YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT,
            _outOfBound(
                key_,
                value,
                string.concat(
                    "the step gas limit lies within [",
                    _VM.toString(uint256(YieldRepurchaseFacilityV2Constants.MIN_STEP_GAS_LIMIT)),
                    ", ",
                    _VM.toString(uint256(YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT)),
                    "]"
                )
            )
        );
        return SafeCast.encodeUInt32(value);
    }

    function _readTimelockDelay(
        string memory env_,
        string memory key_
    ) private view returns (uint48 timelockDelay) {
        uint256 value = _readUint(env_, key_);
        require(
            value >= MIN_TIMELOCK_DELAY && value <= MAX_TIMELOCK_DELAY,
            _outOfBound(
                key_,
                value,
                string.concat(
                    "the timelock delay lies within [",
                    _VM.toString(uint256(MIN_TIMELOCK_DELAY)),
                    ", ",
                    _VM.toString(uint256(MAX_TIMELOCK_DELAY)),
                    "] seconds"
                )
            )
        );
        return SafeCast.encodeUInt48(value);
    }

    function _readInitialDiscount(
        string memory env_,
        string memory key_
    ) private view returns (uint256 initialDiscount) {
        initialDiscount = _readUint(env_, key_);
        require(
            initialDiscount < YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT,
            _outOfBound(
                key_,
                initialDiscount,
                string.concat(
                    "the initial discount is below ",
                    _VM.toString(YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT),
                    " (100%)"
                )
            )
        );
    }

    function _readMaxPricePremium(
        string memory env_,
        string memory key_
    ) private view returns (uint256 maxPricePremium) {
        maxPricePremium = _readUint(env_, key_);
        require(
            maxPricePremium <= YieldRepurchaseFacilityV2Constants.MAX_PRICE_PREMIUM_LIMIT,
            _outOfBound(
                key_,
                maxPricePremium,
                string.concat(
                    "the max price premium is at most ",
                    _VM.toString(YieldRepurchaseFacilityV2Constants.MAX_PRICE_PREMIUM_LIMIT),
                    " (1,000%)"
                )
            )
        );
    }

    // ========== INTERNAL: ASSETS ========== //

    function _readAssets(
        string memory env_,
        string memory chain_,
        string memory assetsPath_
    ) private view returns (DesiredAsset[] memory assets) {
        _requireKey(env_, assetsPath_);
        string[] memory names = _VM.parseJsonKeys(env_, assetsPath_);
        _sort(names);

        assets = new DesiredAsset[](names.length);
        for (uint256 i = 0; i < names.length; ++i) {
            assets[i] = _readAsset(env_, chain_, assetsPath_, names[i]);
            for (uint256 j = 0; j < i; ++j) {
                require(
                    assets[j].vault != assets[i].vault,
                    string.concat(
                        "YieldRepurchaseFacilityV2ConfigLib: assets ",
                        assets[j].name,
                        " and ",
                        assets[i].name,
                        " of ",
                        assetsPath_,
                        " resolve to one vault address ",
                        _VM.toString(assets[i].vault)
                    )
                );
            }
        }
    }

    function _readAsset(
        string memory env_,
        string memory chain_,
        string memory assetsPath_,
        string memory name_
    ) private view returns (DesiredAsset memory asset) {
        string memory base = string.concat(assetsPath_, ".", name_);
        asset.name = name_;
        asset.enabled = _readBool(env_, string.concat(base, ".enabled"));
        asset.sellShares = _readBool(env_, string.concat(base, ".sellShares"));

        string memory shareKey = string.concat(base, ".yieldBuybackShare");
        asset.yieldBuybackShare = _readUint(env_, shareKey);
        require(
            asset.yieldBuybackShare <= YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT,
            _outOfBound(
                shareKey,
                asset.yieldBuybackShare,
                string.concat(
                    "a yield buyback share is at most ",
                    _VM.toString(YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT),
                    " (100%)"
                )
            )
        );

        string memory tokenKey = string.concat(_path(chain_, TOKENS_KEY), ".", name_);
        require(
            _VM.keyExistsJson(env_, tokenKey),
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: asset ",
                name_,
                " of ",
                assetsPath_,
                " has no vault address: missing env.json key ",
                tokenKey
            )
        );
        asset.vault = env_.readAddress(tokenKey);
        require(
            asset.vault != address(0),
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: asset ",
                name_,
                " of ",
                assetsPath_,
                " has no vault address: zero address for ",
                tokenKey
            )
        );
    }

    /// @dev The facility designates only an enabled vault that does not sell shares
    ///      (`setBackingVault`), and afterwards rejects `disableAsset` and
    ///      `setSellShares(vault, true)` for it.
    function _readBackingVault(
        string memory env_,
        string memory key_,
        string memory assetsPath_,
        DesiredAsset[] memory assets_
    ) private view returns (address backingVault) {
        _requireKey(env_, key_);
        string memory name = env_.readString(key_);
        (bool declared, uint256 index) = _indexOfName(assets_, name);
        require(
            declared,
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                key_,
                " names ",
                name,
                ", which is not declared under ",
                assetsPath_
            )
        );
        require(
            assets_[index].enabled,
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the backing vault ",
                name,
                " (",
                key_,
                ") is declared with enabled: false under ",
                assetsPath_,
                "; the facility cannot disable the backing vault"
            )
        );
        require(
            !assets_[index].sellShares,
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the backing vault ",
                name,
                " (",
                key_,
                ") is declared with sellShares: true under ",
                assetsPath_,
                "; the backing vault cannot sell shares"
            )
        );
        return assets_[index].vault;
    }

    // ========== INTERNAL: CLEARINGHOUSES ========== //

    /// @dev The array is read by index, one key at a time: a wildcard read
    ///      (`clearinghouses[*].offset`) leaves out an entry that lacks the field without an
    ///      error, which would shift the values of the following entries.
    function _readClearinghouses(
        string memory env_,
        string memory arrayPath_
    ) private view returns (DesiredClearinghouse[] memory clearinghouses) {
        _requireKey(env_, arrayPath_);
        require(
            !_isObject(env_, arrayPath_),
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                arrayPath_,
                " is an object, expected an array of {address, included, offset} entries"
            )
        );

        uint256 count = 0;
        while (_VM.keyExistsJson(env_, _indexed(arrayPath_, count))) ++count;

        clearinghouses = new DesiredClearinghouse[](count);
        for (uint256 i = 0; i < count; ++i) {
            string memory base = _indexed(arrayPath_, i);
            clearinghouses[i].clearinghouse = _readAddress(env_, string.concat(base, ".address"));
            clearinghouses[i].included = _readBool(env_, string.concat(base, ".included"));
            clearinghouses[i].offset = _readUint(env_, string.concat(base, ".offset"));
            for (uint256 j = 0; j < i; ++j) {
                require(
                    clearinghouses[j].clearinghouse != clearinghouses[i].clearinghouse,
                    string.concat(
                        "YieldRepurchaseFacilityV2ConfigLib: ",
                        base,
                        " repeats the Clearinghouse ",
                        _VM.toString(clearinghouses[i].clearinghouse),
                        " of ",
                        _indexed(arrayPath_, j)
                    )
                );
            }
        }
    }

    /// @notice Returns whether the value at a path is a JSON object.
    /// @dev `parseJsonKeys` succeeds for an object and reverts for any other value.
    function _isObject(
        string memory env_,
        string memory path_
    ) private pure returns (bool isObject) {
        try _VM.parseJsonKeys(env_, path_) returns (string[] memory) {
            return true;
        } catch {
            return false;
        }
    }

    // ========== INTERNAL: READERS ========== //

    function _readUint(
        string memory env_,
        string memory key_
    ) private view returns (uint256 value) {
        _requireKey(env_, key_);
        return env_.readUint(key_);
    }

    function _readBool(string memory env_, string memory key_) private view returns (bool value) {
        _requireKey(env_, key_);
        return env_.readBool(key_);
    }

    function _readAddress(
        string memory env_,
        string memory key_
    ) private view returns (address value) {
        _requireKey(env_, key_);
        value = env_.readAddress(key_);
        require(
            value != address(0),
            string.concat("YieldRepurchaseFacilityV2ConfigLib: zero address for ", key_)
        );
    }

    function _requireKey(string memory env_, string memory key_) private view {
        require(
            _VM.keyExistsJson(env_, key_),
            string.concat("YieldRepurchaseFacilityV2ConfigLib: missing env.json key ", key_)
        );
    }

    function _outOfBound(
        string memory key_,
        uint256 value_,
        string memory bound_
    ) private pure returns (string memory message) {
        return
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the value of ",
                key_,
                " is ",
                _VM.toString(value_),
                "; ",
                bound_
            );
    }

    function _path(
        string memory chain_,
        string memory key_
    ) private pure returns (string memory path) {
        return string.concat(".current.", chain_, ".", key_);
    }

    function _indexed(
        string memory arrayPath_,
        uint256 index_
    ) private pure returns (string memory path) {
        return string.concat(arrayPath_, "[", _VM.toString(index_), "]");
    }

    function _indexOfName(
        DesiredAsset[] memory assets_,
        string memory name_
    ) private pure returns (bool found, uint256 index) {
        bytes32 nameHash = keccak256(bytes(name_));
        for (uint256 i = 0; i < assets_.length; ++i) {
            if (keccak256(bytes(assets_[i].name)) != nameHash) continue;
            index = i;
            found = true;
            break;
        }
    }

    /// @dev Insertion sort by byte-wise comparison, for a deterministic asset order.
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
        for (uint256 i = 0; i < length; ++i) {
            if (a[i] != b[i]) return a[i] < b[i];
        }
        return a.length < b.length;
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
