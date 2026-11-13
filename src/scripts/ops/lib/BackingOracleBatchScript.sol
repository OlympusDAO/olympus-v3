// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: a failed `require` is meant to abort the whole run with
// its message.
// forge-lint: disable-start(custom-errors)

import {ConfigTimelockBatchScript} from "src/scripts/ops/lib/ConfigTimelockBatchScript.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ConfigTimelockKeyLib} from "src/policies/utils/ConfigTimelockKeyLib.sol";

// Contracts
import {Policy} from "src/Kernel.sol";

/// @title BackingOracleBatchScript
/// @notice The base of the multisig batches of the BackingOracle and its
///         BackingOracleConfigTimelock: the addresses of the pair with their binding, the one
///         configuration key of the timelock, and the description of its sub-actions and of
///         the errors of both contracts.
/// @dev The pair serves the consumers of the backing value. A disabled or Kernel-inactive
///      oracle reports no backing to the YieldRepurchaseFacilityV2: the price gate of the
///      facility closes, so its daily cycles open no markets and keep the purchased OHM
///      accumulated, and its `enable` and `reEnable` revert. `ORACLE_DOWN_CONSEQUENCE` words
///      this for the logs of every batch that disables the oracle or finds it disabled.
abstract contract BackingOracleBatchScript is ConfigTimelockBatchScript {
    // =========== CONSTANTS =========== //

    string internal constant KERNEL_KEY = "olympus.Kernel";
    string internal constant ORACLE_KEY = "olympus.policies.BackingOracle";
    string internal constant ORACLE_TIMELOCK_KEY = "olympus.policies.BackingOracleConfigTimelock";
    string internal constant ORACLE_NAME = "BackingOracle";
    string internal constant ORACLE_TIMELOCK_NAME = "BackingOracleConfigTimelock";

    string internal constant ORACLE_DOWN_CONSEQUENCE =
        "While the BackingOracle is disabled or inactive in the Kernel, the YieldRepurchaseFacilityV2 reads a zero backing: its price gate is closed, its daily cycles open no markets and keep the purchased OHM accumulated (a market that is already live stays purchasable until it concludes), and its enable and reEnable revert.";

    // =========== DATA STRUCTURES =========== //

    /// @notice The addresses of the oracle pair of a chain.
    /// @param kernel The Kernel.
    /// @param oracle The BackingOracle.
    /// @param timelock The BackingOracleConfigTimelock.
    struct OracleStack {
        address kernel;
        address oracle;
        address timelock;
    }

    // =========== ADDRESSES =========== //

    /// @notice Reads the oracle pair from `env.json` and checks the bindings that their
    ///         constructors fix.
    /// @dev Reverts if:
    ///      - The Kernel, the oracle or the timelock is not recorded in `env.json`.
    ///      - The oracle or the timelock reports another Kernel.
    ///      - The timelock is bound to another oracle.
    function _oracleStack() internal view returns (OracleStack memory stack) {
        stack.kernel = _envAddressNotZero(KERNEL_KEY);
        stack.oracle = _envAddressNotZero(ORACLE_KEY);
        stack.timelock = _envAddressNotZero(ORACLE_TIMELOCK_KEY);

        require(
            address(Policy(stack.oracle).kernel()) == stack.kernel,
            _fail("the BackingOracle reports another Kernel")
        );
        require(
            address(Policy(stack.timelock).kernel()) == stack.kernel,
            _fail("the BackingOracleConfigTimelock reports another Kernel")
        );
        require(
            address(IBackingOracleConfigTimelock(stack.timelock).backingOracle()) == stack.oracle,
            _fail("the BackingOracleConfigTimelock is bound to another oracle")
        );
    }

    /// @notice Returns the destination-scoped key that every queued backing update reserves.
    function _backingKey(address oracle_) internal pure returns (bytes32 key) {
        return
            ConfigTimelockKeyLib.scope(
                oracle_,
                keccak256(abi.encode(IBackingOracle.setBacking.selector))
            );
    }

    // =========== STATE CHECKS =========== //

    /// @notice Returns whether the oracle serves its backing: active in the Kernel and
    ///         enabled.
    function _oracleServes(OracleStack memory stack_) internal view returns (bool serves) {
        return _isActive(stack_.kernel, stack_.oracle) && IEnabler(stack_.oracle).isEnabled();
    }

    /// @notice Reverts unless both policies are active in the Kernel and the oracle names the
    ///         timelock as its config operator, the wiring that queueing and execution need
    ///         beyond the enabled flags.
    function _requireOracleWired(OracleStack memory stack_) internal view {
        _requireActive(
            stack_.kernel,
            stack_.oracle,
            ORACLE_NAME,
            "so the timelock could neither queue nor execute"
        );
        _requireActive(
            stack_.kernel,
            stack_.timelock,
            ORACLE_TIMELOCK_NAME,
            "so it could neither queue nor execute"
        );
        address configOperator = IConfigOperator(stack_.oracle).configOperator();
        require(
            configOperator == stack_.timelock,
            _fail(
                string.concat(
                    "the config operator of the BackingOracle is ",
                    vm.toString(configOperator),
                    ", not the BackingOracleConfigTimelock, so the timelock could neither queue nor execute; setConfigOperator is an admin call (an OCG proposal on mainnet)"
                )
            )
        );
    }

    // =========== DESCRIPTIONS =========== //

    /// @notice Formats a `setBacking` sub-action with its value.
    function _describeSubAction(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal view virtual override returns (string memory text) {
        if (sub_.selector == IBackingOracle.setBacking.selector && sub_.payload.length == WORD_LENGTH) {
            return
                string.concat("setBacking(", vm.toString(abi.decode(sub_.payload, (uint256))), ")");
        }
        return string.concat("selector ", vm.toString(abi.encodePacked(sub_.selector)));
    }

    /// @notice Names the errors of the oracle and of its timelock, then those of the queue base.
    function _describeRevert(
        bytes memory revertData_
    ) internal view virtual override returns (string memory text) {
        if (revertData_.length < SELECTOR_LENGTH) return super._describeRevert(revertData_);
        bytes4 selector = _selectorOf(revertData_);
        if (selector == IBackingOracle.BackingOracle_BackingChangeTooLarge.selector)
            return
                "BackingOracle_BackingChangeTooLarge (the value is outside the bound of one update around the live backing)";
        if (selector == IBackingOracle.BackingOracle_ZeroBacking.selector)
            return "BackingOracle_ZeroBacking (the oracle rejects a zero backing)";
        if (selector == IBackingOracle.BackingOracle_PolicyNotActive.selector)
            return "BackingOracle_PolicyNotActive (the oracle is not active in the Kernel)";
        if (
            selector == IBackingOracleConfigTimelock.BackingOracleTimelock_PolicyNotActive.selector
        )
            return
                "BackingOracleTimelock_PolicyNotActive (the timelock is not active in the Kernel)";
        return super._describeRevert(revertData_);
    }
}

// forge-lint: disable-end(custom-errors)
