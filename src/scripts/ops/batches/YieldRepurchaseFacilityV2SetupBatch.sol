// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors, one-contract-per-file
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IClearinghouseReserve} from "src/policies/interfaces/IClearinghouseReserve.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepoV1} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepoV1.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2Lens} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Lens.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2Constants.sol";
import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

// Contracts
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {YieldRepurchaseFacilityV2BatchScript} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2BatchScript.sol";

// The one-function interface of the auctioneer owner is declared next to its only consumer
// forge-lint: disable-start(multi-contract-file)

/// @notice The owner getter of the Bond Protocol auctioneer, which `IBondAuctioneer` does not
///         declare.
interface IBondAuctioneerOwner {
    function owner() external view returns (address);
}

/// @title YieldRepurchaseFacilityV2SetupBatch
/// @notice The batches around the launch of the YieldRepurchaseFacilityV2 stack: the facility,
///         its configuration policy, its config timelock, and the BackingOracle with its
///         config timelock. The launch itself (bindings, roles, the first `enable` of the five
///         policies, the assets, the Clearinghouses and the Heart task) is an OCG proposal;
///         these batches prepare it and clean up after it. Every action is conditional on the
///         live state, so a second run on a converged state proposes nothing.
///
///         Entry points:
///         - `setupKernel` (DAO MS as the Kernel executor, before the proposal): activate the
///           five policies in the Kernel, after checking that the deployment is bound
///           together and matches `env.json`. Nothing is enabled.
///         - `setCallbackAuthStatus` (the Safe that owns the bond auctioneer, before the
///           proposal): authorize the facility as a market callback, without which its
///           `enable` reverts.
///         - `checkReadiness` (read-only, any sender): the launch readiness report. A green
///           verdict means that everything that has to be done before the proposal is
///           submitted is done, that `env.json` agrees with the chain, and that the deployed
///           activator of the launch is bound to the stack, carries the values of `env.json`
///           and finds its preconditions met.
///         - `deactivateV1` (DAO MS as the Kernel executor, after the proposal): deactivate
///           the YieldRepurchaseFacility v1.2 in the Kernel.
///
///         The steady state afterwards is served by `YieldRepurchaseFacilityV2ConfigTimelockBatch`
///         (configuration through the timelock), `YieldRepurchaseFacilityV2Batch` (lifecycle
///         and emergency levers) and the `BackingOracle` batches.
contract YieldRepurchaseFacilityV2SetupBatch is YieldRepurchaseFacilityV2BatchScript {
    // =========== CONSTANTS =========== //

    string internal constant LENS_KEY = "olympus.periphery.YieldRepurchaseFacilityV2Lens";
    string internal constant V1_KEY = "olympus.policies.YieldRepurchaseFacility";
    string internal constant HEART_KEY = "olympus.policies.OlympusHeart";
    string internal constant ROLES_ADMIN_KEY = "olympus.policies.RolesAdmin";
    string internal constant OHM_KEY = "olympus.legacy.OHM";
    string internal constant USDS_KEY = "external.tokens.USDS";
    string internal constant SUSDS_KEY = "external.tokens.sUSDS";
    string internal constant AUCTIONEER_KEY = "external.bond-protocol.BondFixedTermAuctioneer";
    string internal constant TELLER_KEY = "external.bond-protocol.BondFixedTermTeller";
    string internal constant DAO_MS_KEY = "olympus.multisig.dao";
    string internal constant EMERGENCY_MS_KEY = "olympus.multisig.emergency";
    string internal constant OCG_TIMELOCK_KEY = "olympus.governance.Timelock";
    string internal constant ACTIVATOR_KEY = "olympus.proposals.YieldRepurchaseFacilityV2Activator";
    string internal constant PRICE_CONFIG_KEY = "olympus.policies.OlympusPriceConfigV2";
    string internal constant USDE_KEY = "external.tokens.USDe";
    string internal constant SUSDE_KEY = "external.tokens.sUSDe";

    /// @notice The role `shutdown` of the YieldRepurchaseFacility v1.2 is gated to, which the
    ///         launch proposal grants to the activator for its call.
    bytes32 internal constant LOOP_DADDY_ROLE = "loop_daddy";

    /// @notice The number of assets the activator registers: the sUSDS and sUSDe vaults.
    uint256 internal constant LAUNCH_ASSET_COUNT = 2;

    uint256 internal constant ONE_HUNDRED_PERCENT_BPS = 10_000;

    /// @notice The decimals of the PRICE module prices and of the backing value.
    uint8 internal constant PRICE_DECIMALS = 18;

    /// @notice The selector of `Error(string)`, the revert data of a failed `require`.
    bytes4 internal constant ERROR_STRING_SELECTOR = 0x08c379a0;

    // =========== STATE =========== //

    /// @notice The failure count of the running readiness check.
    uint256 internal _failures;

    /// @notice The policies `setupKernel` activates, which must stay disabled.
    address[] internal _activated;

    // =========== ENTRY POINTS =========== //

    /// @notice Activates the five policies of the stack in the Kernel (DAO MS as the Kernel
    ///         executor, before the launch proposal).
    /// @dev Each activation is added only when the policy is not active. The activation of a
    ///      policy runs its `configureDependencies`, which checks the versions of the modules
    ///      it reads. Nothing is enabled and nothing is bound: both belong to the proposal.
    ///
    ///      The heart beat validation is skipped: the batch activates only policies that are
    ///      disabled, and a heart beat reads nothing of a disabled policy of the stack.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The desired state of `env.json` is malformed (see
    ///        `YieldRepurchaseFacilityV2ConfigLib`).
    ///      - The contracts of the stack are not bound to each other, or one reports another
    ///        Kernel.
    ///      - The batch owner is not the Kernel executor.
    ///      - A grace period, the timelock delay or the step gas limit of the deployment
    ///        differs from `env.json`, or the facility is bound to another OHM, bond
    ///        auctioneer or teller than `env.json` records, or the lens to another facility.
    ///      - A policy that is not active is enabled.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function setupKernel(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        // Only disabled policies are activated, and none of them is a Heart task yet
        _skipHeartbeatValidation = true;

        Stack memory stack = _stack();
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);

        console2.log("\n=== Activate the YieldRepurchaseFacilityV2 stack in the Kernel ===");
        console2.log("Kernel:", stack.kernel);
        console2.log("BackingOracle:", stack.oracle);
        console2.log("BackingOracleConfigTimelock:", stack.oracleTimelock);
        console2.log("YieldRepurchaseFacilityV2Config:", stack.config);
        console2.log("YieldRepurchaseFacilityV2ConfigTimelock:", stack.timelock);
        console2.log("YieldRepurchaseFacilityV2:", stack.facility);

        _requireKernelExecutor(stack.kernel);
        _requireDeployedAsDeclared(stack, desired.parameters);

        _planActivation(stack.kernel, stack.oracle, ORACLE_NAME);
        _planActivation(stack.kernel, stack.oracleTimelock, ORACLE_TIMELOCK_NAME);
        _planActivation(stack.kernel, stack.config, CONFIG_NAME);
        _planActivation(stack.kernel, stack.timelock, TIMELOCK_NAME);
        _planActivation(stack.kernel, stack.facility, FACILITY_NAME);

        _setPostBatchValidateSelector(this._validateSetupKernel.selector);

        proposeBatch();
    }

    /// @notice Authorizes the facility as a market callback on the bond auctioneer (the Safe
    ///         that owns the auctioneer, before the launch proposal).
    /// @dev The batch owner is the live `owner()` of the auctioneer, not the DAO MS: the
    ///      transaction is proposed to that Safe, and the signer has to be one of its owners.
    ///      Skipped when the facility is already authorized. Without the authorization the
    ///      `enable` of the facility reverts, and the auctioneer rejects its markets.
    ///
    ///      The heart beat validation is skipped while the facility is disabled: it creates
    ///      no market then. For an enabled facility the authorization decides whether its
    ///      daily cycles open markets, and the heart beat is validated.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - `useDaoMS_` is false: the batch is a proposal to a Safe.
    ///      - The facility uses another auctioneer than `env.json` records.
    ///      - The owner of the auctioneer is not a contract.
    /// @param useDaoMS_ Must be true; the owner is the Safe that owns the auctioneer.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function setCallbackAuthStatus(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external {
        _validateArgsFileEmpty(argsFile_);
        require(
            useDaoMS_,
            _fail(
                "the batch is a proposal to the Safe that owns the bond auctioneer: run it with --multisig true"
            )
        );

        // The steps of the setUp modifier, with the owner of the auctioneer as the batch owner
        console2.log("Setting up batch script");
        _loadEnv(ChainUtils._getChainName(block.chainid));

        address auctioneer = _envAddressNotZero(AUCTIONEER_KEY);
        address facility = _envAddressNotZero(FACILITY_KEY);
        address usedAuctioneer = IYieldRepurchaseFacilityV2View(facility).bondAuctioneer();
        require(
            usedAuctioneer == auctioneer,
            _fail(
                string.concat(
                    "the facility creates its markets on the auctioneer ",
                    vm.toString(usedAuctioneer),
                    ", not on ",
                    AUCTIONEER_KEY,
                    " of env.json"
                )
            )
        );

        address auctioneerOwner = IBondAuctioneerOwner(auctioneer).owner();
        require(
            auctioneerOwner.code.length > 0,
            _fail(
                string.concat(
                    "the owner of the bond auctioneer, ",
                    vm.toString(auctioneerOwner),
                    ", is not a contract, so there is no Safe to propose the transaction to; the owner has to call setCallbackAuthStatus(facility, true) directly"
                )
            )
        );
        _setUpBatchScript(auctioneerOwner, ledgerDerivationPath_);

        console2.log("\n=== Authorize the facility as a market callback ===");
        console2.log("Bond auctioneer:", auctioneer);
        console2.log("Auctioneer owner (the batch owner):", auctioneerOwner);
        console2.log("YieldRepurchaseFacilityV2:", facility);

        // A disabled facility creates no market, so the authorization changes no heart beat
        _skipHeartbeatValidation = !IEnabler(facility).isEnabled();

        if (IBondAuctioneer(auctioneer).callbackAuthorized(facility)) {
            console2.log("The facility is already authorized as a market callback. Skipping.");
        } else {
            addToBatch(
                auctioneer,
                abi.encodeWithSelector(
                    IBondAuctioneer.setCallbackAuthStatus.selector,
                    facility,
                    true
                )
            );
            console2.log("Added: BondFixedTermAuctioneer.setCallbackAuthStatus(facility, true)");
        }

        _setPostBatchValidateSelector(this._validateCallbackAuthStatus.selector);

        proposeBatch();
    }

    /// @notice The launch readiness report (read-only, any sender): what has to hold before
    ///         the launch proposal is submitted.
    /// @dev Prints one `[ OK ]` or `[FAIL]` line per check, `[INFO]` lines for the state that
    ///      the proposal itself establishes, `[TODO]` lines for the `env.json` values that
    ///      have to be verified again before the proposal contracts are deployed, and a final
    ///      `READINESS RESULT <chain>: GREEN|RED` line. It does not revert on a red result: a
    ///      reverted script would swallow its own log, so a wrapper derives the exit code
    ///      from the verdict line. Each section runs in its own call: a section that reverts
    ///      (a malformed `env.json`, an address that is not the expected contract) is one
    ///      failed line, and the report continues. Performs no state change on the chain.
    ///
    ///      The parameters the launch registers USDe with in the PRICE module (the update
    ///      threshold of the feed, the expected price and its tolerance) are read from the
    ///      activator recorded in `env.json`, which holds them as public constants.
    function checkReadiness() external {
        _loadEnv(ChainUtils._getChainName(block.chainid));
        _failures = 0;

        console2.log("\n=== YieldRepurchaseFacilityV2 launch readiness:", chain, "===");
        _section(this._readinessEnv.selector, "The desired state of env.json");
        _section(this._readinessDeployment.selector, "Deployment");
        _section(this._readinessKernel.selector, "Kernel and roles");
        _section(this._readinessPristine.selector, "Pre-launch state of the stack");
        _section(this._readinessBond.selector, "Bond Protocol");
        _section(this._readinessHeart.selector, "Heart and YieldRepurchaseFacility v1.2");
        _section(this._readinessPrice.selector, "PRICE");
        _section(this._readinessAssets.selector, "Assets");
        _section(this._readinessClearinghouses.selector, "Clearinghouses");
        _section(this._readinessActivator.selector, "Activator");
        _section(this._readinessReverify.selector, "Values to verify again");

        console2.log(
            string.concat("\nREADINESS RESULT ", chain, ": ", _failures == 0 ? "GREEN" : "RED")
        );
    }

    /// @notice Deactivates the YieldRepurchaseFacility v1.2 in the Kernel (DAO MS as the
    ///         Kernel executor, after the launch proposal).
    /// @dev Skipped when v1.2 is already inactive. The deactivation is planned under
    ///      preconditions that are checked while the batch is built and not when the Safe
    ///      executes it: the encoded action is `Kernel.executeAction(DeactivatePolicy, v1.2)`
    ///      alone, and the Kernel checks none of them. Nothing holds them between the build
    ///      and the execution: build and simulate the batch immediately before signing, and
    ///      cancel a pending Safe transaction of it after any administration of v1.2, of the
    ///      v2 facility or of the Heart tasks, then build it again.
    ///
    ///      A USDS, sUSDS or OHM balance of v1.2 does not stop the batch: the run logs a
    ///      warning with the amount, and the deactivation leaves the balance on v1.2.
    ///
    ///      The heart beat is validated after the batch.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner is not the Kernel executor.
    ///      - v1.2 is active in the Kernel and is not shut down or is a periodic task of the
    ///        Heart.
    ///      - v1.2 is active in the Kernel and the v2 facility is not active in the Kernel,
    ///        not enabled, or not a periodic task of the Heart.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function deactivateV1(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);

        Stack memory stack = _stack();
        address v1 = _envAddressNotZero(V1_KEY);

        console2.log("\n=== Deactivate the YieldRepurchaseFacility v1.2 in the Kernel ===");
        console2.log("Kernel:", stack.kernel);
        console2.log("YieldRepurchaseFacility v1.2:", v1);
        console2.log("YieldRepurchaseFacilityV2:", stack.facility);

        if (!_isActive(stack.kernel, v1)) {
            console2.log("v1.2 is already inactive in the Kernel. Skipping.");
        } else {
            _requireKernelExecutor(stack.kernel);
            _requireV1Retired(stack, v1);
            addToBatch(
                stack.kernel,
                abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, v1)
            );
            console2.log("Added: Kernel.executeAction(DeactivatePolicy, YieldRepurchaseFacility)");
        }

        _setPostBatchValidateSelector(this._validateDeactivateV1.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `setupKernel`: the five policies are active in the
    ///         Kernel, and the ones this run activated are still disabled.
    function _validateSetupKernel() external view {
        Stack memory stack = _stack();

        console2.log("\nValidating setupKernel post-batch state");
        _requireActiveAfter(stack.kernel, stack.oracle, ORACLE_NAME);
        _requireActiveAfter(stack.kernel, stack.oracleTimelock, ORACLE_TIMELOCK_NAME);
        _requireActiveAfter(stack.kernel, stack.config, CONFIG_NAME);
        _requireActiveAfter(stack.kernel, stack.timelock, TIMELOCK_NAME);
        _requireActiveAfter(stack.kernel, stack.facility, FACILITY_NAME);
        console2.log("  The five policies are active in the Kernel");

        uint256 length = _activated.length;
        for (uint256 i = 0; i < length; ++i) {
            require(
                !IEnabler(_activated[i]).isEnabled(),
                string.concat("Policy ", vm.toString(_activated[i]), " is enabled")
            );
        }
        console2.log("  The policies this batch activated are disabled");
        console2.log("setupKernel post-batch validation passed");
    }

    /// @notice Validates the state after `setCallbackAuthStatus`.
    function _validateCallbackAuthStatus() external view {
        address auctioneer = _envAddressNotZero(AUCTIONEER_KEY);
        address facility = _envAddressNotZero(FACILITY_KEY);

        console2.log("\nValidating setCallbackAuthStatus post-batch state");
        require(
            IBondAuctioneer(auctioneer).callbackAuthorized(facility),
            "The facility is not authorized as a market callback"
        );
        console2.log("  The facility is authorized as a market callback");
        console2.log("setCallbackAuthStatus post-batch validation passed");
    }

    /// @notice Validates the state after `deactivateV1`: v1.2 is inactive, and the v2 facility
    ///         is active, enabled and a periodic task of the Heart.
    function _validateDeactivateV1() external view {
        Stack memory stack = _stack();
        address v1 = _envAddressNotZero(V1_KEY);
        address heart = _envAddressNotZero(HEART_KEY);

        console2.log("\nValidating deactivateV1 post-batch state");
        require(!_isActive(stack.kernel, v1), "v1.2 is still active in the Kernel");
        console2.log("  v1.2 is inactive in the Kernel");
        _requireActiveAfter(stack.kernel, stack.facility, FACILITY_NAME);
        require(IEnabler(stack.facility).isEnabled(), "The v2 facility is not enabled");
        require(
            IPeriodicTaskManager(heart).getPeriodicTaskIndex(stack.facility) != type(uint256).max,
            "The v2 facility is not a periodic task of the Heart"
        );
        console2.log("  The v2 facility is active, enabled and a periodic task of the Heart");
        console2.log("deactivateV1 post-batch validation passed");
    }

    // =========== READINESS SECTIONS =========== //

    /// @notice Readiness: `env.json` declares a readable desired state.
    function _readinessEnv() external {
        YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);
        _check(true, "env.json declares the desired state of the stack");
        BackingOracleConfigLib.desiredBacking(env, chain);
        _check(true, "env.json declares the backing of the oracle");
        YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(env, chain);
        _check(true, "env.json declares the USDe/USD price feed");
    }

    /// @notice Readiness: the stack is deployed, bound together and matches `env.json`.
    function _readinessDeployment() external {
        address lens = _envAddress(LENS_KEY);
        bool recorded = _envAddress(ORACLE_KEY) != address(0) &&
            _envAddress(ORACLE_TIMELOCK_KEY) != address(0) &&
            _envAddress(CONFIG_KEY) != address(0) &&
            _envAddress(TIMELOCK_KEY) != address(0) &&
            _envAddress(FACILITY_KEY) != address(0) &&
            lens != address(0);
        _check(recorded, "the five policies and the lens are recorded in env.json");
        if (!recorded) return;

        Stack memory stack = _stack();
        _check(
            true,
            "the five policies report the Kernel of env.json, the timelocks are bound to their destinations and the facility reads the oracle"
        );
        _check(
            IYieldRepurchaseFacilityV2Lens(lens).facility() == stack.facility,
            "the lens reads the facility"
        );

        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack.facility);
        _check(
            facility.bondAuctioneer() == _envAddress(AUCTIONEER_KEY) &&
                facility.bondTeller() == _envAddress(TELLER_KEY),
            "the facility uses the bond auctioneer and the teller of env.json"
        );
        _check(facility.context().ohm == _envAddress(OHM_KEY), "the facility is bound to OHM");

        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredParameters(env, chain);
        _check(
            IGracePeriod(stack.facility).gracePeriod() == desired.gracePeriod &&
                IGracePeriod(stack.config).gracePeriod() == desired.gracePeriod &&
                IGracePeriod(stack.timelock).gracePeriod() == desired.gracePeriod,
            string.concat(
                "the grace period of the facility, the configuration policy and the config timelock is ",
                vm.toString(uint256(desired.gracePeriod)),
                " seconds, as in env.json"
            )
        );
        _check(
            ITimelockBatchQueue(stack.timelock).timelockDelay() == desired.timelockDelay,
            string.concat(
                "the delay of the config timelock is ",
                vm.toString(uint256(desired.timelockDelay)),
                " seconds, as in env.json"
            )
        );
        _check(
            facility.stepGasLimit() == desired.stepGasLimit,
            string.concat(
                "the step gas limit of the facility is ",
                vm.toString(uint256(desired.stepGasLimit)),
                ", as in env.json"
            )
        );
    }

    /// @notice Readiness: the Kernel executor, the RolesAdmin admin, the activation of the
    ///         five policies and the roles the launch and the levers rely on.
    function _readinessKernel() external {
        address kernel = _envAddressNotZero(KERNEL_KEY);
        address daoMS = _envAddressNotZero(DAO_MS_KEY);
        address emergencyMS = _envAddressNotZero(EMERGENCY_MS_KEY);
        address ocgTimelock = _envAddressNotZero(OCG_TIMELOCK_KEY);
        address heart = _envAddressNotZero(HEART_KEY);

        _check(Kernel(kernel).executor() == daoMS, "the DAO MS is the Kernel executor");
        _check(
            RolesAdmin(_envAddressNotZero(ROLES_ADMIN_KEY)).admin() == ocgTimelock,
            "the OCG timelock is the RolesAdmin admin, which grants yrf_admin and backing_admin"
        );

        _checkActive(kernel, ORACLE_KEY, ORACLE_NAME);
        _checkActive(kernel, ORACLE_TIMELOCK_KEY, ORACLE_TIMELOCK_NAME);
        _checkActive(kernel, CONFIG_KEY, CONFIG_NAME);
        _checkActive(kernel, TIMELOCK_KEY, TIMELOCK_NAME);
        _checkActive(kernel, FACILITY_KEY, FACILITY_NAME);

        ROLESv1 roles = _roles(kernel);
        _check(roles.hasRole(ocgTimelock, ADMIN_ROLE), "the OCG timelock holds admin");
        _check(
            roles.hasRole(emergencyMS, EMERGENCY_ROLE),
            "the Emergency MS holds emergency, the role of the emergency levers"
        );
        _check(
            roles.hasRole(heart, HEART_ROLE),
            "the Heart holds heart, the role of the periodic task of the facility"
        );
        _info(
            string.concat(
                "the DAO MS ",
                roles.hasRole(daoMS, YRF_ADMIN_ROLE) ? "holds" : "does not hold",
                " yrf_admin and ",
                roles.hasRole(daoMS, BACKING_ADMIN_ROLE) ? "holds" : "does not hold",
                " backing_admin; the proposal grants both"
            )
        );
    }

    /// @notice Readiness: nothing of the stack is enabled, bound or configured yet, the state
    ///         the launch starts from. `setFacility`, `setConfigurator` and
    ///         `setConfigOperator` revert on a value that is already set.
    function _readinessPristine() external {
        Stack memory stack = _stack();

        _checkNeverEnabled(stack.oracle, ORACLE_NAME);
        _checkNeverEnabled(stack.oracleTimelock, ORACLE_TIMELOCK_NAME);
        _checkNeverEnabled(stack.config, CONFIG_NAME);
        _checkNeverEnabled(stack.timelock, TIMELOCK_NAME);
        _checkNeverEnabled(stack.facility, FACILITY_NAME);

        _check(
            IYieldRepurchaseFacilityV2Config(stack.config).facility() == address(0) &&
                IYieldRepurchaseFacilityV2View(stack.facility).configurator() == address(0),
            "the configuration policy and the facility are not bound to each other yet"
        );
        _check(
            IConfigOperator(stack.config).configOperator() == address(0) &&
                IConfigOperator(stack.oracle).configOperator() == address(0),
            "the configuration policy and the oracle name no config operator yet"
        );
        _check(IBackingOracle(stack.oracle).backing() == 0, "the oracle holds no backing yet");
        _check(
            IYieldRepurchaseFacilityV2View(stack.facility).getVaults().length == 0,
            "the facility has no registered vault yet"
        );
    }

    /// @notice Readiness: the facility is authorized as a market callback, a condition of its
    ///         `enable`.
    function _readinessBond() external {
        address auctioneer = _envAddressNotZero(AUCTIONEER_KEY);
        address facility = _envAddressNotZero(FACILITY_KEY);
        address auctioneerOwner = IBondAuctioneerOwner(auctioneer).owner();

        _check(
            IBondAuctioneer(auctioneer).callbackAuthorized(facility),
            "the facility is authorized as a market callback on the bond auctioneer (setCallbackAuthStatus, from the Safe that owns the auctioneer)"
        );
        _info(
            string.concat(
                "the owner of the bond auctioneer is ",
                vm.toString(auctioneerOwner),
                auctioneerOwner.code.length > 0 ? " (a contract)" : " (not a contract)"
            )
        );
    }

    /// @notice Readiness: v1.2 holds the Heart slot the launch hands to the v2 facility.
    function _readinessHeart() external {
        address kernel = _envAddressNotZero(KERNEL_KEY);
        address heart = _envAddressNotZero(HEART_KEY);
        address v1 = _envAddressNotZero(V1_KEY);
        address facility = _envAddressNotZero(FACILITY_KEY);

        uint256 v1Index = IPeriodicTaskManager(heart).getPeriodicTaskIndex(v1);
        _check(
            v1Index != type(uint256).max,
            v1Index == type(uint256).max
                ? "v1.2 is a periodic task of the Heart"
                : string.concat(
                    "v1.2 is a periodic task of the Heart, at index ",
                    vm.toString(v1Index)
                )
        );
        _check(_isActive(kernel, v1), "v1.2 is active in the Kernel");
        _check(!IYieldRepoV1(v1).isShutdown(), "v1.2 is not shut down");
        _check(
            IPeriodicTaskManager(heart).getPeriodicTaskIndex(facility) == type(uint256).max,
            "the v2 facility is not a periodic task of the Heart yet"
        );
        _check(
            IERC165(facility).supportsInterface(type(IPeriodicTask).interfaceId),
            "the v2 facility advertises IPeriodicTask, which the Heart requires of a task without a custom selector"
        );
    }

    /// @notice Readiness: the PRICE module the facility reads, and the USDe/USD feed the
    ///         launch registers.
    /// @dev The price of the feed and the age of its answer are compared with the constants of
    ///      the activator. Until the activator is recorded in `env.json`, the section fails on
    ///      its absence and prints both values as an `[INFO]` line.
    function _readinessPrice() external {
        address kernel = _envAddressNotZero(KERNEL_KEY);
        address price = address(Kernel(kernel).getModuleForKeycode(toKeycode("PRICE")));
        (uint8 major, uint8 minor) = IVersioned(price).VERSION();
        _check(
            ((major == 1 && minor >= 2) || major == 2) &&
                IPRICEv2(price).decimals() == PRICE_DECIMALS,
            string.concat(
                "the PRICE module reports version ",
                vm.toString(uint256(major)),
                ".",
                vm.toString(uint256(minor)),
                " and 18 decimals (the facility requires 1.2 or later, or 2.x)"
            )
        );

        AggregatorV2V3Interface feed = AggregatorV2V3Interface(
            YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(env, chain)
        );
        // Only the answer and the time of its update are read
        // forge-lint: disable-next-line(unused-return)
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        uint8 feedDecimals = feed.decimals();
        bool readable = answer > 0 && feedDecimals <= PRICE_DECIMALS;
        _check(readable, "the USDe/USD feed reports a positive answer with at most 18 decimals");
        uint256 usdePrice = 0;
        if (readable) {
            // casting to 'uint256' is safe because a readable answer is positive
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 feedAnswer = uint256(answer);
            // answer (feed decimals) * 10^(18 - feed decimals) -> price (18 decimals)
            usdePrice =
                feedAnswer *
                YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** (PRICE_DECIMALS - feedDecimals);
        }
        uint256 age = vm.getBlockTimestamp() > updatedAt ? vm.getBlockTimestamp() - updatedAt : 0;

        address activator = _envAddress(ACTIVATOR_KEY);
        bool deployed = activator.code.length != 0;
        _check(
            deployed,
            "the activator is recorded in env.json, so that the registration parameters of the USDe/USD feed can be read from it"
        );
        if (!deployed) {
            // The bounds of the registration are constants of the activator: without it the
            // answer of the feed is reported and compared with nothing
            _info(
                string.concat(
                    "the USDe/USD feed price is ",
                    vm.toString(usdePrice),
                    " (18 decimals) and was updated ",
                    vm.toString(age),
                    " seconds ago; the tolerance and the update threshold are compared once the activator is deployed"
                )
            );
            return;
        }
        uint256 updateThreshold = IYieldRepurchaseFacilityV2Activator(activator)
            .USDE_FEED_UPDATE_THRESHOLD();
        uint256 expectedPrice = IYieldRepurchaseFacilityV2Activator(activator)
            .USDE_EXPECTED_PRICE();
        uint256 toleranceBps = IYieldRepurchaseFacilityV2Activator(activator)
            .USDE_PRICE_TOLERANCE_BPS();

        if (readable) {
            uint256 deviation = usdePrice > expectedPrice
                ? usdePrice - expectedPrice
                : expectedPrice - usdePrice;
            // deviation (18 decimals) * 10_000 <= expected (18 decimals) * tolerance (bps)
            _check(
                deviation * ONE_HUNDRED_PERCENT_BPS <= expectedPrice * toleranceBps,
                string.concat(
                    "the USDe/USD feed price ",
                    vm.toString(usdePrice),
                    " is within ",
                    vm.toString(toleranceBps),
                    " bps of the expected ",
                    vm.toString(expectedPrice)
                )
            );
        }
        _check(
            age <= updateThreshold,
            string.concat(
                "the USDe/USD feed was updated ",
                vm.toString(age),
                " seconds ago; the threshold is ",
                vm.toString(updateThreshold),
                " seconds",
                age <= updateThreshold
                    ? string.concat(
                        ", which leaves ",
                        vm.toString(updateThreshold - age),
                        " seconds of margin (the proposal reverts on a stale feed and can be executed again inside its window)"
                    )
                    : ""
            )
        );
    }

    /// @notice Readiness: every declared asset is a vault the facility can register.
    function _readinessAssets() external {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);
        address kernel = _envAddressNotZero(KERNEL_KEY);
        address price = address(Kernel(kernel).getModuleForKeycode(toKeycode("PRICE")));
        address treasury = address(Kernel(kernel).getModuleForKeycode(toKeycode("TRSRY")));
        address ohm = _envAddressNotZero(OHM_KEY);

        for (uint256 i = 0; i < desired.assets.length; ++i) {
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset = desired.assets[i];
            address reserve = IERC4626(asset.vault).asset();
            uint8 vaultDecimals = IERC20(asset.vault).decimals();
            uint8 reserveDecimals = IERC20(reserve).decimals();
            _check(
                vaultDecimals == reserveDecimals && reserveDecimals <= PRICE_DECIMALS,
                string.concat(
                    "asset ",
                    asset.name,
                    ": the vault and its reserve ",
                    vm.toString(reserve),
                    " have the same decimals, at most 18"
                )
            );
            _check(
                asset.vault != ohm && reserve != ohm && _distinctReserve(desired, i, reserve),
                string.concat(
                    "asset ",
                    asset.name,
                    ": neither the vault nor its reserve is OHM, and no other declared asset shares the reserve"
                )
            );
            _check(
                IERC4626(asset.vault).previewRedeem(
                    YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** vaultDecimals
                ) !=
                    0 &&
                    IERC4626(asset.vault).previewDeposit(
                        YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** reserveDecimals
                    ) !=
                    0,
                string.concat(
                    "asset ",
                    asset.name,
                    ": the vault prices one share and one reserve unit above zero"
                )
            );
            _checkReservePrice(price, ohm, asset, reserve, asset.vault == desired.backingVault);
            _info(
                string.concat(
                    "asset ",
                    asset.name,
                    ": the treasury holds ",
                    vm.toString(IERC20(asset.vault).balanceOf(treasury)),
                    " shares; enabled ",
                    asset.enabled ? "true" : "false",
                    ", sellShares ",
                    asset.sellShares ? "true" : "false",
                    ", yieldBuybackShare ",
                    vm.toString(asset.yieldBuybackShare),
                    asset.vault == desired.backingVault ? " (the backing vault)" : ""
                )
            );
        }
    }

    /// @notice Readiness: `env.json` declares the Clearinghouses of the CHREG registry, and
    ///         the declared inclusions and offsets are ones the facility accepts.
    function _readinessClearinghouses() external {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);
        address kernel = _envAddressNotZero(KERNEL_KEY);
        CHREGv1 chreg = CHREGv1(address(Kernel(kernel).getModuleForKeycode(toKeycode("CHREG"))));

        uint256 registryCount = chreg.registryCount();
        bool declaresRegistry = registryCount == desired.clearinghouses.length;
        for (uint256 i = 0; i < registryCount; ++i) {
            (bool declared, ) = YieldRepurchaseFacilityV2ConfigLib.findClearinghouse(
                desired.clearinghouses,
                chreg.registry(i)
            );
            if (!declared) declaresRegistry = false;
        }
        _check(
            declaresRegistry,
            string.concat(
                "env.json declares exactly the ",
                vm.toString(registryCount),
                " Clearinghouses of the CHREG registry"
            )
        );

        for (uint256 i = 0; i < desired.clearinghouses.length; ++i) {
            _checkClearinghouse(chreg, registryCount, desired.clearinghouses[i]);
        }
    }

    /// @notice Readiness: the activator of the launch is deployed, accepts the OCG timelock,
    ///         is bound to the stack of `env.json`, carries the launch values of `env.json`,
    ///         is not activated, holds neither of the roles the proposal grants it, and finds
    ///         the preconditions of the launch met.
    function _readinessActivator() external {
        address activatorAddress = _envAddress(ACTIVATOR_KEY);
        bool deployed = ERC165Checker.supportsInterface(
            activatorAddress,
            type(IYieldRepurchaseFacilityV2Activator).interfaceId
        );
        _check(
            deployed,
            "the activator is recorded in env.json and advertises IYieldRepurchaseFacilityV2Activator"
        );
        if (!deployed) return;
        IYieldRepurchaseFacilityV2Activator activator = IYieldRepurchaseFacilityV2Activator(
            activatorAddress
        );

        _check(
            activator.timelock() == _envAddressNotZero(OCG_TIMELOCK_KEY),
            "the activator accepts the OCG timelock as the caller of activate"
        );
        _checkActivatorDeployment(activator.deployment());
        _checkActivatorParameters(activator.launchParameters());
        _check(!activator.isActivated(), "the activator is not activated");

        ROLESv1 roles = _roles(_envAddressNotZero(KERNEL_KEY));
        _check(
            !roles.hasRole(activatorAddress, ADMIN_ROLE) &&
                !roles.hasRole(activatorAddress, LOOP_DADDY_ROLE),
            "the activator holds neither admin nor loop_daddy; the proposal grants both for its call and revokes them after it"
        );

        try activator.checkPreconditions() {
            _check(
                true,
                "checkPreconditions() of the activator passes: the launch would execute now"
            );
        } catch (bytes memory revertData) {
            _check(
                false,
                string.concat(
                    "checkPreconditions() of the activator reverts with ",
                    _describeActivatorError(revertData)
                )
            );
        }
    }

    /// @notice Readiness: the `env.json` values that have to be verified again before the
    ///         proposal contracts are deployed, since a later change means a redeployment.
    function _readinessReverify() external view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredParameters(env, chain);
        string memory base = string.concat(YieldRepurchaseFacilityV2ConfigLib.CONFIG_KEY, ".");

        _todo(
            string.concat(
                BackingOracleConfigLib.BACKING_KEY,
                " = ",
                vm.toString(BackingOracleConfigLib.desiredBacking(env, chain))
            )
        );
        _todo(string.concat(base, "gracePeriod = ", vm.toString(uint256(desired.gracePeriod))));
        _todo(string.concat(base, "initialDiscount = ", vm.toString(desired.initialDiscount)));
        _todo(string.concat(base, "maxPricePremium = ", vm.toString(desired.maxPricePremium)));
        _todo(string.concat(base, "stepGasLimit = ", vm.toString(uint256(desired.stepGasLimit))));
        _todo(string.concat(base, "timelockDelay = ", vm.toString(uint256(desired.timelockDelay))));
    }

    // =========== READINESS HELPERS =========== //

    /// @notice Runs one readiness section in its own call, so that a revert inside it becomes
    ///         one failed line and the report continues.
    function _section(bytes4 selector_, string memory title_) internal {
        console2.log(string.concat("\n-- ", title_, " --"));
        // A raw call so that the revert data of a failing section is captured. The callee is a
        // section of this script, which calls nothing that could re-enter the report.
        // forge-lint: disable-next-item(low-level-calls,reentrancy-no-eth)
        (bool success, bytes memory revertData) = address(this).call(
            abi.encodeWithSelector(selector_)
        );
        if (success) return;
        _check(
            false,
            string.concat("the section could not be completed: ", _revertReason(revertData))
        );
    }

    /// @notice Returns the message of an `Error(string)` revert, or the raw revert data.
    function _revertReason(bytes memory revertData_) internal pure returns (string memory reason) {
        if (
            revertData_.length < SELECTOR_LENGTH ||
            _selectorOf(revertData_) != ERROR_STRING_SELECTOR
        ) {
            return string.concat("reverted with data ", vm.toString(revertData_));
        }
        return abi.decode(_withoutSelector(revertData_), (string));
    }

    function _check(bool ok_, string memory description_) internal {
        console2.log(string.concat(ok_ ? "  [ OK ] " : "  [FAIL] ", description_));
        if (!ok_) _failures++;
    }

    function _info(string memory description_) internal pure {
        console2.log(string.concat("  [INFO] ", description_));
    }

    function _todo(string memory description_) internal pure {
        console2.log(
            string.concat(
                "  [TODO] verify before the proposal contracts are deployed: ",
                description_
            )
        );
    }

    function _checkActive(address kernel_, string memory key_, string memory name_) internal {
        address policy = _envAddress(key_);
        _check(
            policy != address(0) && _isActive(kernel_, policy),
            string.concat(name_, " is active in the Kernel (setupKernel)")
        );
    }

    function _checkNeverEnabled(address policy_, string memory name_) internal {
        _check(
            !IEnabler(policy_).isEnabled() && IEnablerV2(policy_).lastTransitionAt() == 0,
            string.concat(name_, " has never been enabled")
        );
    }

    /// @notice Returns whether no declared asset before `index_` shares the reserve.
    function _distinctReserve(
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory desired_,
        uint256 index_,
        address reserve_
    ) internal view returns (bool distinct) {
        for (uint256 j = 0; j < index_; ++j) {
            if (IERC4626(desired_.assets[j].vault).asset() == reserve_) return false;
        }
        return true;
    }

    /// @notice Checks that the PRICE module prices OHM in the reserve of an asset, the probe
    ///         of `addAsset`. A reserve that is not registered yet is a failure for the
    ///         backing vault and a note for any other asset, whose reserve the launch
    ///         registers.
    function _checkReservePrice(
        address price_,
        address ohm_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset_,
        address reserve_,
        bool isBackingVault_
    ) internal {
        if (!IPRICEv2(price_).isAssetApproved(reserve_)) {
            string memory line = string.concat(
                "asset ",
                asset_.name,
                ": the reserve ",
                vm.toString(reserve_),
                " is not registered in the PRICE module"
            );
            if (isBackingVault_) _check(false, line);
            else _info(string.concat(line, "; the launch registers it before addAsset"));
            return;
        }
        try IPRICEv2(price_).getPriceIn(ohm_, reserve_) returns (uint256 ohmPrice) {
            _check(
                ohmPrice != 0,
                string.concat(
                    "asset ",
                    asset_.name,
                    ": the PRICE module prices OHM in the reserve at ",
                    vm.toString(ohmPrice)
                )
            );
        } catch (bytes memory revertData) {
            _check(
                false,
                string.concat(
                    "asset ",
                    asset_.name,
                    ": the PRICE module cannot price OHM in the reserve: ",
                    _revertReason(revertData)
                )
            );
        }
    }

    /// @notice Checks one declared Clearinghouse: its offset against the live receivables,
    ///         the conditions of an inclusion, and a note where a zero offset stands against
    ///         receivables that count toward the yield.
    function _checkClearinghouse(
        CHREGv1 chreg_,
        uint256 registryCount_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry_
    ) internal {
        string memory name = string.concat("Clearinghouse ", vm.toString(entry_.clearinghouse));

        bool inRegistry = false;
        for (uint256 i = 0; i < registryCount_; ++i) {
            if (chreg_.registry(i) != entry_.clearinghouse) continue;
            inRegistry = true;
            break;
        }

        bool readable = false;
        uint256 receivables = 0;
        try IGenericClearinghouse(entry_.clearinghouse).principalReceivables() returns (
            uint256 value
        ) {
            readable = true;
            receivables = value;
        } catch {
            // An unreadable Clearinghouse counts as zero receivables, as the facility reads it
        }

        string memory reserveText = "reverts";
        try IClearinghouseReserve(entry_.clearinghouse).reserve() returns (address reserve) {
            reserveText = vm.toString(reserve);
        } catch {
            // The DAI Clearinghouses expose no reserve(): they count only while included
        }

        _info(
            string.concat(
                name,
                ": included ",
                entry_.included ? "true" : "false",
                ", offset ",
                vm.toString(entry_.offset),
                ", principalReceivables ",
                readable ? vm.toString(receivables) : "unreadable",
                ", reserve() ",
                reserveText
            )
        );
        _check(
            entry_.offset <= receivables,
            string.concat(name, ": the offset does not exceed the principalReceivables")
        );
        if (!entry_.included) return;

        _check(
            inRegistry && readable,
            string.concat(
                name,
                ": is in the CHREG registry with readable principalReceivables, the conditions of includeClearinghouse"
            )
        );
        if (entry_.offset == 0 && receivables != 0) {
            _todo(
                string.concat(
                    name,
                    " is included with offset 0 against principalReceivables ",
                    vm.toString(receivables),
                    ": confirm that none of its receivables has to be offset"
                )
            );
        }
    }

    /// @notice Checks that the activator is bound to the contracts and tokens `env.json`
    ///         records, one line per contract.
    function _checkActivatorDeployment(
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment_
    ) internal {
        _checkBound("the Kernel", deployment_.kernel, _envAddress(KERNEL_KEY));
        _checkBound(ORACLE_NAME, deployment_.backingOracle, _envAddress(ORACLE_KEY));
        _checkBound(
            ORACLE_TIMELOCK_NAME,
            deployment_.backingOracleConfigTimelock,
            _envAddress(ORACLE_TIMELOCK_KEY)
        );
        _checkBound(CONFIG_NAME, deployment_.config, _envAddress(CONFIG_KEY));
        _checkBound(TIMELOCK_NAME, deployment_.configTimelock, _envAddress(TIMELOCK_KEY));
        _checkBound(FACILITY_NAME, deployment_.facility, _envAddress(FACILITY_KEY));
        _checkBound(
            "the YieldRepurchaseFacility v1.2",
            deployment_.yieldRepoV1,
            _envAddress(V1_KEY)
        );
        _checkBound("the Heart", deployment_.heart, _envAddress(HEART_KEY));
        _checkBound("PriceConfig v2", deployment_.priceConfig, _envAddress(PRICE_CONFIG_KEY));
        _checkBound("the bond auctioneer", deployment_.bondAuctioneer, _envAddress(AUCTIONEER_KEY));
        _checkBound(
            "the USDe/USD price feed",
            deployment_.usdeUsdPriceFeed,
            YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(env, chain)
        );
        _checkBound("OHM", deployment_.ohm, _envAddress(OHM_KEY));
        _checkBound("USDS", deployment_.usds, _envAddress(USDS_KEY));
        _checkBound("sUSDS", deployment_.sUsds, _envAddress(SUSDS_KEY));
        _checkBound("USDe", deployment_.usde, _envAddress(USDE_KEY));
        _checkBound("sUSDe", deployment_.sUsde, _envAddress(SUSDE_KEY));
    }

    function _checkBound(string memory name_, address bound_, address recorded_) internal {
        _check(
            recorded_ != address(0) && bound_ == recorded_,
            string.concat("the activator is bound to ", name_, " of env.json")
        );
    }

    /// @notice Checks that the launch values of the activator are the desired state of
    ///         `env.json`: the backing, the bond market parameters, the two vaults and the
    ///         Clearinghouses in the declared order.
    function _checkActivatorParameters(
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters_
    ) internal {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);

        _check(
            parameters_.backing == BackingOracleConfigLib.desiredBacking(env, chain),
            string.concat(
                "the activator enables the oracle with the backing of env.json, ",
                vm.toString(parameters_.backing)
            )
        );
        _check(
            parameters_.initialDiscount == desired.parameters.initialDiscount &&
                parameters_.maxPricePremium == desired.parameters.maxPricePremium,
            string.concat(
                "the activator enables the facility with the initialDiscount and the maxPricePremium of env.json, ",
                vm.toString(parameters_.initialDiscount),
                " and ",
                vm.toString(parameters_.maxPricePremium)
            )
        );

        (
            bool sUsdsDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsds
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(desired.assets, _envAddress(SUSDS_KEY));
        (
            bool sUsdeDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsde
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(desired.assets, _envAddress(SUSDE_KEY));
        _check(
            desired.assets.length == LAUNCH_ASSET_COUNT &&
                sUsdsDeclared &&
                sUsdeDeclared &&
                sUsds.enabled &&
                sUsde.enabled &&
                desired.backingVault == sUsds.vault,
            "env.json declares exactly the two vaults the activator registers, sUSDS and sUSDe, both enabled, with sUSDS as the backing vault"
        );
        _check(
            parameters_.sUsds.yieldBuybackShare == sUsds.yieldBuybackShare &&
                parameters_.sUsds.sellShares == sUsds.sellShares &&
                parameters_.sUsde.yieldBuybackShare == sUsde.yieldBuybackShare &&
                parameters_.sUsde.sellShares == sUsde.sellShares,
            "the activator registers both vaults with the yieldBuybackShare and the sellShares of env.json"
        );

        bool sameClearinghouses = parameters_.clearinghouses.length ==
            desired.clearinghouses.length;
        for (uint256 i = 0; sameClearinghouses && i < desired.clearinghouses.length; ++i) {
            sameClearinghouses =
                parameters_.clearinghouses[i].clearinghouse ==
                desired.clearinghouses[i].clearinghouse &&
                parameters_.clearinghouses[i].included == desired.clearinghouses[i].included &&
                parameters_.clearinghouses[i].offset == desired.clearinghouses[i].offset;
        }
        _check(
            sameClearinghouses,
            string.concat(
                "the activator lists the ",
                vm.toString(desired.clearinghouses.length),
                " Clearinghouses of env.json with their inclusions and offsets, in the declared order"
            )
        );
    }

    /// @notice Names the error of the activator a `checkPreconditions` revert carries, or
    ///         returns the raw revert data for an error of another contract.
    function _describeActivatorError(
        bytes memory revertData_
    ) internal pure returns (string memory description) {
        if (revertData_.length < SELECTOR_LENGTH) {
            return string.concat("data ", vm.toString(revertData_));
        }
        bytes4 selector = _selectorOf(revertData_);
        string memory name = _activatorErrorName(selector);
        if (bytes(name).length == 0) return string.concat("data ", vm.toString(revertData_));
        return string.concat(name, " (data ", vm.toString(revertData_), ")");
    }

    /// @notice Returns the name of a precondition error of the activator, or an empty string.
    // One branch per error of the interface; splitting the list would not make it clearer
    // forge-lint: disable-next-item(cyclomatic-complexity)
    function _activatorErrorName(bytes4 selector_) internal pure returns (string memory name) {
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_BindingMismatch
                .selector
        ) return "BindingMismatch";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_AlreadyActivated
                .selector
        ) return "AlreadyActivated";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_PolicyNotActive
                .selector
        ) return "PolicyNotActive";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_PolicyNotEnabled
                .selector
        ) return "PolicyNotEnabled";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_PolicyAlreadyEnabled
                .selector
        ) return "PolicyAlreadyEnabled";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_AlreadyBound
                .selector
        ) return "AlreadyBound";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized
                .selector
        ) return "CallbackNotAuthorized";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1ShutDown
                .selector
        ) return "V1ShutDown";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1ConversionRateUnset
                .selector
        ) return "V1ConversionRateUnset";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1NotHeartTask
                .selector
        ) return "V1NotHeartTask";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_FacilityAlreadyHeartTask
                .selector
        ) return "FacilityAlreadyHeartTask";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch
                .selector
        ) return "ClearinghouseRegistryMismatch";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_ClearinghouseReceivablesNotReadable
                .selector
        ) return "ClearinghouseReceivablesNotReadable";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_ClearinghouseOffsetTooHigh
                .selector
        ) return "ClearinghouseOffsetTooHigh";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_ReserveNotPriceable
                .selector
        ) return "ReserveNotPriceable";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable
                .selector
        ) return "UsdeFeedNotReadable";
        if (
            selector_ ==
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_UsdePriceOutOfBounds
                .selector
        ) return "UsdePriceOutOfBounds";
        return "";
    }

    // =========== PLANNING HELPERS =========== //

    /// @notice Plans the activation of a policy that is not active, and refuses to activate
    ///         one that is enabled.
    function _planActivation(address kernel_, address policy_, string memory name_) internal {
        if (!_isActive(kernel_, policy_)) {
            require(
                !IEnabler(policy_).isEnabled(),
                _fail(
                    string.concat(
                        name_,
                        " is enabled but not active in the Kernel; this batch prepares a launch and activates disabled policies only, so the state has to be examined before the policy is activated again"
                    )
                )
            );
        }
        if (_planActivatePolicy(kernel_, policy_, name_)) _activated.push(policy_);
    }

    /// @notice Reverts unless the deployment carries the parameters and the bindings that
    ///         `env.json` declares.
    function _requireDeployedAsDeclared(
        Stack memory stack_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory desired_
    ) internal view {
        _requireGracePeriod(stack_.facility, FACILITY_NAME, desired_.gracePeriod);
        _requireGracePeriod(stack_.config, CONFIG_NAME, desired_.gracePeriod);
        _requireGracePeriod(stack_.timelock, TIMELOCK_NAME, desired_.gracePeriod);

        uint48 timelockDelay = ITimelockBatchQueue(stack_.timelock).timelockDelay();
        require(
            timelockDelay == desired_.timelockDelay,
            _fail(
                string.concat(
                    "the delay of the config timelock is ",
                    vm.toString(uint256(timelockDelay)),
                    " seconds, while env.json declares ",
                    vm.toString(uint256(desired_.timelockDelay)),
                    "; align olympus.config.YieldRepurchaseFacilityV2.timelockDelay with the deployment or redeploy"
                )
            )
        );

        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(stack_.facility);
        uint32 stepGasLimit = facility.stepGasLimit();
        require(
            stepGasLimit == desired_.stepGasLimit,
            _fail(
                string.concat(
                    "the step gas limit of the facility is ",
                    vm.toString(uint256(stepGasLimit)),
                    ", while env.json declares ",
                    vm.toString(uint256(desired_.stepGasLimit)),
                    "; align olympus.config.YieldRepurchaseFacilityV2.stepGasLimit with the deployment or redeploy"
                )
            )
        );
        require(
            facility.bondAuctioneer() == _envAddressNotZero(AUCTIONEER_KEY) &&
                facility.bondTeller() == _envAddressNotZero(TELLER_KEY),
            _fail("the facility uses another bond auctioneer or teller than env.json records")
        );
        require(
            facility.context().ohm == _envAddressNotZero(OHM_KEY),
            _fail("the facility is bound to another OHM than env.json records")
        );
        require(
            IYieldRepurchaseFacilityV2Lens(_envAddressNotZero(LENS_KEY)).facility() ==
                stack_.facility,
            _fail("the lens of env.json reads another facility")
        );
    }

    function _requireGracePeriod(
        address policy_,
        string memory name_,
        uint32 desired_
    ) internal view {
        uint32 gracePeriod = IGracePeriod(policy_).gracePeriod();
        require(
            gracePeriod == desired_,
            _fail(
                string.concat(
                    "the grace period of ",
                    name_,
                    " is ",
                    vm.toString(uint256(gracePeriod)),
                    " seconds, while env.json declares ",
                    vm.toString(uint256(desired_)),
                    "; align olympus.config.YieldRepurchaseFacilityV2.gracePeriod with the deployment or redeploy"
                )
            )
        );
    }

    /// @notice Reverts unless v1.2 is retired and the v2 facility has taken over: the
    ///         preconditions of the deactivation, which the Kernel does not check.
    /// @dev A USDS, sUSDS or OHM balance of v1.2 is logged as a warning and is not a
    ///      precondition: any account can transfer a token to v1.2, and the deactivation
    ///      neither reads nor moves the balance.
    function _requireV1Retired(Stack memory stack_, address v1_) internal view {
        address heart = _envAddressNotZero(HEART_KEY);

        require(
            IYieldRepoV1(v1_).isShutdown(),
            _fail(
                "v1.2 is not shut down; the launch proposal shuts it down, so the deactivation follows the proposal"
            )
        );
        _warnBalance(_envAddressNotZero(USDS_KEY), v1_, "USDS");
        _warnBalance(_envAddressNotZero(SUSDS_KEY), v1_, "sUSDS");
        _warnBalance(_envAddressNotZero(OHM_KEY), v1_, "OHM");
        require(
            IPeriodicTaskManager(heart).getPeriodicTaskIndex(v1_) == type(uint256).max,
            _fail(
                "v1.2 is still a periodic task of the Heart; a beat would call a policy without permissions once it is deactivated"
            )
        );
        _requireActive(
            stack_.kernel,
            stack_.facility,
            FACILITY_NAME,
            "so v1.2 has no successor yet"
        );
        require(
            IEnabler(stack_.facility).isEnabled(),
            _fail("the v2 facility is not enabled, so v1.2 has no successor yet")
        );
        require(
            IPeriodicTaskManager(heart).getPeriodicTaskIndex(stack_.facility) != type(uint256).max,
            _fail(
                "the v2 facility is not a periodic task of the Heart, so v1.2 has no successor yet"
            )
        );
    }

    /// @notice Logs a warning with the amount when v1.2 holds a balance of the token.
    function _warnBalance(address token_, address holder_, string memory name_) internal view {
        uint256 balance = IERC20(token_).balanceOf(holder_);
        if (balance == 0) return;
        console2.log(
            string.concat(
                "WARNING: v1.2 holds ",
                vm.toString(balance),
                " of ",
                name_,
                ". The deactivation leaves the balance on v1.2: its shutdown(), restricted to the loop_daddy role, burns the OHM balance and transfers the listed token balances to the treasury."
            )
        );
    }

    function _requireActiveAfter(
        address kernel_,
        address policy_,
        string memory name_
    ) internal view {
        require(_isActive(kernel_, policy_), string.concat(name_, " is not active in the Kernel"));
    }

    // =========== HOOKS =========== //

    function _batchName() internal pure override returns (string memory name) {
        return "YieldRepurchaseFacilityV2SetupBatch";
    }
}

// forge-lint: disable-end(multi-contract-file)
// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
