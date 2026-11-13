// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2ConfigTimelock.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

// Contracts
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {YieldRepurchaseFacilityV2BatchScript} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2BatchScript.sol";

/// @title YieldRepurchaseFacilityV2ConfigTimelockBatch
/// @notice Declarative configuration of the YieldRepurchaseFacilityV2 through its
///         YieldRepurchaseFacilityV2ConfigTimelock. `env.json` is the desired state
///         (`olympus.config.YieldRepurchaseFacilityV2`); the facility is the live state; the
///         batch holds only the typed timelock calls that converge the two.
///
///         Entry points:
///         - `reconcile` (DAO MS as `yrf_admin`): compare the desired state with the facility,
///           field by field, and queue the minimal set of `queue*` calls: the initial
///           discount, the max price premium, and per asset its yield buyback share and its
///           enabled state, and per Clearinghouse an exclusion and an increase of its offset.
///           Each change is queued as its own action, so that one that turned stale does not
///           block the others. A pending action that already carries a change is left alone.
///           When a pending action holds a needed key with another value, or has expired, the
///           run holds its cancellations only, and the next run queues the replacements. The
///           run ends with every unresolved queued action: cancelled by this run, carrying a
///           planned change, or outside the plan, with the sub-actions that conflict with
///           `env.json` where it decides it.
///         - `queueDecreaseNextYield` (DAO MS as `yrf_admin`): queue a correction of the stored
///           next yield of one asset, from the args file. The value is not derived from
///           `env.json`.
///         - `executeReadyActions` (anyone): execute every queued action whose delay has
///           elapsed and whose execution would succeed, or only the action ids listed in the
///           args file; report the others.
///         - `cancelQueuedAction` (DAO MS as the proposer, or any owner for an expired action)
///           and `cancelQueuedActionEmergency` (Emergency MS): cancel one action by id, which
///           is the only way to release the keys of an expired or stale action.
///
///         The fields that only the admin role changes stop the run when they differ from
///         `env.json`: the grace periods, the timelock delay, the backing vault, the
///         registration and the sell-shares mode of an asset, the inclusion of a
///         Clearinghouse and a decrease of its offset. A live vault or a registry Clearinghouse
///         that `env.json` does not declare stops the run as well: the declaration has to be
///         complete before anything is queued.
///
///         Two fields of `env.json` are reconciled elsewhere and are reported here when they
///         differ: the step gas limit, by a direct call
///         (`YieldRepurchaseFacilityV2Batch.reconcileStepGasLimit`), and the backing, through
///         the timelock of the oracle (`BackingOracleConfigTimelockBatch.reconcileBacking`).
contract YieldRepurchaseFacilityV2ConfigTimelockBatch is YieldRepurchaseFacilityV2BatchScript {
    // =========== STATE =========== //

    /// @notice The scalar parameters of `env.json`, for the conflict check of the queue
    ///         listing.
    YieldRepurchaseFacilityV2ConfigLib.DesiredParameters internal _desiredParameters;

    /// @notice The Clearinghouses of `env.json`, for the conflict check of the queue listing.
    YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] internal _desiredClearinghouses;

    /// @notice The facility, whose live offsets the conflict check of the queue listing reads.
    address internal _listedFacility;

    // =========== ENTRY POINTS =========== //

    /// @notice Queues the timelock actions that converge the facility to `env.json`, or
    ///         cancels the pending actions that stand in their way (DAO MS as `yrf_admin`).
    /// @dev Every planned change is checked with the validation function of the configuration
    ///      policy for its setter before it is planned, so that a rejection carries the error
    ///      of the contracts.
    ///
    ///      An `enableAsset` zeroes the stored next yield and the unfunded carry of its vault
    ///      and refreshes its yield snapshots, and a `disableAsset` closes the live bond
    ///      market of its vault; the plan prints a warning for both. An `enableAsset` reserves
    ///      the next yield domain of its vault, which a queued `decreaseNextYield` holds: such
    ///      a holder stops the run instead of being cancelled, since it was queued from an
    ///      args file.
    ///
    ///      A run that cancels at least one pending action holds the cancellations only: the
    ///      plan output lists the replacements, and they are queued by the next run once the
    ///      cancellations have landed. A cancellation of an action that executed in between
    ///      reverts with `ITimelockBatchQueue_ActionAlreadyExecuted` and fails the batch; the
    ///      next run plans from the resulting state.
    ///
    ///      The heart beat validation is skipped: the batch queues and cancels, and the
    ///      facility keeps its configuration until a queued action executes.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The contracts of the stack are not bound to each other.
    ///      - The configuration policy or the config timelock is not active in the Kernel or
    ///        is disabled, or the launch bindings do not hold.
    ///      - The batch owner does not hold `yrf_admin`.
    ///      - The desired state is malformed (see `YieldRepurchaseFacilityV2ConfigLib`).
    ///      - A field that only the admin role changes differs from `env.json`.
    ///      - A live vault, or a Clearinghouse of the CHREG registry, is not declared in
    ///        `env.json`, or a declared Clearinghouse is not in the registry.
    ///      - The configuration policy rejects a planned change.
    ///      - An unexpired `decreaseNextYield` action holds a key of a planned change.
    ///      - A pending action holds a needed key with another value and the batch owner may
    ///        not cancel it.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function reconcile(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the queue of the config timelock
        _skipHeartbeatValidation = true;

        Stack memory stack = _stack();
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);
        _rememberDesired(stack, desired);

        console2.log(
            "\n=== Reconcile the YieldRepurchaseFacilityV2 through its config timelock ==="
        );
        console2.log("YieldRepurchaseFacilityV2:", stack.facility);
        console2.log("YieldRepurchaseFacilityV2Config:", stack.config);
        console2.log("YieldRepurchaseFacilityV2ConfigTimelock:", stack.timelock);

        _requireQueueable(stack);

        _logLive(stack);
        _logDesired(desired);

        _requireAdminFieldsMatch(stack, desired);
        _requireLiveDeclared(stack, desired);

        console2.log("\n--- Plan ---");
        _planParameters(stack, desired.parameters);
        for (uint256 i = 0; i < desired.assets.length; ++i) {
            _planAsset(stack, desired.assets[i]);
        }
        for (uint256 i = 0; i < desired.clearinghouses.length; ++i) {
            _planClearinghouse(stack, desired.clearinghouses[i]);
        }
        _logFieldsReconciledElsewhere(stack, desired.parameters);

        _reconcileQueue(
            IConfigTimelockBatchQueue(stack.timelock),
            stack.kernel,
            "reconcile",
            "No change needed: the fields the config timelock governs match env.json. This describes the facility state only; the unresolved queued actions are listed below."
        );

        proposeBatch();
    }

    /// @notice Queues a correction that lowers the stored next yield of one asset (DAO MS as
    ///         `yrf_admin`).
    /// @dev Args file:
    ///      `{"functions": [{"name": "queueDecreaseNextYield", "args": {"asset": "sUSDS",
    ///      "expectedNextYield": "1000000000000000000000", "newNextYield": "0"}}]}`, with the
    ///      asset named as under `assets` in `env.json` and both values in reserve units. The
    ///      stored next yield has to equal `expectedNextYield` when the action is queued and
    ///      when it executes: a weekly reset that replaces the stored value in between makes
    ///      the action stale, and it then holds the next yield domain of the vault until it is
    ///      cancelled. A run with an unexpired pending action that carries the same correction
    ///      adds nothing.
    ///
    ///      The heart beat validation is skipped: the batch queues, and the facility keeps its
    ///      stored next yield until the action executes.
    ///
    ///      Reverts if:
    ///      - The contracts of the stack are not bound to each other.
    ///      - The configuration policy or the config timelock is not active in the Kernel or
    ///        is disabled, or the launch bindings do not hold.
    ///      - The batch owner does not hold `yrf_admin`.
    ///      - The args name an asset that `env.json` does not declare.
    ///      - The configuration policy rejects the correction (`validateDecreaseNextYield`).
    ///      - Another unresolved action holds the next yield domain of the vault: a pending
    ///        `enableAsset`, or a `decreaseNextYield` with other values or one that expired.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (must contain
    ///        "queueDecreaseNextYield.asset", ".expectedNextYield" and ".newNextYield").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function queueDecreaseNextYield(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The batch touches only the queue of the config timelock
        _skipHeartbeatValidation = true;

        Stack memory stack = _stack();
        (
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets,

        ) = YieldRepurchaseFacilityV2ConfigLib.desiredAssets(env, chain);
        _rememberAssets(assets);

        string memory assetName = _readBatchArgString("queueDecreaseNextYield", "asset");
        uint256 expected = _readBatchArgUint256("queueDecreaseNextYield", "expectedNextYield");
        uint256 newValue = _readBatchArgUint256("queueDecreaseNextYield", "newNextYield");
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset
        ) = YieldRepurchaseFacilityV2ConfigLib.findAssetByName(assets, assetName);
        require(
            declared,
            _fail(
                string.concat(
                    "the args name the asset ",
                    assetName,
                    ", which env.json does not declare under olympus.config.YieldRepurchaseFacilityV2.assets"
                )
            )
        );

        console2.log("\n=== Queue a next yield correction through the config timelock ===");
        console2.log("Asset:", _vaultLabel(asset.vault));
        console2.log("Expected stored next yield:", expected);
        console2.log("New next yield:            ", newValue);

        _requireQueueable(stack);

        console2.log("\n--- Plan ---");
        // Surface the validation of the configuration policy before queueing
        IYieldRepurchaseFacilityV2Config(stack.config).validateDecreaseNextYield(
            asset.vault,
            expected,
            newValue
        );
        _addPlanned(
            string.concat(
                "decreaseNextYield(",
                asset.name,
                ", ",
                vm.toString(expected),
                ", ",
                vm.toString(newValue),
                ")"
            ),
            _configCall(
                stack.config,
                IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector,
                abi.encode(asset.vault, expected, newValue)
            ),
            abi.encodeCall(
                IYieldRepurchaseFacilityV2ConfigTimelock.queueDecreaseNextYield,
                (asset.vault, expected, newValue)
            ),
            _singleKey(
                _entityKey(
                    stack,
                    IYieldRepurchaseFacilityV2ConfigTimelock(stack.timelock).NEXT_YIELD_DOMAIN(),
                    asset.vault
                )
            )
        );
        console2.log(
            "  A weekly reset that replaces the stored next yield before the execution makes the action stale; it then holds the next yield domain of the vault until it is cancelled."
        );

        _queueImperative(IConfigTimelockBatchQueue(stack.timelock));

        proposeBatch();
    }

    /// @notice Executes the queued actions whose delay has elapsed, whose window has not closed
    ///         and whose execution succeeds in a dry run: every such action, or only the
    ///         listed ones when the args file names them. Anyone may run it.
    /// @dev Args file (optional):
    ///      `{"functions": [{"name": "executeReadyActions", "args": {"actionIds": [1]}}]}`
    ///      restricts the run to the listed ids. An action that does not exist, is executed or
    ///      cancelled, is not ready, has expired, or would revert (for instance with
    ///      `ConfigStateChanged` after the guarded field moved, or `NotEnabled` while a policy
    ///      is disabled) is reported with the reason and left out; an expired or stale action
    ///      keeps its keys until it is cancelled. The execution does not require the facility
    ///      enabled: its configuration setters apply while it is disabled.
    ///
    ///      The heart beat is validated after the batch: an executed action changes the
    ///      configuration the facility reads at its next beat.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner; any owner may execute.
    /// @param argsFile_ Path to the arguments file (optional; may carry
    ///        "executeReadyActions.actionIds").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function executeReadyActions(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        Stack memory stack = _stack();
        _planExecuteReady(
            IConfigTimelockBatchQueue(stack.timelock),
            TIMELOCK_NAME,
            "executeReadyActions"
        );
        proposeBatch();
    }

    /// @notice Cancels one queued action (DAO MS as the proposer of the action, or any `admin`
    ///         or `emergency` holder as owner; any owner once the action has expired).
    /// @dev Args file: `{"functions": [{"name": "cancelQueuedAction", "args": {"actionId": 1}}]}`.
    ///      A cancellation is available while the timelock is disabled. The heart beat
    ///      validation is skipped: a cancellation changes nothing that a heart beat reads.
    ///
    ///      Reverts if:
    ///      - The timelock is not active in the Kernel.
    ///      - The action does not exist, or is already executed or cancelled.
    ///      - The action has not expired and the batch owner is neither the proposer nor an
    ///        `admin` or `emergency` holder.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (must contain "cancelQueuedAction.actionId").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function cancelQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _planCancel("cancelQueuedAction");
        proposeBatch();
    }

    /// @notice Cancels one queued action with the Emergency MS as owner.
    /// @dev Same behaviour and args file as `cancelQueuedAction`, under the function name
    ///      `cancelQueuedActionEmergency`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (must contain
    ///        "cancelQueuedActionEmergency.actionId").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function cancelQueuedActionEmergency(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _planCancel("cancelQueuedActionEmergency");
        proposeBatch();
    }

    // =========== PRECONDITIONS =========== //

    /// @notice Reverts unless a `queue*` call from the batch owner would pass the gates of the
    ///         config timelock: both policies active in the Kernel and enabled, the caller
    ///         holding `yrf_admin`, and the timelock named as the config operator.
    function _requireQueueable(Stack memory stack_) internal view {
        _requireLaunchBindings(stack_);
        _requireControlPlaneEnabled(stack_);
        require(
            _roles(stack_.kernel).hasRole(_owner, YRF_ADMIN_ROLE),
            _fail(
                "the batch owner does not hold yrf_admin, the only role the queue of the config timelock accepts (the admin role does not queue); on mainnet the DAO MS receives yrf_admin from the launch proposal"
            )
        );
    }

    /// @notice Reverts when a field that only the admin role changes differs from `env.json`.
    /// @dev Covers the grace periods (`setGracePeriod`), the timelock delay
    ///      (`setTimelockDelay`), the backing vault (`setBackingVault`), the registration
    ///      (`addAsset`) and the sell-shares mode (`setSellShares`) of an asset, the inclusion
    ///      of a Clearinghouse (`includeClearinghouse`) and a decrease of its offset
    ///      (`setClearinghouseOffset`).
    function _requireAdminFieldsMatch(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory desired_
    ) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack_.facility);

        _requireAdminUint(
            "the grace period of the facility",
            IGracePeriod(stack_.facility).gracePeriod(),
            desired_.parameters.gracePeriod,
            "gracePeriod"
        );
        _requireAdminUint(
            "the grace period of the configuration policy",
            IGracePeriod(stack_.config).gracePeriod(),
            desired_.parameters.gracePeriod,
            "gracePeriod"
        );
        _requireAdminUint(
            "the grace period of the config timelock",
            IGracePeriod(stack_.timelock).gracePeriod(),
            desired_.parameters.gracePeriod,
            "gracePeriod"
        );
        _requireAdminUint(
            "the delay of the config timelock",
            ITimelockBatchQueue(stack_.timelock).timelockDelay(),
            desired_.parameters.timelockDelay,
            "timelockDelay"
        );

        address liveBackingVault = facility.backingVault();
        require(
            liveBackingVault == desired_.backingVault,
            _adminMismatch(
                string.concat(
                    "the backing vault of the facility is ",
                    _vaultLabel(liveBackingVault),
                    ", while env.json declares ",
                    _vaultLabel(desired_.backingVault)
                ),
                "backingVault"
            )
        );

        for (uint256 i = 0; i < desired_.assets.length; ++i) {
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset = desired_.assets[i];
            require(
                _isRegistered(facility, asset.vault),
                _adminMismatch(
                    string.concat(
                        "the asset ",
                        _vaultLabel(asset.vault),
                        " is declared in env.json but is not registered on the facility (addAsset)"
                    ),
                    string.concat("assets.", asset.name)
                )
            );
            require(
                facility.getAssetConfig(asset.vault).sellShares == asset.sellShares,
                _adminMismatch(
                    string.concat(
                        "the sell-shares mode of the asset ",
                        _vaultLabel(asset.vault),
                        " differs from env.json (setSellShares)"
                    ),
                    string.concat("assets.", asset.name, ".sellShares")
                )
            );
        }

        for (uint256 i = 0; i < desired_.clearinghouses.length; ++i) {
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry = desired_
                .clearinghouses[i];
            require(
                !entry.included || facility.isClearinghouseIncluded(entry.clearinghouse),
                _adminMismatch(
                    string.concat(
                        "the Clearinghouse ",
                        vm.toString(entry.clearinghouse),
                        " is declared with included: true but is not included on the facility (includeClearinghouse)"
                    ),
                    string.concat("clearinghouses[", vm.toString(i), "].included")
                )
            );
            uint256 liveOffset = facility.clearinghouseOffset(entry.clearinghouse);
            require(
                entry.offset >= liveOffset,
                _adminMismatch(
                    string.concat(
                        "the offset of the Clearinghouse ",
                        vm.toString(entry.clearinghouse),
                        " is ",
                        vm.toString(liveOffset),
                        ", while env.json declares the lower value ",
                        vm.toString(entry.offset),
                        " (setClearinghouseOffset)"
                    ),
                    string.concat("clearinghouses[", vm.toString(i), "].offset")
                )
            );
        }
    }

    function _requireAdminUint(
        string memory subject_,
        uint256 live_,
        uint256 desired_,
        string memory key_
    ) internal pure {
        require(
            live_ == desired_,
            _adminMismatch(
                string.concat(
                    subject_,
                    " is ",
                    vm.toString(live_),
                    ", while env.json declares ",
                    vm.toString(desired_)
                ),
                key_
            )
        );
    }

    /// @notice Words the failure of a field that only the admin role changes.
    function _adminMismatch(
        string memory difference_,
        string memory key_
    ) internal pure returns (string memory message) {
        return
            _fail(
                string.concat(
                    difference_,
                    "; only the admin role changes this field (an OCG proposal on mainnet), so the run stops: change the chain through a proposal, or align olympus.config.YieldRepurchaseFacilityV2.",
                    key_,
                    " with the chain"
                )
            );
    }

    /// @notice Reverts when the live state holds something `env.json` does not declare: a
    ///         registered vault, or a Clearinghouse of the CHREG registry. Nothing is derived
    ///         from an absence, so the declaration must name every live vault and every
    ///         registry Clearinghouse.
    function _requireLiveDeclared(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory desired_
    ) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack_.facility);

        address[] memory vaults = facility.getVaults();
        for (uint256 i = 0; i < vaults.length; ++i) {
            (bool declared, ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(
                desired_.assets,
                vaults[i]
            );
            require(
                declared,
                _fail(
                    string.concat(
                        "the registered vault ",
                        vm.toString(vaults[i]),
                        " is not declared in env.json; declare it under olympus.config.YieldRepurchaseFacilityV2.assets with its token under external.tokens (enabled: false queues its disable; a removal is an admin call)"
                    )
                )
            );
        }

        CHREGv1 chreg = CHREGv1(facility.context().chreg);
        uint256 registryCount = chreg.registryCount();
        for (uint256 i = 0; i < registryCount; ++i) {
            address clearinghouse = chreg.registry(i);
            (bool declared, ) = YieldRepurchaseFacilityV2ConfigLib.findClearinghouse(
                desired_.clearinghouses,
                clearinghouse
            );
            require(
                declared,
                _fail(
                    string.concat(
                        "the Clearinghouse ",
                        vm.toString(clearinghouse),
                        " of the CHREG registry is not declared in env.json; declare it under olympus.config.YieldRepurchaseFacilityV2.clearinghouses with its inclusion and offset"
                    )
                )
            );
        }
        // No declared address repeats, so equal lengths with every registry entry declared
        // leave no declared Clearinghouse outside the registry
        require(
            desired_.clearinghouses.length == registryCount,
            _fail(
                string.concat(
                    "env.json declares ",
                    vm.toString(desired_.clearinghouses.length),
                    " Clearinghouses, while the CHREG registry holds ",
                    vm.toString(registryCount),
                    "; olympus.config.YieldRepurchaseFacilityV2.clearinghouses must list exactly the registry"
                )
            )
        );
    }

    function _isRegistered(
        IYieldRepurchaseFacilityV2View facility_,
        address vault_
    ) internal view returns (bool registered) {
        address[] memory vaults = facility_.getVaults();
        for (uint256 i = 0; i < vaults.length; ++i) {
            if (vaults[i] == vault_) return true;
        }
        return false;
    }

    // =========== PLANNING =========== //

    function _planParameters(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory desired_
    ) internal {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack_.facility);
        IYieldRepurchaseFacilityV2Config config = IYieldRepurchaseFacilityV2Config(stack_.config);
        IYieldRepurchaseFacilityV2ConfigTimelock timelock = IYieldRepurchaseFacilityV2ConfigTimelock(
                stack_.timelock
            );

        uint256 liveDiscount = facility.initialDiscount();
        if (liveDiscount == desired_.initialDiscount) {
            console2.log("\nInitial discount: matches env.json.");
        } else {
            console2.log(
                "\nInitial discount: live",
                liveDiscount,
                "desired",
                desired_.initialDiscount
            );
            // Surface the validation of the configuration policy before queueing
            config.validateSetInitialDiscount(desired_.initialDiscount);
            _addPlanned(
                string.concat("setInitialDiscount(", vm.toString(desired_.initialDiscount), ")"),
                _configCall(
                    stack_.config,
                    IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector,
                    abi.encode(desired_.initialDiscount)
                ),
                abi.encodeCall(
                    IYieldRepurchaseFacilityV2ConfigTimelock.queueSetInitialDiscount,
                    (desired_.initialDiscount)
                ),
                _singleKey(_globalKey(stack_, timelock.INITIAL_DISCOUNT_DOMAIN()))
            );
        }

        uint256 livePremium = facility.maxPricePremium();
        if (livePremium == desired_.maxPricePremium) {
            console2.log("Max price premium: matches env.json.");
        } else {
            console2.log(
                "Max price premium: live",
                livePremium,
                "desired",
                desired_.maxPricePremium
            );
            config.validateSetMaxPricePremium(desired_.maxPricePremium);
            _addPlanned(
                string.concat("setMaxPricePremium(", vm.toString(desired_.maxPricePremium), ")"),
                _configCall(
                    stack_.config,
                    IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector,
                    abi.encode(desired_.maxPricePremium)
                ),
                abi.encodeCall(
                    IYieldRepurchaseFacilityV2ConfigTimelock.queueSetMaxPricePremium,
                    (desired_.maxPricePremium)
                ),
                _singleKey(_globalKey(stack_, timelock.MAX_PRICE_PREMIUM_DOMAIN()))
            );
        }
    }

    /// @notice Plans the enabled state and the yield buyback share of one asset, each as its
    ///         own action.
    function _planAsset(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset_
    ) internal {
        IYieldRepurchaseFacilityV2.ReserveAsset memory live = IYieldRepurchaseFacilityV2View(
            stack_.facility
        ).getAssetConfig(asset_.vault);
        console2.log(string.concat("\nAsset ", _vaultLabel(asset_.vault)));

        if (
            live.isAssetEnabled == asset_.enabled &&
            live.yieldBuybackShare == asset_.yieldBuybackShare
        ) {
            console2.log("  Matches env.json. Nothing to do.");
            return;
        }
        if (live.isAssetEnabled != asset_.enabled) _planAssetStatus(stack_, asset_);
        if (live.yieldBuybackShare != asset_.yieldBuybackShare) {
            console2.log(
                "  Yield buyback share: live",
                live.yieldBuybackShare,
                "desired",
                asset_.yieldBuybackShare
            );
            IYieldRepurchaseFacilityV2Config(stack_.config).validateSetYieldBuybackShare(
                asset_.vault,
                asset_.yieldBuybackShare
            );
            _addPlanned(
                string.concat(
                    "setYieldBuybackShare(",
                    asset_.name,
                    ", ",
                    vm.toString(asset_.yieldBuybackShare),
                    ")"
                ),
                _configCall(
                    stack_.config,
                    IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector,
                    abi.encode(asset_.vault, asset_.yieldBuybackShare)
                ),
                abi.encodeCall(
                    IYieldRepurchaseFacilityV2ConfigTimelock.queueSetYieldBuybackShare,
                    (asset_.vault, asset_.yieldBuybackShare)
                ),
                _singleKey(
                    _entityKey(
                        stack_,
                        IYieldRepurchaseFacilityV2ConfigTimelock(stack_.timelock)
                            .YIELD_BUYBACK_SHARE_DOMAIN(),
                        asset_.vault
                    )
                )
            );
        }
    }

    /// @notice Plans the `enableAsset` or the `disableAsset` of one asset, with the warning of
    ///         what the call does beyond the flag.
    function _planAssetStatus(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset_
    ) internal {
        IYieldRepurchaseFacilityV2Config config = IYieldRepurchaseFacilityV2Config(stack_.config);
        IYieldRepurchaseFacilityV2ConfigTimelock timelock = IYieldRepurchaseFacilityV2ConfigTimelock(
                stack_.timelock
            );
        bytes32 statusKey = _entityKey(stack_, timelock.ASSET_STATUS_DOMAIN(), asset_.vault);

        if (asset_.enabled) {
            console2.log("  Disabled on the facility, declared with enabled: true.");
            console2.log(
                "  WARNING: enableAsset zeroes the stored next yield and the unfunded carry of the vault and refreshes its yield snapshots; the yield projection resumes at the following weekly reset."
            );
            config.validateEnableAsset(asset_.vault);
            // enableAsset reserves the status domain and the next yield domain of its vault
            bytes32[] memory keys = new bytes32[](2);
            keys[0] = statusKey;
            keys[1] = _entityKey(stack_, timelock.NEXT_YIELD_DOMAIN(), asset_.vault);
            _addPlanned(
                string.concat("enableAsset(", asset_.name, ")"),
                _configCall(
                    stack_.config,
                    IYieldRepurchaseFacilityV2Config.enableAsset.selector,
                    abi.encode(asset_.vault)
                ),
                abi.encodeCall(
                    IYieldRepurchaseFacilityV2ConfigTimelock.queueEnableAsset,
                    (asset_.vault)
                ),
                keys
            );
            return;
        }

        console2.log("  Enabled on the facility, declared with enabled: false.");
        console2.log(
            "  WARNING: disableAsset closes the live bond market of the vault on a best-effort basis and stops its weekly and daily cycles; its buyback pool and accounting stay in place."
        );
        config.validateDisableAsset(asset_.vault);
        _addPlanned(
            string.concat("disableAsset(", asset_.name, ")"),
            _configCall(
                stack_.config,
                IYieldRepurchaseFacilityV2Config.disableAsset.selector,
                abi.encode(asset_.vault)
            ),
            abi.encodeCall(
                IYieldRepurchaseFacilityV2ConfigTimelock.queueDisableAsset,
                (asset_.vault)
            ),
            _singleKey(statusKey)
        );
    }

    /// @notice Plans the exclusion and the offset increase of one Clearinghouse, each as its
    ///         own action. An inclusion and an offset decrease are admin calls, which
    ///         `_requireAdminFieldsMatch` rejects before the plan.
    function _planClearinghouse(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry_
    ) internal {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack_.facility);
        IYieldRepurchaseFacilityV2Config config = IYieldRepurchaseFacilityV2Config(stack_.config);
        IYieldRepurchaseFacilityV2ConfigTimelock timelock = IYieldRepurchaseFacilityV2ConfigTimelock(
                stack_.timelock
            );
        address clearinghouse = entry_.clearinghouse;
        bool liveIncluded = facility.isClearinghouseIncluded(clearinghouse);
        uint256 liveOffset = facility.clearinghouseOffset(clearinghouse);
        console2.log("\nClearinghouse", clearinghouse);

        if (liveIncluded == entry_.included && liveOffset == entry_.offset) {
            console2.log("  Matches env.json. Nothing to do.");
            return;
        }
        if (liveIncluded && !entry_.included) {
            console2.log("  Included on the facility, declared with included: false.");
            config.validateExcludeClearinghouse(clearinghouse);
            _addPlanned(
                string.concat("excludeClearinghouse(", vm.toString(clearinghouse), ")"),
                _configCall(
                    stack_.config,
                    IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector,
                    abi.encode(clearinghouse)
                ),
                abi.encodeCall(
                    IYieldRepurchaseFacilityV2ConfigTimelock.queueExcludeClearinghouse,
                    (clearinghouse)
                ),
                _singleKey(
                    _entityKey(stack_, timelock.CLEARINGHOUSE_INCLUSION_DOMAIN(), clearinghouse)
                )
            );
        }
        if (entry_.offset > liveOffset) {
            // desired offset - live offset -> the amount to add, in the units of the receivables
            uint256 additional = entry_.offset - liveOffset;
            console2.log("  Offset: live", liveOffset, "desired", entry_.offset);
            config.validateIncreaseClearinghouseOffset(clearinghouse, additional);
            _addPlanned(
                string.concat(
                    "increaseClearinghouseOffset(",
                    vm.toString(clearinghouse),
                    ", ",
                    vm.toString(additional),
                    ")"
                ),
                _configCall(
                    stack_.config,
                    IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector,
                    abi.encode(clearinghouse, additional)
                ),
                abi.encodeCall(
                    IYieldRepurchaseFacilityV2ConfigTimelock.queueIncreaseClearinghouseOffset,
                    (clearinghouse, additional)
                ),
                _singleKey(
                    _entityKey(stack_, timelock.CLEARINGHOUSE_OFFSET_DOMAIN(), clearinghouse)
                )
            );
        }
    }

    /// @notice Queues the one imperative change of the plan, unless an unexpired pending
    ///         action already carries it. Any other holder of its key stops the run: an
    ///         imperative entry point cancels nothing.
    function _queueImperative(IConfigTimelockBatchQueue timelock_) internal {
        Planned storage planned = _plan[0];

        console2.log("\n--- Queue ---");
        uint64 pendingId = timelock_.pendingActionId(planned.keys[0]);
        if (pendingId == 0) {
            addToBatch(address(timelock_), planned.queueCall);
            console2.log("  Added to the batch");
        } else {
            ITimelockBatchQueue.QueuedAction memory pending = timelock_.getQueuedAction(pendingId);
            bool expired = vm.getBlockTimestamp() > pending.expiresAt;
            require(
                !expired && _holdsChange(pending, planned),
                _fail(
                    string.concat(
                        "the next yield domain of the vault is reserved by action ",
                        vm.toString(pendingId),
                        " (",
                        _describeSubAction(pending.actions[0]),
                        expired ? ", expired" : "",
                        "); execute it once it is ready, or cancel it with cancelQueuedAction, then run again"
                    )
                )
            );
            console2.log(
                "  Already queued as action",
                pendingId,
                "executable at",
                pending.executableAt
            );
            planned.skipped = true;
        }

        _logUnresolvedQueue(
            timelock_,
            TIMELOCK_NAME,
            "Each unresolved action executes permissionlessly once it is ready, unless it is cancelled (cancelQueuedAction)."
        );
        _validatedTimelock = address(timelock_);
        _setPostBatchValidateSelector(this._validateReconcile.selector);
    }

    function _planCancel(string memory functionName_) internal {
        // A cancellation changes nothing that a heart beat reads
        _skipHeartbeatValidation = true;

        Stack memory stack = _stack();
        _planCancelById(
            IConfigTimelockBatchQueue(stack.timelock),
            stack.kernel,
            TIMELOCK_NAME,
            functionName_
        );
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Keeps the desired state for the queue listing: the asset names, the scalar
    ///         parameters, the Clearinghouses and the facility whose offsets it reads.
    function _rememberDesired(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory desired_
    ) internal {
        _rememberAssets(desired_.assets);
        _desiredParameters = desired_.parameters;
        for (uint256 i = 0; i < desired_.clearinghouses.length; ++i) {
            _desiredClearinghouses.push(desired_.clearinghouses[i]);
        }
        _listedFacility = stack_.facility;
    }

    /// @notice Builds one call of the configuration policy.
    function _configCall(
        address config_,
        bytes4 selector_,
        bytes memory payload_
    ) internal pure returns (ITimelockBatchQueue.BatchAction memory call) {
        return
            ITimelockBatchQueue.BatchAction({
                target: config_,
                selector: selector_,
                payload: payload_
            });
    }

    // =========== LOGGING =========== //

    function _logLive(Stack memory stack_) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack_.facility);

        console2.log("\n--- Live state of the facility ---");
        console2.log("  initial discount:", facility.initialDiscount());
        console2.log("  max price premium:", facility.maxPricePremium());
        console2.log("  step gas limit:", facility.stepGasLimit());
        console2.log("  backing vault:", _vaultLabel(facility.backingVault()));

        address[] memory vaults = facility.getVaults();
        for (uint256 i = 0; i < vaults.length; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility.getAssetConfig(
                vaults[i]
            );
            console2.log(string.concat("  vault ", _vaultLabel(vaults[i])));
            console2.log("    enabled:", asset.isAssetEnabled, "sell shares:", asset.sellShares);
            console2.log("    yield buyback share:", asset.yieldBuybackShare);
            console2.log("    stored next yield:", asset.nextYield);
        }

        CHREGv1 chreg = CHREGv1(facility.context().chreg);
        uint256 registryCount = chreg.registryCount();
        for (uint256 i = 0; i < registryCount; ++i) {
            address clearinghouse = chreg.registry(i);
            console2.log("  Clearinghouse", clearinghouse);
            console2.log(
                "    included:",
                facility.isClearinghouseIncluded(clearinghouse),
                "offset:",
                facility.clearinghouseOffset(clearinghouse)
            );
        }
    }

    function _logDesired(
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory desired_
    ) internal view {
        console2.log("\n--- Desired state in env.json ---");
        console2.log("  initial discount:", desired_.parameters.initialDiscount);
        console2.log("  max price premium:", desired_.parameters.maxPricePremium);
        console2.log("  step gas limit:", desired_.parameters.stepGasLimit);
        console2.log("  backing vault:", _vaultLabel(desired_.backingVault));
        for (uint256 i = 0; i < desired_.assets.length; ++i) {
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset = desired_.assets[i];
            console2.log(string.concat("  vault ", _vaultLabel(asset.vault)));
            console2.log("    enabled:", asset.enabled, "sell shares:", asset.sellShares);
            console2.log("    yield buyback share:", asset.yieldBuybackShare);
        }
        for (uint256 i = 0; i < desired_.clearinghouses.length; ++i) {
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry = desired_
                .clearinghouses[i];
            console2.log("  Clearinghouse", entry.clearinghouse);
            console2.log("    included:", entry.included, "offset:", entry.offset);
        }
    }

    /// @notice Reports the two fields of `env.json` that other entry points reconcile, when
    ///         they differ from the chain.
    function _logFieldsReconciledElsewhere(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory desired_
    ) internal view {
        uint32 liveStepGasLimit = IYieldRepurchaseFacilityV2View(stack_.facility).stepGasLimit();
        if (liveStepGasLimit != desired_.stepGasLimit) {
            console2.log(
                "\nNOTE: the step gas limit of the facility is",
                liveStepGasLimit,
                "while env.json declares",
                desired_.stepGasLimit
            );
            console2.log(
                "  It is set by a direct call, without the timelock: YieldRepurchaseFacilityV2Batch.reconcileStepGasLimit."
            );
        }

        string memory backingPath = BackingOracleConfigLib.backingPath(chain);
        if (!vm.keyExistsJson(env, backingPath)) return;
        uint256 desiredBacking = BackingOracleConfigLib.desiredBacking(env, chain);
        uint256 liveBacking = IBackingOracle(stack_.oracle).backing();
        if (liveBacking != desiredBacking) {
            console2.log(
                "\nNOTE: the backing of the oracle is",
                liveBacking,
                "while env.json declares",
                desiredBacking
            );
            console2.log(
                "  It runs through the timelock of the oracle: BackingOracleConfigTimelockBatch.reconcileBacking."
            );
        }
    }

    // =========== HOOKS =========== //

    function _batchName() internal pure override returns (string memory name) {
        return "YieldRepurchaseFacilityV2ConfigTimelockBatch";
    }

    /// @notice An action that carries a `decreaseNextYield` was queued from an args file: its
    ///         values are not derived from `env.json`.
    function _isImperative(
        ITimelockBatchQueue.QueuedAction memory action_
    ) internal pure override returns (bool imperative) {
        for (uint256 i = 0; i < action_.actions.length; ++i) {
            if (
                action_.actions[i].selector ==
                IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector
            ) return true;
        }
        return false;
    }

    /// @notice Compares a queued operator setter with the desired state of `env.json`.
    function _conflict(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal view override returns (string memory verdict) {
        bytes4 selector = sub_.selector;
        bytes memory payload = sub_.payload;

        if (selector == IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector) {
            return
                abi.decode(payload, (uint256)) == _desiredParameters.initialDiscount
                    ? ""
                    : "CONFLICT: sets an initial discount that differs from env.json";
        }
        if (selector == IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector) {
            return
                abi.decode(payload, (uint256)) == _desiredParameters.maxPricePremium
                    ? ""
                    : "CONFLICT: sets a max price premium that differs from env.json";
        }
        if (selector == IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector) {
            return "is not checked: env.json declares no next yield";
        }
        if (
            selector == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector ||
            selector == IYieldRepurchaseFacilityV2Config.enableAsset.selector ||
            selector == IYieldRepurchaseFacilityV2Config.disableAsset.selector
        ) return _assetConflict(selector, payload);
        if (
            selector == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector ||
            selector == IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector
        ) return _clearinghouseConflict(selector, payload);
        return "is not checked: not an operator setter of the configuration policy";
    }

    function _assetConflict(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (string memory verdict) {
        // The vault is the first word of the payload of the three asset setters
        address vault = abi.decode(payload_, (address));
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(_namedAssets, vault);
        if (!declared) return "CONFLICT: its vault is not declared in env.json";

        if (selector_ == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector) {
            (, uint256 share) = abi.decode(payload_, (address, uint256));
            return
                share == asset.yieldBuybackShare
                    ? ""
                    : "CONFLICT: sets a yield buyback share that differs from env.json";
        }
        if (selector_ == IYieldRepurchaseFacilityV2Config.enableAsset.selector) {
            return asset.enabled ? "" : "CONFLICT: enables an asset declared with enabled: false";
        }
        return asset.enabled ? "CONFLICT: disables an asset declared with enabled: true" : "";
    }

    function _clearinghouseConflict(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (string memory verdict) {
        // The Clearinghouse is the first word of the payload of both Clearinghouse setters
        address clearinghouse = abi.decode(payload_, (address));
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        ) = YieldRepurchaseFacilityV2ConfigLib.findClearinghouse(
                _desiredClearinghouses,
                clearinghouse
            );
        if (!declared) return "CONFLICT: its Clearinghouse is not declared in env.json";

        if (selector_ == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector) {
            return
                entry.included
                    ? "CONFLICT: excludes a Clearinghouse declared with included: true"
                    : "";
        }
        (, uint256 additional) = abi.decode(payload_, (address, uint256));
        // live offset + queued increase -> the offset the action leaves
        uint256 resulting = IYieldRepurchaseFacilityV2View(_listedFacility).clearinghouseOffset(
            clearinghouse
        ) + additional;
        return
            resulting == entry.offset
                ? ""
                : "CONFLICT: raises the offset to a value that differs from env.json";
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
