// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Scripting
import {console2} from "@forge-std-1.16.2/console2.sol";
import {DeployV3} from "src/scripts/deploy/DeployV3.s.sol";

// Interfaces
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";
import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityV2Config} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Config.sol";
import {YieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ConfigTimelock.sol";
import {YieldRepurchaseFacilityV2Lens} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Lens.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";

// solhint-disable gas-custom-errors

/// @title DeployYieldRepurchaseFacilityV2
/// @notice Deploys YieldRepurchaseFacilityV2, its configuration policy, its config timelock, its
///         lens and the one-use activator of its launch through the sequence runner of DeployV3.
/// @dev The facility calls six linked libraries. Before a script runs, forge deploys every
///      linked library that the bytecode of the target contract references and that has no
///      code at its address yet, through the CREATE2 factory, whichever function the run
///      calls. This contract is a separate target, so DeployV3, which does not reference the
///      facility, deploys no library.
///
///      Run it under the `deploy` profile, as `shell/deployV3.sh` does when its `--script`
///      argument names this contract.
///      The grace periods, the timelock delay and the step gas limit default to the
///      `olympus.config.YieldRepurchaseFacilityV2` values of the chain in `env.json`; a sequence
///      argument of the same name overrides them. The launch values of the activator are read
///      from `env.json` only.
contract DeployYieldRepurchaseFacilityV2 is DeployV3 {
    // ========== CONSTANTS ========== //

    /// @notice The `env.json` prefix of the deployment parameters.
    string internal constant _CONFIG_KEY = "olympus.config.YieldRepurchaseFacilityV2";

    /// @notice The `env.json` prefix under which the linked library addresses are recorded.
    string internal constant _LIBRARIES_KEY = "olympus.libraries";

    /// @notice The number of assets the activator registers: the sUSDS vault and the sUSDe
    ///         vault.
    uint256 internal constant _LAUNCH_ASSET_COUNT = 2;

    // ========== DEPLOYMENT FUNCTIONS ========== //

    /// @notice Deploys the configuration policy, not yet bound to a facility.
    /// @dev The facility is bound after the Kernel activation through `setFacility`.
    function deployYieldRepurchaseFacilityV2Config() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        uint32 gracePeriod = _readGracePeriod("YieldRepurchaseFacilityV2Config");

        // Log parameters
        console2.log("YieldRepurchaseFacilityV2Config parameters:");
        console2.log("  kernel", kernel);
        console2.log("  gracePeriod", gracePeriod);

        // Deploy
        vm.broadcast();
        YieldRepurchaseFacilityV2Config config = new YieldRepurchaseFacilityV2Config(
            Kernel(kernel),
            gracePeriod
        );

        return (address(config), "olympus.policies");
    }

    /// @notice Deploys the config timelock of the configuration policy.
    /// @dev The configuration policy must be deployed first, in this sequence or in `env.json`:
    ///      the constructor requires it to advertise `IYieldRepurchaseFacilityV2Config`,
    ///      `IConfigOperator` and `IEnabler` and to report the same Kernel.
    function deployYieldRepurchaseFacilityV2ConfigTimelock()
        public
        returns (address, string memory)
    {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address config = _getAddressNotZero("olympus.policies.YieldRepurchaseFacilityV2Config");
        uint48 initialTimelockDelay = SafeCast.encodeUInt48(
            _readDeploymentArgUint256OrEnv(
                "YieldRepurchaseFacilityV2ConfigTimelock",
                "initialTimelockDelay",
                string.concat(_CONFIG_KEY, ".timelockDelay")
            )
        );
        uint32 gracePeriod = _readGracePeriod("YieldRepurchaseFacilityV2ConfigTimelock");

        // Log parameters
        console2.log("YieldRepurchaseFacilityV2ConfigTimelock parameters:");
        console2.log("  kernel", kernel);
        console2.log("  config", config);
        console2.log("  initialTimelockDelay", initialTimelockDelay);
        console2.log("  gracePeriod", gracePeriod);

        // Deploy
        vm.broadcast();
        YieldRepurchaseFacilityV2ConfigTimelock timelock = new YieldRepurchaseFacilityV2ConfigTimelock(
                Kernel(kernel),
                config,
                initialTimelockDelay,
                gracePeriod
            );

        return (address(timelock), "olympus.policies");
    }

    /// @notice Deploys the facility and records the addresses of its linked libraries under
    ///         `olympus.libraries.<library name>`.
    /// @dev The backing oracle must be deployed first, in this sequence or in `env.json`: the
    ///      constructor requires it to report the same Kernel and 18 decimals. The bond teller
    ///      is resolved from the auctioneer by the constructor.
    function deployYieldRepurchaseFacilityV2() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");
        address backingOracle = _getAddressNotZero("olympus.policies.BackingOracle");
        address bondAuctioneer = _getAddressNotZero(
            "external.bond-protocol.BondFixedTermAuctioneer"
        );
        uint32 gracePeriod = _readGracePeriod("YieldRepurchaseFacilityV2");
        uint32 stepGasLimit = SafeCast.encodeUInt32(
            _readDeploymentArgUint256OrEnv(
                "YieldRepurchaseFacilityV2",
                "stepGasLimit",
                string.concat(_CONFIG_KEY, ".stepGasLimit")
            )
        );

        // Log parameters
        console2.log("YieldRepurchaseFacilityV2 parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohm", ohm);
        console2.log("  backingOracle", backingOracle);
        console2.log("  bondAuctioneer", bondAuctioneer);
        console2.log("  gracePeriod", gracePeriod);
        console2.log("  stepGasLimit", stepGasLimit);

        // Libraries, deployed by forge before the script runs
        console2.log("YieldRepurchaseFacilityV2 linked libraries:");
        _recordLinkedLibrary("YieldRepurchaseFacilityV2AssetRegistryLib");
        _recordLinkedLibrary("YieldRepurchaseFacilityV2BondMarketLib");
        _recordLinkedLibrary("YieldRepurchaseFacilityV2BuybackPoolLib");
        _recordLinkedLibrary("YieldRepurchaseFacilityV2ClearinghouseLib");
        _recordLinkedLibrary("YieldRepurchaseFacilityV2DependenciesLib");
        _recordLinkedLibrary("YieldRepurchaseFacilityV2YieldLib");

        // Deploy
        vm.broadcast();
        YieldRepurchaseFacilityV2 facility = new YieldRepurchaseFacilityV2(
            Kernel(kernel),
            ohm,
            backingOracle,
            bondAuctioneer,
            gracePeriod,
            stepGasLimit
        );

        return (address(facility), "olympus.policies");
    }

    /// @notice Deploys the lens of the facility.
    /// @dev The facility must be deployed first, in this sequence or in `env.json`.
    function deployYieldRepurchaseFacilityV2Lens() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address facility = _getAddressNotZero("olympus.policies.YieldRepurchaseFacilityV2");

        // Log parameters
        console2.log("YieldRepurchaseFacilityV2Lens parameters:");
        console2.log("  facility", facility);

        // Deploy
        vm.broadcast();
        YieldRepurchaseFacilityV2Lens lens = new YieldRepurchaseFacilityV2Lens(facility);

        return (address(lens), "olympus.periphery");
    }

    // ========== HELPERS ========== //

    /// @notice Reads the re-enable grace period of a deployment, in seconds.
    function _readGracePeriod(string memory deploymentName_) internal view returns (uint32) {
        return
            SafeCast.encodeUInt32(
                _readDeploymentArgUint256OrEnv(
                    deploymentName_,
                    "gracePeriod",
                    string.concat(_CONFIG_KEY, ".gracePeriod")
                )
            );
    }

    /// @notice Records the address of a linked library of the facility for `env.json` and the
    ///         deployment file of the run.
    /// @dev The address is derived the way forge places the library: the default CREATE2
    ///      deployer, the zero salt (the `create2_library_salt` default; `foundry.toml` sets
    ///      neither) and the creation code of the library artifact, which is the deployed
    ///      creation code because the library links no other library. The function reverts
    ///      when the derived address holds no code, so that a library placed elsewhere is not
    ///      recorded.
    /// @param name_ The contract name of the library, which is also its file name.
    function _recordLinkedLibrary(string memory name_) internal {
        address library_ = vm.computeCreate2Address(
            bytes32(0),
            keccak256(vm.getCode(string.concat(name_, ".sol:", name_)))
        );
        require(
            library_.code.length > 0,
            string.concat("Linked library not deployed at its CREATE2 address: ", name_)
        );

        string memory key = string.concat(_LIBRARIES_KEY, ".", name_);
        console2.log("  %s: %s", key, library_);

        deployedToKeys.push(key);
        deployedTo[key] = library_;
    }
}
