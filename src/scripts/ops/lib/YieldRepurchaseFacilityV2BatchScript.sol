// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {BackingOracleBatchScript} from "src/scripts/ops/lib/BackingOracleBatchScript.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2ConfigTimelock.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ConfigTimelockKeyLib} from "src/policies/utils/ConfigTimelockKeyLib.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

// Contracts
import {Policy} from "src/Kernel.sol";

/// @title YieldRepurchaseFacilityV2BatchScript
/// @notice The base of the multisig batches of the YieldRepurchaseFacilityV2 stack: the
///         addresses of the facility, its configuration policy, its config timelock and the
///         oracle pair with their bindings, the configuration keys of the timelock, and the
///         description of its sub-actions and of the errors of the stack.
/// @dev The batches import the interfaces of the stack only. Forge deploys the linked
///      libraries that the bytecode of a script target references before the script runs, so
///      a batch that embedded the facility would deploy its six libraries on every run.
abstract contract YieldRepurchaseFacilityV2BatchScript is BackingOracleBatchScript {
    // =========== CONSTANTS =========== //

    string internal constant CONFIG_KEY = "olympus.policies.YieldRepurchaseFacilityV2Config";
    string internal constant TIMELOCK_KEY =
        "olympus.policies.YieldRepurchaseFacilityV2ConfigTimelock";
    string internal constant FACILITY_KEY = "olympus.policies.YieldRepurchaseFacilityV2";
    string internal constant CONFIG_NAME = "YieldRepurchaseFacilityV2Config";
    string internal constant TIMELOCK_NAME = "YieldRepurchaseFacilityV2ConfigTimelock";
    string internal constant FACILITY_NAME = "YieldRepurchaseFacilityV2";

    // =========== DATA STRUCTURES =========== //

    /// @notice The addresses of the facility stack of a chain.
    /// @param kernel The Kernel.
    /// @param oracle The BackingOracle.
    /// @param oracleTimelock The BackingOracleConfigTimelock.
    /// @param config The YieldRepurchaseFacilityV2Config.
    /// @param timelock The YieldRepurchaseFacilityV2ConfigTimelock.
    /// @param facility The YieldRepurchaseFacilityV2.
    struct Stack {
        address kernel;
        address oracle;
        address oracleTimelock;
        address config;
        address timelock;
        address facility;
    }

    // =========== STATE =========== //

    /// @notice The assets of `env.json`, kept for the vault names in the logs.
    YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] internal _namedAssets;

    // =========== ADDRESSES =========== //

    /// @notice Reads the stack from `env.json` and checks the bindings that the constructors
    ///         and the admin setters fix.
    /// @dev Reverts if:
    ///      - A contract of the stack is not recorded in `env.json`.
    ///      - The oracle pair is not bound (`_oracleStack`).
    ///      - The configuration policy, the config timelock or the facility reports another
    ///        Kernel.
    ///      - The config timelock is bound to another configuration policy.
    ///      - The facility reads another backing oracle.
    function _stack() internal view returns (Stack memory stack) {
        OracleStack memory oracleStack = _oracleStack();
        stack.kernel = oracleStack.kernel;
        stack.oracle = oracleStack.oracle;
        stack.oracleTimelock = oracleStack.timelock;
        stack.config = _envAddressNotZero(CONFIG_KEY);
        stack.timelock = _envAddressNotZero(TIMELOCK_KEY);
        stack.facility = _envAddressNotZero(FACILITY_KEY);

        require(
            address(Policy(stack.config).kernel()) == stack.kernel,
            _fail("the YieldRepurchaseFacilityV2Config reports another Kernel")
        );
        require(
            address(Policy(stack.timelock).kernel()) == stack.kernel,
            _fail("the YieldRepurchaseFacilityV2ConfigTimelock reports another Kernel")
        );
        require(
            address(Policy(stack.facility).kernel()) == stack.kernel,
            _fail("the YieldRepurchaseFacilityV2 reports another Kernel")
        );
        require(
            IYieldRepurchaseFacilityV2ConfigTimelock(stack.timelock).config() == stack.config,
            _fail("the config timelock is bound to another configuration policy")
        );
        address backingOracle = IYieldRepurchaseFacilityV2View(stack.facility).backingOracle();
        require(
            backingOracle == stack.oracle,
            _fail(
                string.concat(
                    "the facility reads the backing oracle ",
                    vm.toString(backingOracle),
                    ", not the BackingOracle of env.json"
                )
            )
        );
    }

    /// @notice Narrows a stack to its oracle pair.
    function _oracleOf(Stack memory stack_) internal pure returns (OracleStack memory oracle) {
        oracle.kernel = stack_.kernel;
        oracle.oracle = stack_.oracle;
        oracle.timelock = stack_.oracleTimelock;
    }

    // =========== STATE CHECKS =========== //

    /// @notice Reverts unless the bindings that the launch establishes hold: the configuration
    ///         policy and the facility name each other, and the configuration policy names
    ///         the config timelock as its config operator.
    /// @dev `setFacility`, `setConfigurator` and `setConfigOperator` are admin calls.
    function _requireLaunchBindings(Stack memory stack_) internal view {
        address boundFacility = IYieldRepurchaseFacilityV2Config(stack_.config).facility();
        require(
            boundFacility == stack_.facility,
            _fail(
                string.concat(
                    "the configuration policy is bound to the facility ",
                    vm.toString(boundFacility),
                    ", not to the facility of env.json; setFacility is an admin call, made by the launch proposal"
                )
            )
        );
        address configurator = IYieldRepurchaseFacilityV2View(stack_.facility).configurator();
        require(
            configurator == stack_.config,
            _fail(
                string.concat(
                    "the configurator of the facility is ",
                    vm.toString(configurator),
                    ", not the configuration policy; setConfigurator is an admin call, made by the launch proposal"
                )
            )
        );
        address configOperator = IConfigOperator(stack_.config).configOperator();
        require(
            configOperator == stack_.timelock,
            _fail(
                string.concat(
                    "the config operator of the configuration policy is ",
                    vm.toString(configOperator),
                    ", not the config timelock, so the timelock could neither queue nor execute; setConfigOperator is an admin call (an OCG proposal on mainnet)"
                )
            )
        );
    }

    /// @notice Reverts unless the configuration policy and the config timelock are active in
    ///         the Kernel and enabled, the states that queueing and execution require of both.
    function _requireControlPlaneEnabled(Stack memory stack_) internal view {
        _requireActive(
            stack_.kernel,
            stack_.config,
            CONFIG_NAME,
            "so the timelock could neither queue nor execute"
        );
        _requireActive(
            stack_.kernel,
            stack_.timelock,
            TIMELOCK_NAME,
            "so it could neither queue nor execute"
        );
        require(
            IEnabler(stack_.config).isEnabled(),
            _fail(
                "the configuration policy is disabled, and queueing requires it enabled; re-enable it with YieldRepurchaseFacilityV2Batch.reEnable inside its grace window, or through the admin enable path afterwards"
            )
        );
        require(
            IEnabler(stack_.timelock).isEnabled(),
            _fail(
                "the config timelock is disabled, and queueing requires it enabled; re-enable it with YieldRepurchaseFacilityV2Batch.reEnable inside its grace window, or through the admin enable path afterwards"
            )
        );
    }

    // =========== CONFIGURATION KEYS =========== //

    /// @notice Returns the reserved key of a global domain: the domain constant scoped to the
    ///         configuration policy.
    function _globalKey(Stack memory stack_, bytes32 domain_) internal pure returns (bytes32 key) {
        return ConfigTimelockKeyLib.scope(stack_.config, domain_);
    }

    /// @notice Returns the reserved key of a vault or Clearinghouse domain:
    ///         `keccak256(abi.encode(domain, entity))` scoped to the configuration policy.
    function _entityKey(
        Stack memory stack_,
        bytes32 domain_,
        address entity_
    ) internal pure returns (bytes32 key) {
        return ConfigTimelockKeyLib.scope(stack_.config, keccak256(abi.encode(domain_, entity_)));
    }

    // =========== DESCRIPTIONS =========== //

    /// @notice Keeps the assets of `env.json` for the vault names in the logs.
    function _rememberAssets(
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets_
    ) internal {
        for (uint256 i = 0; i < assets_.length; ++i) {
            _namedAssets.push(assets_[i]);
        }
    }

    /// @notice Formats a vault: its `env.json` name when it is a declared asset, and its
    ///         address.
    function _vaultLabel(address vault_) internal view returns (string memory label) {
        uint256 length = _namedAssets.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_namedAssets[i].vault == vault_)
                return string.concat(_namedAssets[i].name, " ", vm.toString(vault_));
        }
        return vm.toString(vault_);
    }

    /// @notice Formats an operator setter of the configuration policy with its arguments, then
    ///         the sub-actions of the oracle timelock.
    /// @dev A queued payload is the canonical encoding of the arguments of its setter, which
    ///      the timelock checks when the action is queued.
    function _describeSubAction(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal view virtual override returns (string memory text) {
        bytes4 selector = sub_.selector;
        bytes memory payload = sub_.payload;

        if (selector == IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector) {
            return
                string.concat(
                    "setInitialDiscount(",
                    vm.toString(abi.decode(payload, (uint256))),
                    ")"
                );
        }
        if (selector == IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector) {
            return
                string.concat(
                    "setMaxPricePremium(",
                    vm.toString(abi.decode(payload, (uint256))),
                    ")"
                );
        }
        if (selector == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector) {
            (address vault, uint256 share) = abi.decode(payload, (address, uint256));
            return
                string.concat(
                    "setYieldBuybackShare(",
                    _vaultLabel(vault),
                    ", ",
                    vm.toString(share),
                    ")"
                );
        }
        if (selector == IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector) {
            (address clearinghouse, uint256 additional) = abi.decode(payload, (address, uint256));
            return
                string.concat(
                    "increaseClearinghouseOffset(",
                    vm.toString(clearinghouse),
                    ", ",
                    vm.toString(additional),
                    ")"
                );
        }
        if (selector == IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector) {
            (address vault, uint256 expected, uint256 newValue) = abi.decode(
                payload,
                (address, uint256, uint256)
            );
            return
                string.concat(
                    "decreaseNextYield(",
                    _vaultLabel(vault),
                    ", ",
                    vm.toString(expected),
                    ", ",
                    vm.toString(newValue),
                    ")"
                );
        }
        if (selector == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector) {
            return
                string.concat(
                    "excludeClearinghouse(",
                    vm.toString(abi.decode(payload, (address))),
                    ")"
                );
        }
        if (selector == IYieldRepurchaseFacilityV2Config.enableAsset.selector) {
            return string.concat("enableAsset(", _vaultLabel(abi.decode(payload, (address))), ")");
        }
        if (selector == IYieldRepurchaseFacilityV2Config.disableAsset.selector) {
            return string.concat("disableAsset(", _vaultLabel(abi.decode(payload, (address))), ")");
        }
        return super._describeSubAction(sub_);
    }

    /// @notice Names the errors of the facility stack, then those of the oracle pair and of
    ///         the queue base.
    function _describeRevert(
        bytes memory revertData_
    ) internal view virtual override returns (string memory text) {
        if (revertData_.length < SELECTOR_LENGTH) return super._describeRevert(revertData_);
        bytes4 selector = _selectorOf(revertData_);
        if (
            selector ==
            IYieldRepurchaseFacilityV2ConfigTimelock
                .IYieldRepurchaseFacilityV2ConfigTimelock_NotConfigOperator
                .selector
        ) return "NotConfigOperator (the configuration policy names another config operator)";
        if (
            selector ==
            IYieldRepurchaseFacilityV2ConfigTimelock
                .IYieldRepurchaseFacilityV2ConfigTimelock_PolicyNotActive
                .selector
        ) return "PolicyNotActive (the config timelock is not active in the Kernel)";
        if (
            selector ==
            IYieldRepurchaseFacilityV2Config.IYieldRepurchaseFacilityV2Config_PolicyNotActive.selector
        ) return "PolicyNotActive (the configuration policy is not active in the Kernel)";
        if (
            selector == IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_PolicyNotActive.selector
        )
            return
                "PolicyNotActive (the facility is not active in the Kernel; the action stays queued and executes inside its window once the facility is active again)";
        if (
            selector ==
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector
        ) return "AssetNotRegistered (the vault was de-registered; cancel the action)";
        if (
            selector ==
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_OffsetExceedsReceivables.selector
        )
            return
                "OffsetExceedsReceivables (repayments lowered the receivables below the resulting offset; cancel the action and reconcile again)";
        if (
            selector == IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldMismatch.selector
        )
            return
                "NextYieldMismatch (a weekly reset replaced the stored next yield; cancel the action)";
        return super._describeRevert(revertData_);
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
