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

    /// @notice Deploys the one-use activator of the launch, bound to the stack and to the
    ///         launch values of `env.json`.
    /// @dev The five policies of the stack must be deployed first, in this sequence or in
    ///      `env.json`: the constructor of the activator reads their bindings. The launch values
    ///      are the desired state of the chain: `olympus.config.BackingOracle.backing` and, under
    ///      `olympus.config.YieldRepurchaseFacilityV2`, `initialDiscount`, `maxPricePremium`,
    ///      `assets` and `clearinghouses`, read through `BackingOracleConfigLib` and
    ///      `YieldRepurchaseFacilityV2ConfigLib` with their bounds. A value that changes after
    ///      this deployment requires another activator: the launch proposal rejects an
    ///      activator whose values differ from `env.json`.
    ///
    ///      Reverts if `env.json` does not declare exactly the sUSDS vault and the sUSDe vault,
    ///      declares one of them with `enabled: false`, or names another backing vault than the
    ///      sUSDS vault: the activator registers these two vaults, both enabled, with the sUSDS
    ///      vault as the backing vault.
    function deployYieldRepurchaseFacilityV2Activator() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address timelock = _getAddressNotZero("olympus.governance.Timelock");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment;
        deployment.kernel = _getAddressNotZero("olympus.Kernel");
        deployment.backingOracle = _getAddressNotZero("olympus.policies.BackingOracle");
        deployment.backingOracleConfigTimelock = _getAddressNotZero(
            "olympus.policies.BackingOracleConfigTimelock"
        );
        deployment.config = _getAddressNotZero("olympus.policies.YieldRepurchaseFacilityV2Config");
        deployment.configTimelock = _getAddressNotZero(
            "olympus.policies.YieldRepurchaseFacilityV2ConfigTimelock"
        );
        deployment.facility = _getAddressNotZero("olympus.policies.YieldRepurchaseFacilityV2");
        deployment.yieldRepoV1 = _getAddressNotZero("olympus.policies.YieldRepurchaseFacility");
        deployment.heart = _getAddressNotZero("olympus.policies.OlympusHeart");
        deployment.priceConfig = _getAddressNotZero("olympus.policies.OlympusPriceConfigV2");
        deployment.bondAuctioneer = _getAddressNotZero(
            "external.bond-protocol.BondFixedTermAuctioneer"
        );
        deployment.usdeUsdPriceFeed = YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(
            env,
            chain
        );
        deployment.ohm = _getAddressNotZero("olympus.legacy.OHM");
        deployment.usds = _getAddressNotZero("external.tokens.USDS");
        deployment.sUsds = _getAddressNotZero("external.tokens.sUSDS");
        deployment.usde = _getAddressNotZero("external.tokens.USDe");
        deployment.sUsde = _getAddressNotZero("external.tokens.sUSDe");

        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _readLaunchParameters(deployment.sUsds, deployment.sUsde);

        // Log parameters
        console2.log("YieldRepurchaseFacilityV2Activator parameters:");
        console2.log("  timelock", timelock);
        console2.log("  usdeUsdPriceFeed", deployment.usdeUsdPriceFeed);
        console2.log("  backing", parameters.backing);
        console2.log("  initialDiscount", parameters.initialDiscount);
        console2.log("  maxPricePremium", parameters.maxPricePremium);
        console2.log("  sUSDS yieldBuybackShare", parameters.sUsds.yieldBuybackShare);
        console2.log("  sUSDS sellShares", parameters.sUsds.sellShares);
        console2.log("  sUSDe yieldBuybackShare", parameters.sUsde.yieldBuybackShare);
        console2.log("  sUSDe sellShares", parameters.sUsde.sellShares);
        for (uint256 i = 0; i < parameters.clearinghouses.length; ++i) {
            console2.log("  clearinghouse", parameters.clearinghouses[i].clearinghouse);
            console2.log("    included", parameters.clearinghouses[i].included);
            console2.log("    offset", parameters.clearinghouses[i].offset);
        }

        // Deploy
        vm.broadcast();
        YieldRepurchaseFacilityV2Activator activator = new YieldRepurchaseFacilityV2Activator(
            timelock,
            deployment,
            parameters
        );

        return (address(activator), "olympus.proposals");
    }

    // ========== HELPERS ========== //

    /// @notice Reads the launch values of the activator from the desired state of `env.json`.
    /// @dev Reverts if the desired state is malformed (see
    ///      `YieldRepurchaseFacilityV2ConfigLib` and `BackingOracleConfigLib`), or if it does
    ///      not declare exactly the two vaults, both enabled, with `sUsds_` as the backing
    ///      vault.
    /// @param sUsds_ The sUSDS vault.
    /// @param sUsde_ The sUSDe vault.
    function _readLaunchParameters(
        address sUsds_,
        address sUsde_
    )
        internal
        view
        returns (IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters)
    {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env, chain);

        (
            bool sUsdsDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsds
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(desired.assets, sUsds_);
        (
            bool sUsdeDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsde
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(desired.assets, sUsde_);
        require(
            desired.assets.length == _LAUNCH_ASSET_COUNT && sUsdsDeclared && sUsdeDeclared,
            "The activator registers the sUSDS and sUSDe vaults: olympus.config.YieldRepurchaseFacilityV2.assets must declare exactly these two"
        );
        require(
            sUsds.enabled && sUsde.enabled,
            "The activator registers both vaults enabled: olympus.config.YieldRepurchaseFacilityV2.assets must not declare enabled: false"
        );
        require(
            desired.backingVault == sUsds_,
            "The activator designates the sUSDS vault as the backing vault: olympus.config.YieldRepurchaseFacilityV2.backingVault must name sUSDS"
        );

        parameters.backing = BackingOracleConfigLib.desiredBacking(env, chain);
        parameters.initialDiscount = desired.parameters.initialDiscount;
        parameters.maxPricePremium = desired.parameters.maxPricePremium;
        parameters.sUsds = IYieldRepurchaseFacilityV2Activator.AssetParameters({
            yieldBuybackShare: sUsds.yieldBuybackShare,
            sellShares: sUsds.sellShares
        });
        parameters.sUsde = IYieldRepurchaseFacilityV2Activator.AssetParameters({
            yieldBuybackShare: sUsde.yieldBuybackShare,
            sellShares: sUsde.sellShares
        });
        parameters
            .clearinghouses = new IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters[](
            desired.clearinghouses.length
        );
        for (uint256 i = 0; i < desired.clearinghouses.length; ++i) {
            parameters.clearinghouses[i] = IYieldRepurchaseFacilityV2Activator
                .ClearinghouseParameters({
                    clearinghouse: desired.clearinghouses[i].clearinghouse,
                    included: desired.clearinghouses[i].included,
                    offset: desired.clearinghouses[i].offset
                });
        }
    }

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
