// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IBasicRescueable} from "src/interfaces/IBasicRescueable.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IYieldRepurchaseFacilityV2Write} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Write.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Libraries
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {YieldRepurchaseFacilityV2BatchScript} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2BatchScript.sol";

/// @title YieldRepurchaseFacilityV2Batch
/// @notice The lifecycle batches and the emergency levers of the YieldRepurchaseFacilityV2
///         stack: the facility, its configuration policy and its config timelock. Every entry
///         point is declarative or conditional: it reads the live state and adds only the
///         calls that are missing, so a second run on a converged state proposes nothing.
///
///         Entry points of the DAO MS:
///         - `reEnable` (as `yrf_admin`): re-enable the configuration policy, the config
///           timelock and the facility after a disable, while their grace windows are open.
///         - `reconcileStepGasLimit` (as `yrf_admin`): set the step gas limit of the facility
///           to the value of `env.json`, by a direct call that takes effect at once.
///         - `rescue` (as `yrf_admin`): transfer a token that is not part of a buyback pool,
///           or the OHM above the purchased amount, from the facility to the treasury.
///
///         Emergency levers of the Emergency MS:
///         - `stopPurchasesEmergencyMS`: disable the facility. Its beats stop and its live
///           bond markets are closed on a best-effort basis; the funds and the accounting stay
///           in place, so that `reEnable` resumes the interrupted week.
///         - `freezeConfigEmergencyMS`: disable the config timelock and the configuration
///           policy. Queueing and execution stop, and so do the admin setters of the
///           configuration policy; the facility keeps operating on its current configuration.
///         - `haltAllEmergencyMS`: both of the above in one batch.
///         - `returnFundsToTreasuryEmergencyMS`: on a disabled facility, burn the purchased
///           OHM and transfer every balance to the treasury.
///
///         The four levers are separate because their costs differ: stopping the purchases
///         interrupts the buybacks, freezing the configuration does not, and returning the
///         funds ends the week for good. The levers have no DAO MS variant: `disable()` and
///         `returnFundsToTreasury()` are gated to `emergency` and `admin`, and on mainnet the
///         DAO MS holds neither.
///
///         Configuration changes run through `YieldRepurchaseFacilityV2ConfigTimelockBatch`,
///         the backing through the `BackingOracle` batches. A disabled BackingOracle closes
///         the price gate of the facility without stopping its beats, and makes the `reEnable`
///         of the facility revert.
contract YieldRepurchaseFacilityV2Batch is YieldRepurchaseFacilityV2BatchScript {
    // =========== CONSTANTS =========== //

    /// @notice The gas limit of one transaction on Ethereum mainnet (EIP-7825), which the gas
    ///         a `returnFundsToTreasury` call needs is compared with.
    uint256 internal constant TRANSACTION_GAS_LIMIT_CAP = 2 ** 24;

    // =========== STATE =========== //

    /// @notice The step gas limit `reconcileStepGasLimit` expects afterwards.
    uint32 internal _expectedStepGasLimit;

    /// @notice The token `rescue` transfers.
    address internal _rescuedToken;

    /// @notice The balance of the rescued token the facility keeps: the purchased OHM for
    ///         OHM, and zero for any other token.
    uint256 internal _rescueResidual;

    /// @notice The treasury balance of the rescued token `rescue` expects afterwards.
    uint256 internal _expectedTreasuryBalance;

    // =========== ENTRY POINTS: DAO MS =========== //

    /// @notice Re-enables the configuration policy, the config timelock and the facility after
    ///         a disable, while their grace windows are open (DAO MS as `yrf_admin`).
    /// @dev A policy that is enabled, that has never been enabled or whose grace window has
    ///      elapsed is reported and skipped: the last two need the admin `enable` path, which
    ///      on mainnet is an OCG proposal. The configuration policy is re-enabled first and
    ///      the facility last. A re-enabled facility resumes the interrupted week in place.
    ///
    ///      The enabled flags alone do not make the stack usable, so the batch requires the
    ///      wiring before it plans: the three policies active in the Kernel, the facility and
    ///      the configuration policy naming each other, and the config timelock named as the
    ///      config operator. The `reEnable` of the facility also requires the BackingOracle
    ///      active in the Kernel and enabled.
    ///
    ///      Re-enabling the config timelock makes every matured queued action executable by
    ///      any account at once: the run lists the unresolved actions, and the ones that must
    ///      not survive are cancelled first
    ///      (`YieldRepurchaseFacilityV2ConfigTimelockBatch.cancelQueuedAction` or
    ///      `cancelQueuedActionEmergency`).
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The contracts of the stack are not bound to each other.
    ///      - The configuration policy, the config timelock or the facility is not active in
    ///        the Kernel, or the launch bindings do not hold.
    ///      - The re-enable of the facility is due and the BackingOracle is not active in the
    ///        Kernel or is disabled (re-enable it first with `BackingOracleBatch.reEnable`).
    ///      - A re-enable is due and the batch owner does not hold `yrf_admin`.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function reEnable(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);

        Stack memory stack = _stack();

        console2.log(
            "\n=== Re-enable the YieldRepurchaseFacilityV2 stack within the grace windows ==="
        );
        _requireWired(stack);

        bool configDue = _reEnableDue(stack.config, CONFIG_NAME);
        bool timelockDue = _reEnableDue(stack.timelock, TIMELOCK_NAME);
        bool facilityDue = _reEnableDue(stack.facility, FACILITY_NAME);

        if (facilityDue) {
            require(
                _oracleServes(_oracleOf(stack)),
                _fail(
                    "the BackingOracle is not active in the Kernel or is disabled, and the reEnable of the facility requires it active and enabled; re-enable the oracle first with BackingOracleBatch.reEnable inside its grace window, or through the admin enable path afterwards"
                )
            );
        } else if (!_oracleServes(_oracleOf(stack))) {
            console2.log("\nNOTE:", ORACLE_DOWN_CONSEQUENCE);
        }
        if (configDue || timelockDue || facilityDue) {
            require(
                _roles(stack.kernel).hasRole(_owner, YRF_ADMIN_ROLE),
                _fail(
                    "the batch owner does not hold yrf_admin, the only role reEnable() of the three policies accepts; on mainnet the DAO MS receives yrf_admin from the launch proposal"
                )
            );
        }
        console2.log("");
        if (configDue) _planReEnable(stack.config, CONFIG_NAME);
        if (timelockDue) _planReEnable(stack.timelock, TIMELOCK_NAME);
        if (facilityDue) _planReEnable(stack.facility, FACILITY_NAME);

        _logUnresolvedQueue(
            IConfigTimelockBatchQueue(stack.timelock),
            TIMELOCK_NAME,
            "Once the configuration policy and the config timelock are enabled, a matured action executes permissionlessly. Cancel the ones that must not survive before this batch lands (YieldRepurchaseFacilityV2ConfigTimelockBatch.cancelQueuedAction or cancelQueuedActionEmergency); an action whose window closed meanwhile has expired and must be cancelled and queued again."
        );

        _setPostBatchValidateSelector(this._validateReEnable.selector);

        proposeBatch();
    }

    /// @notice Sets the step gas limit of the facility to the value of `env.json` (DAO MS as
    ///         `yrf_admin`, or an `admin` holder).
    /// @dev A direct `setStepGasLimit` call, without the timelock: the limit takes effect at
    ///      once, also while the facility is disabled or the configuration is frozen, since
    ///      `returnFundsToTreasury` sweeps each vault with it. Skipped when the limit already
    ///      matches. The entry point reads the scalar parameters of `env.json` only.
    ///
    ///      The heart beat is validated after the batch: every isolated step of the next beat
    ///      runs with the limit.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The contracts of the stack are not bound to each other.
    ///      - The scalar parameters of `env.json` are malformed (see
    ///        `YieldRepurchaseFacilityV2ConfigLib.desiredParameters`).
    ///      - The limit differs and the batch owner holds neither `yrf_admin` nor `admin`.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function reconcileStepGasLimit(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);

        Stack memory stack = _stack();
        uint32 desired = YieldRepurchaseFacilityV2ConfigLib
            .desiredParameters(env, chain)
            .stepGasLimit;
        uint32 live = IYieldRepurchaseFacilityV2View(stack.facility).stepGasLimit();

        console2.log("\n=== Reconcile the step gas limit of the YieldRepurchaseFacilityV2 ===");
        console2.log("YieldRepurchaseFacilityV2:", stack.facility);
        console2.log("Live step gas limit:   ", live);
        console2.log("Desired step gas limit:", desired);

        if (live == desired) {
            console2.log("The step gas limit matches env.json. Nothing to do.");
        } else {
            _requireYrfAdminOrAdmin(stack, "setStepGasLimit");
            addToBatch(
                stack.facility,
                abi.encodeWithSelector(
                    IYieldRepurchaseFacilityV2Write.setStepGasLimit.selector,
                    desired
                )
            );
            console2.log("Added: YieldRepurchaseFacilityV2.setStepGasLimit(", desired, ")");
        }
        _expectedStepGasLimit = desired;

        _setPostBatchValidateSelector(this._validateStepGasLimit.selector);

        proposeBatch();
    }

    /// @notice Transfers a token that is not part of a buyback pool, or the OHM above the
    ///         purchased amount, from the facility to the treasury (DAO MS as `yrf_admin`, or
    ///         an `admin` holder).
    /// @dev Args file: `{"functions": [{"name": "rescue", "args": {"token": "0x..."}}]}`.
    ///      The facility rescues any token in full except OHM, of which it keeps the
    ///      purchased amount that awaits its burn, and rejects the vault, the share token and
    ///      the reserve of a registered asset: those balances are the buyback pool of the
    ///      asset, and the path for them is a disable of the facility followed by
    ///      `returnFundsToTreasuryEmergencyMS`. Skipped when there is nothing to rescue.
    ///
    ///      The heart beat is validated after the batch.
    ///
    ///      Reverts if:
    ///      - The contracts of the stack are not bound to each other.
    ///      - The batch owner holds neither `yrf_admin` nor `admin`.
    ///      - The token is the vault, the share token or the reserve of a registered asset.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (must contain "rescue.token").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function rescue(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address token = _readBatchArgAddress("rescue", "token");

        Stack memory stack = _stack();
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack.facility);
        IYieldRepurchaseFacilityV2.Context memory context = facility.context();

        console2.log("\n=== Rescue a token from the YieldRepurchaseFacilityV2 ===");
        console2.log("YieldRepurchaseFacilityV2:", stack.facility);
        console2.log("Token:", token);
        console2.log("Treasury:", context.trsry);

        _requireYrfAdminOrAdmin(stack, "rescue");

        uint256 balance = IERC20(token).balanceOf(stack.facility);
        uint256 rescuable = balance;
        if (token == context.ohm) {
            // The purchased OHM awaits its burn and stays on the facility
            uint256 purchased = facility.ohmPurchased();
            rescuable = balance > purchased ? balance - purchased : 0;
            console2.log("OHM purchased and not yet burned, which stays:", purchased);
        } else {
            _requireNotPoolToken(facility, token);
        }
        console2.log("Facility balance:", balance);
        console2.log("Rescuable amount:", rescuable);

        if (rescuable == 0) {
            console2.log("Nothing to rescue. Skipping.");
        } else {
            addToBatch(
                stack.facility,
                abi.encodeWithSelector(IBasicRescueable.rescue.selector, token)
            );
            console2.log("Added: YieldRepurchaseFacilityV2.rescue(token)");
        }
        _rescuedToken = token;
        _rescueResidual = balance - rescuable;
        _expectedTreasuryBalance = IERC20(token).balanceOf(context.trsry) + rescuable;

        _setPostBatchValidateSelector(this._validateRescue.selector);

        proposeBatch();
    }

    // =========== ENTRY POINTS: EMERGENCY MS =========== //

    /// @notice Stops the purchases: disables the facility (Emergency MS).
    /// @dev The facility closes its live bond markets on a best-effort basis, its bond callback
    ///      reverts and its beats return without any effect; the buyback pools, the purchased
    ///      OHM and the accounting stay in place. Skipped when the facility is already
    ///      disabled. Recovery is `reEnable` within the grace window, which resumes the
    ///      interrupted week, or the admin `enable` path afterwards, which restarts the cycle.
    ///      `returnFundsToTreasuryEmergencyMS` moves the funds to the treasury meanwhile.
    ///
    ///      The config timelock and the configuration policy stay enabled: a matured queued
    ///      action still executes, since the configuration setters of the facility apply while
    ///      it is disabled. The run lists the unresolved actions.
    ///
    ///      The heart beat is validated after the batch; `EMERGENCY_SKIP_HEARTBEAT_VALIDATION`
    ///      set to `true` in the environment builds the lever without it, for a Heart that
    ///      fails for a reason the lever does not remove.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function stopPurchasesEmergencyMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        _applyEmergencyHeartbeatOptOut();

        Stack memory stack = _stack();
        _requireEmergencyAuthority(stack);

        console2.log("\n=== Stop the purchases: disable the YieldRepurchaseFacilityV2 ===");
        _planDisable(stack.facility, FACILITY_NAME);
        console2.log(
            "The live bond markets are closed on a best-effort basis; the buyback pools stay on the facility (returnFundsToTreasuryEmergencyMS moves them to the treasury)."
        );

        _logQueueAfterLever(stack);
        _setPostBatchValidateSelector(this._validateLifecycle.selector);

        proposeBatch();
    }

    /// @notice Freezes the configuration: disables the config timelock and the configuration
    ///         policy (Emergency MS).
    /// @dev Queueing and execution stop; the queued actions are kept, hold their keys and may
    ///      expire. The setters of the configuration policy stop for every caller, the admin
    ///      role included, while its validation functions and the cancellation on the timelock
    ///      stay available. The facility keeps operating on its current configuration. A
    ///      policy that is already disabled is skipped. Recovery is `reEnable` within the grace
    ///      window, or the admin `enable` path afterwards.
    ///
    ///      The heart beat validation is skipped: a heart beat reads neither the config
    ///      timelock nor the configuration policy.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function freezeConfigEmergencyMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the two configuration policies, which a heart beat does not read
        _skipHeartbeatValidation = true;

        Stack memory stack = _stack();
        _requireEmergencyAuthority(stack);

        console2.log(
            "\n=== Freeze the configuration: disable the config timelock and the configuration policy ==="
        );
        _planDisable(stack.timelock, TIMELOCK_NAME);
        _planDisable(stack.config, CONFIG_NAME);

        _logQueueAfterLever(stack);
        _setPostBatchValidateSelector(this._validateLifecycle.selector);

        proposeBatch();
    }

    /// @notice Halts the stack in one batch: disables the facility, the config timelock and
    ///         the configuration policy (Emergency MS).
    /// @dev The disables are planned as in `stopPurchasesEmergencyMS` and
    ///      `freezeConfigEmergencyMS`, with the same skips. The funds stay on the facility;
    ///      `returnFundsToTreasuryEmergencyMS` moves them to the treasury.
    ///
    ///      Recovery: cancel the queued actions that must not survive, then `reEnable` the
    ///      three policies within the grace window (the admin `enable` path afterwards).
    ///
    ///      The heart beat is validated after the batch; `EMERGENCY_SKIP_HEARTBEAT_VALIDATION`
    ///      set to `true` in the environment builds the lever without it.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function haltAllEmergencyMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        _applyEmergencyHeartbeatOptOut();

        Stack memory stack = _stack();
        _requireEmergencyAuthority(stack);

        console2.log(
            "\n=== Full halt: disable the facility, the config timelock and the configuration policy ==="
        );
        _planDisable(stack.facility, FACILITY_NAME);
        _planDisable(stack.timelock, TIMELOCK_NAME);
        _planDisable(stack.config, CONFIG_NAME);

        _logQueueAfterLever(stack);
        _setPostBatchValidateSelector(this._validateLifecycle.selector);

        proposeBatch();
    }

    /// @notice Returns the funds of the disabled facility to the treasury: burns the purchased
    ///         OHM and transfers every OHM, share and reserve balance (Emergency MS).
    /// @dev The stored next yields and the unfunded carries are kept, so a later `reEnable` or
    ///      `enable` refunds the facility from the treasury at the next weekly reset. Skipped
    ///      when the facility holds nothing.
    ///
    ///      Each vault is swept in an isolated step. Before every step the facility requires
    ///      `stepGasLimit + stepGasLimit / 63 + 15_000` gas to be left, whatever the step
    ///      consumes, and the whole call reverts with `InsufficientStepGas` otherwise: the run
    ///      prints the gas this takes, which a gas estimate derived from the gas used does not
    ///      cover. A vault whose sweep fails keeps its balances and emits
    ///      `FundsReturnSkipped`; the call succeeds, and the next run retries it. The
    ///      post-batch validation requires the OHM to be gone and reports every vault that
    ///      kept a balance.
    ///
    ///      The heart beat is validated after the batch; `EMERGENCY_SKIP_HEARTBEAT_VALIDATION`
    ///      set to `true` in the environment builds the lever without it.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner holds neither `emergency` nor `admin`.
    ///      - The facility is enabled.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function returnFundsToTreasuryEmergencyMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        _applyEmergencyHeartbeatOptOut();

        Stack memory stack = _stack();
        _requireEmergencyAuthority(stack);

        console2.log("\n=== Return the funds of the YieldRepurchaseFacilityV2 to the treasury ===");
        console2.log("YieldRepurchaseFacilityV2:", stack.facility);
        require(
            !IEnabler(stack.facility).isEnabled(),
            _fail(
                "the facility is enabled, and returnFundsToTreasury runs on a disabled facility only; disable it first with stopPurchasesEmergencyMS or haltAllEmergencyMS"
            )
        );

        if (!_logHoldings(stack.facility)) {
            console2.log("The facility holds nothing. Skipping.");
        } else {
            _logSweepGas(stack.facility);
            addToBatch(
                stack.facility,
                abi.encodeWithSelector(
                    IYieldRepurchaseFacilityV2Write.returnFundsToTreasury.selector
                )
            );
            console2.log("Added: YieldRepurchaseFacilityV2.returnFundsToTreasury()");
        }

        _logQueueAfterLever(stack);
        _setPostBatchValidateSelector(this._validateFundsReturned.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `reEnable`: the re-enabled flags and the wiring.
    function _validateReEnable() external view {
        console2.log("\nValidating reEnable post-batch state");
        _requireWired(_stack());
        console2.log(
            "  The three policies are active in the Kernel and bound to each other, and the config timelock is the config operator"
        );
        _requireLifecycle();
    }

    /// @notice Validates the state after `reconcileStepGasLimit`.
    function _validateStepGasLimit() external view {
        Stack memory stack = _stack();

        console2.log("\nValidating reconcileStepGasLimit post-batch state");
        uint32 live = IYieldRepurchaseFacilityV2View(stack.facility).stepGasLimit();
        require(live == _expectedStepGasLimit, "The step gas limit is not the value of env.json");
        console2.log("  The step gas limit is", live);
        console2.log("reconcileStepGasLimit post-batch validation passed");
    }

    /// @notice Validates the state after `rescue`: the facility keeps only the purchased OHM of
    ///         the token, and the treasury holds the rescued amount.
    function _validateRescue() external view {
        Stack memory stack = _stack();
        IYieldRepurchaseFacilityV2.Context memory context = IYieldRepurchaseFacilityV2View(
            stack.facility
        ).context();

        console2.log("\nValidating rescue post-batch state");
        uint256 facilityBalance = IERC20(_rescuedToken).balanceOf(stack.facility);
        require(
            facilityBalance == _rescueResidual,
            "The facility balance of the token is not the expected remainder"
        );
        uint256 treasuryBalance = IERC20(_rescuedToken).balanceOf(context.trsry);
        require(
            treasuryBalance == _expectedTreasuryBalance,
            "The treasury balance of the token did not grow by the rescued amount"
        );
        console2.log("  Facility balance:", facilityBalance);
        console2.log("  Treasury balance:", treasuryBalance);
        console2.log("rescue post-batch validation passed");
    }

    /// @notice Validates the state after `returnFundsToTreasuryEmergencyMS`: the facility holds
    ///         no OHM and tracks none as purchased. A vault that kept a balance is reported:
    ///         its sweep was skipped, which the call tolerates.
    function _validateFundsReturned() external view {
        Stack memory stack = _stack();
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack.facility);

        console2.log("\nValidating returnFundsToTreasury post-batch state");
        require(
            // The call transfers the whole OHM balance, so any remainder is a failure
            // forge-lint: disable-next-line(incorrect-strict-equality)
            IERC20(facility.context().ohm).balanceOf(stack.facility) == 0,
            "The facility still holds OHM"
        );
        require(facility.ohmPurchased() == 0, "The facility still tracks purchased OHM");
        console2.log("  The facility holds no OHM");

        address[] memory vaults = facility.getVaults();
        uint256 skipped = 0;
        for (uint256 i = 0; i < vaults.length; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility.getAssetConfig(
                vaults[i]
            );
            uint256 shares = IERC20(asset.shareToken).balanceOf(stack.facility);
            uint256 reserve = IERC20(asset.reserve).balanceOf(stack.facility);
            if (shares == 0 && reserve == 0) {
                console2.log("  Vault", vaults[i], "is swept");
                continue;
            }
            ++skipped;
            console2.log(
                "  WARNING: the sweep of vault",
                vaults[i],
                "was skipped (FundsReturnSkipped); it keeps shares and reserve:"
            );
            console2.log("   ", shares, reserve);
        }
        if (skipped > 0) {
            console2.log(
                "  WARNING: vaults that kept their balances:",
                skipped,
                "- examine the vault and run the batch again to retry"
            );
        }
        console2.log("returnFundsToTreasury post-batch validation passed");
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts unless the stack is wired for operation: the three policies active in
    ///         the Kernel and the launch bindings in place.
    function _requireWired(Stack memory stack_) internal view {
        _requireActive(
            stack_.kernel,
            stack_.config,
            CONFIG_NAME,
            "so the re-enabled stack could not be configured"
        );
        _requireActive(
            stack_.kernel,
            stack_.timelock,
            TIMELOCK_NAME,
            "so it could neither queue nor execute"
        );
        _requireActive(
            stack_.kernel,
            stack_.facility,
            FACILITY_NAME,
            "so its beats would return without any effect"
        );
        _requireLaunchBindings(stack_);
    }

    function _requireEmergencyAuthority(Stack memory stack_) internal view {
        _requireDisableAuthority(
            stack_.kernel,
            "on mainnet the Emergency MS holds emergency and the OCG timelock holds admin, and the DAO MS holds neither"
        );
    }

    /// @notice Reverts unless the batch owner holds `yrf_admin` or `admin`.
    function _requireYrfAdminOrAdmin(Stack memory stack_, string memory function_) internal view {
        ROLESv1 roles = _roles(stack_.kernel);
        require(
            roles.hasRole(_owner, YRF_ADMIN_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
            _fail(
                string.concat(
                    "the batch owner holds neither yrf_admin nor admin, the gate of ",
                    function_,
                    "(); on mainnet the DAO MS receives yrf_admin from the launch proposal"
                )
            )
        );
    }

    /// @notice Reverts when a token is the vault, the share token or the reserve of a
    ///         registered asset, which `rescue` rejects.
    function _requireNotPoolToken(
        IYieldRepurchaseFacilityV2View facility_,
        address token_
    ) internal view {
        address[] memory vaults = facility_.getVaults();
        for (uint256 i = 0; i < vaults.length; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility_.getAssetConfig(
                vaults[i]
            );
            require(
                token_ != asset.vault && token_ != asset.shareToken && token_ != asset.reserve,
                _fail(
                    string.concat(
                        "the token ",
                        vm.toString(token_),
                        " is the vault, the share token or the reserve of the registered vault ",
                        vm.toString(vaults[i]),
                        ": its balance is the buyback pool of the asset and is not rescuable; the path for it is a disable of the facility followed by returnFundsToTreasuryEmergencyMS"
                    )
                )
            );
        }
    }

    /// @notice Logs what the facility holds and returns whether it holds anything that
    ///         `returnFundsToTreasury` moves or burns.
    function _logHoldings(address facility_) internal view returns (bool holdsFunds) {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(facility_);

        uint256 ohmBalance = IERC20(facility.context().ohm).balanceOf(facility_);
        uint256 purchased = facility.ohmPurchased();
        console2.log(
            "OHM balance:",
            ohmBalance,
            "of which purchased and burned by the call:",
            purchased
        );
        holdsFunds = ohmBalance != 0 || purchased != 0;

        address[] memory vaults = facility.getVaults();
        for (uint256 i = 0; i < vaults.length; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility.getAssetConfig(
                vaults[i]
            );
            uint256 shares = IERC20(asset.shareToken).balanceOf(facility_);
            uint256 reserve = IERC20(asset.reserve).balanceOf(facility_);
            console2.log("Vault", vaults[i]);
            console2.log("  shares:", shares, "reserve:", reserve);
            if (shares != 0 || reserve != 0) holdsFunds = true;
        }
    }

    /// @notice Logs the gas `returnFundsToTreasury` needs for its isolated steps.
    /// @dev Before the sweep of each vault the facility requires
    ///      `stepGasLimit + stepGasLimit / STEP_GAS_RETENTION_DIVISOR + STEP_GAS_MARGIN` gas
    ///      to be left. The product with the vault count is an upper bound of what the steps
    ///      take together, reached when every sweep consumes its whole limit.
    function _logSweepGas(address facility_) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(facility_);
        uint256 stepGasLimit = facility.stepGasLimit();
        uint256 vaultCount = facility.getVaults().length;
        // limit + limit / 63 (kept back by the calling frame, EIP-150) + margin, in gas units
        uint256 perStep = stepGasLimit +
            stepGasLimit /
            YieldRepurchaseFacilityV2Constants.STEP_GAS_RETENTION_DIVISOR +
            YieldRepurchaseFacilityV2Constants.STEP_GAS_MARGIN;
        uint256 allSteps = perStep * vaultCount;

        console2.log(
            "\nGAS: the facility sweeps each of its",
            vaultCount,
            "vaults in an isolated step."
        );
        console2.log(
            "  Gas that has to be left before every step, whatever the step consumes:",
            perStep
        );
        console2.log("  Upper bound for all steps, on top of the OHM burn and transfer:", allSteps);
        console2.log(
            "  The whole call reverts with InsufficientStepGas below that. An estimate derived from the gas used falls short: set the gas limit of the executing transaction explicitly."
        );
        if (allSteps > TRANSACTION_GAS_LIMIT_CAP) {
            console2.log(
                "  WARNING: the upper bound exceeds the transaction gas limit of",
                TRANSACTION_GAS_LIMIT_CAP,
                "- if a sweep consumes its limit, the call cannot complete; lower the step gas limit first (reconcileStepGasLimit)."
            );
        }
    }

    /// @notice Lists the unresolved queued actions after a lever, with the sentence that fits
    ///         the lifecycle state the lever leaves the two configuration policies in.
    function _logQueueAfterLever(Stack memory stack_) internal view {
        bool frozen = !IEnabler(stack_.config).isEnabled() ||
            !IEnabler(stack_.timelock).isEnabled() ||
            _plannedDisable(stack_.config) ||
            _plannedDisable(stack_.timelock);
        _logUnresolvedQueue(
            IConfigTimelockBatchQueue(stack_.timelock),
            TIMELOCK_NAME,
            frozen
                ? "Their execution is blocked while the config timelock or the configuration policy is disabled, and each keeps its keys reserved. Before reEnable, cancel the ones that must not survive (YieldRepurchaseFacilityV2ConfigTimelockBatch.cancelQueuedAction or cancelQueuedActionEmergency); an action whose window closes meanwhile expires and must be cancelled and queued again."
                : "WARNING: the config timelock and the configuration policy are enabled, so a matured action executes permissionlessly, also on a disabled facility. Freeze the configuration with freezeConfigEmergencyMS or haltAllEmergencyMS, or cancel the actions (YieldRepurchaseFacilityV2ConfigTimelockBatch.cancelQueuedAction or cancelQueuedActionEmergency)."
        );
    }

    /// @notice Returns whether this batch plans the disable of a policy.
    function _plannedDisable(address policy_) internal view returns (bool planned) {
        uint256 length = _expectedDisabled.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_expectedDisabled[i] == policy_) return true;
        }
        return false;
    }

    // =========== HOOKS =========== //

    function _batchName() internal pure override returns (string memory name) {
        return "YieldRepurchaseFacilityV2Batch";
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
