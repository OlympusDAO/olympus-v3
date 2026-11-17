// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2EnvFixture} from "src/test/proposals/YieldRepurchaseFacilityV2Proposal/YieldRepurchaseFacilityV2EnvFixture.sol";

// Contracts
import {DeployYieldRepurchaseFacilityV2} from "src/scripts/deploy/DeployYieldRepurchaseFacilityV2.s.sol";
import {YieldRepurchaseFacilityV2ActivatorTest} from "src/test/proposals/YieldRepurchaseFacilityV2Activator/YieldRepurchaseFacilityV2ActivatorTest.sol";

/// @notice `deployYieldRepurchaseFacilityV2Activator` of the deployment script, run against the
///         local stack of the activator rig. The test contract is the script: it inherits the
///         deployment functions, records the contracts of the rig as the dependencies of the
///         run, and supplies an `env.json` rendered from the launch values of the rig.
contract DeployYieldRepurchaseFacilityV2Tests_deployYieldRepurchaseFacilityV2Activator is
    YieldRepurchaseFacilityV2ActivatorTest,
    DeployYieldRepurchaseFacilityV2
{
    string internal constant CHAIN = "local";
    string internal constant SUSDS_NAME = "sUSDS";
    string internal constant SUSDE_NAME = "sUSDe";

    function setUp() public override {
        super.setUp();

        chain = CHAIN;
        env = YieldRepurchaseFacilityV2EnvFixture.toJson(_state(), CHAIN);

        deployedTo["olympus.governance.Timelock"] = ocgTimelock;
        deployedTo["olympus.Kernel"] = address(kernel);
        deployedTo["olympus.policies.BackingOracle"] = address(backingOracle);
        deployedTo["olympus.policies.BackingOracleConfigTimelock"] = address(
            backingOracleConfigTimelock
        );
        deployedTo["olympus.policies.YieldRepurchaseFacilityV2Config"] = address(config);
        deployedTo["olympus.policies.YieldRepurchaseFacilityV2ConfigTimelock"] = address(
            configTimelock
        );
        deployedTo["olympus.policies.YieldRepurchaseFacilityV2"] = address(facility);
        deployedTo["olympus.policies.YieldRepurchaseFacility"] = address(yieldRepoV1);
        deployedTo["olympus.policies.OlympusHeart"] = address(heart);
        deployedTo["olympus.policies.OlympusPriceConfigV2"] = address(priceConfig);
        deployedTo["external.bond-protocol.BondFixedTermAuctioneer"] = address(bondAuctioneer);
        deployedTo["olympus.legacy.OHM"] = address(ohm);
        deployedTo["external.tokens.USDS"] = address(usds);
        deployedTo["external.tokens.sUSDS"] = address(sUsds);
        deployedTo["external.tokens.USDe"] = address(usde);
        deployedTo["external.tokens.sUSDe"] = address(sUsde);
    }

    // ========== HELPERS ========== //

    /// @notice The desired state that declares the launch values of the rig.
    function _state() internal view returns (YieldRepurchaseFacilityV2EnvFixture.State memory s) {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();

        s.backing = parameters.backing;
        s.usdeUsdPriceFeed = address(usdeUsdFeed);
        s.config.parameters.gracePeriod = GRACE_PERIOD;
        s.config.parameters.stepGasLimit = STEP_GAS_LIMIT;
        s.config.parameters.timelockDelay = TIMELOCK_DELAY;
        s.config.parameters.initialDiscount = parameters.initialDiscount;
        s.config.parameters.maxPricePremium = parameters.maxPricePremium;
        s.config.backingVault = address(sUsds);

        s.config.assets = new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](2);
        s.config.assets[0] = YieldRepurchaseFacilityV2ConfigLib.DesiredAsset({
            name: SUSDS_NAME,
            vault: address(sUsds),
            enabled: true,
            sellShares: parameters.sUsds.sellShares,
            yieldBuybackShare: parameters.sUsds.yieldBuybackShare
        });
        s.config.assets[1] = YieldRepurchaseFacilityV2ConfigLib.DesiredAsset({
            name: SUSDE_NAME,
            vault: address(sUsde),
            enabled: true,
            sellShares: parameters.sUsde.sellShares,
            yieldBuybackShare: parameters.sUsde.yieldBuybackShare
        });

        s.config.clearinghouses = new YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[](
            parameters.clearinghouses.length
        );
        for (uint256 i = 0; i < parameters.clearinghouses.length; ++i) {
            s.config.clearinghouses[i] = YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse({
                clearinghouse: parameters.clearinghouses[i].clearinghouse,
                included: parameters.clearinghouses[i].included,
                offset: parameters.clearinghouses[i].offset
            });
        }
    }

    function _setEnv(YieldRepurchaseFacilityV2EnvFixture.State memory state_) internal {
        env = YieldRepurchaseFacilityV2EnvFixture.toJson(state_, CHAIN);
    }

    // ========== ERROR CONDITIONS ========== //

    // given env.json declares a third asset
    //   [X] it reverts: the activator registers exactly the two vaults

    function test_givenEnvDeclaresThirdAsset_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _state();
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[]
            memory assets = new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](3);
        // The library sorts the assets by name: "sDAI" precedes "sUSDS" and "sUSDe"
        assets[0] = YieldRepurchaseFacilityV2ConfigLib.DesiredAsset({
            name: "sDAI",
            vault: makeAddr("sDAI"),
            enabled: true,
            sellShares: true,
            yieldBuybackShare: 1e18
        });
        assets[1] = state.config.assets[0];
        assets[2] = state.config.assets[1];
        state.config.assets = assets;
        _setEnv(state);

        vm.expectRevert(
            bytes(
                "The activator registers the sUSDS and sUSDe vaults: olympus.config.YieldRepurchaseFacilityV2.assets must declare exactly these two"
            )
        );
        this.deployYieldRepurchaseFacilityV2Activator();
    }

    // given env.json does not declare the sUSDe vault
    //   [X] it reverts: the activator registers exactly the two vaults

    function test_givenEnvDoesNotDeclareSUsde_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _state();
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[]
            memory assets = new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](1);
        assets[0] = state.config.assets[0];
        state.config.assets = assets;
        _setEnv(state);

        vm.expectRevert(
            bytes(
                "The activator registers the sUSDS and sUSDe vaults: olympus.config.YieldRepurchaseFacilityV2.assets must declare exactly these two"
            )
        );
        this.deployYieldRepurchaseFacilityV2Activator();
    }

    // given env.json declares two assets, one of which is not a vault of the launch
    //   [X] it reverts: the activator registers exactly the two vaults

    function test_givenEnvDeclaresAnotherVault_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _state();
        state.config.assets[1].vault = makeAddr("otherVault");
        _setEnv(state);

        vm.expectRevert(
            bytes(
                "The activator registers the sUSDS and sUSDe vaults: olympus.config.YieldRepurchaseFacilityV2.assets must declare exactly these two"
            )
        );
        this.deployYieldRepurchaseFacilityV2Activator();
    }

    // given env.json declares the sUSDe vault with enabled: false
    //   [X] it reverts: the activator registers both vaults enabled

    function test_givenEnvDeclaresSUsdeDisabled_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _state();
        state.config.assets[1].enabled = false;
        _setEnv(state);

        vm.expectRevert(
            bytes(
                "The activator registers both vaults enabled: olympus.config.YieldRepurchaseFacilityV2.assets must not declare enabled: false"
            )
        );
        this.deployYieldRepurchaseFacilityV2Activator();
    }

    // given env.json declares the sUSDS vault, the backing vault, with enabled: false
    //   [X] it reverts with the refusal of the library that reads env.json

    function test_givenEnvDeclaresSUsdsDisabled_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _state();
        state.config.assets[0].enabled = false;
        _setEnv(state);

        vm.expectRevert(
            bytes(
                "YieldRepurchaseFacilityV2ConfigLib: the backing vault sUSDS (.current.local.olympus.config.YieldRepurchaseFacilityV2.backingVault) is declared with enabled: false under .current.local.olympus.config.YieldRepurchaseFacilityV2.assets; the facility cannot disable the backing vault"
            )
        );
        this.deployYieldRepurchaseFacilityV2Activator();
    }

    // given env.json names the sUSDe vault as the backing vault
    //   [X] it reverts: the activator designates the sUSDS vault

    function test_givenEnvNamesSUsdeAsBackingVault_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _state();
        // The library rejects a backing vault that sells shares, so the declaration is one it
        // accepts: sUSDe paying out the reserve
        state.config.assets[1].sellShares = false;
        state.config.backingVault = address(sUsde);
        _setEnv(state);

        vm.expectRevert(
            bytes(
                "The activator designates the sUSDS vault as the backing vault: olympus.config.YieldRepurchaseFacilityV2.backingVault must name sUSDS"
            )
        );
        this.deployYieldRepurchaseFacilityV2Activator();
    }

    // ========== SUCCESS CONDITIONS ========== //

    // given env.json declares the launch values of the rig
    //   [X] it deploys an activator bound to the recorded contracts and to those values
    //   [X] it reports the env.json prefix of proposal helpers

    function test_givenEnvDeclaresTheLaunch() public {
        (address deployed, string memory prefix) = this.deployYieldRepurchaseFacilityV2Activator();
        vm.label(deployed, "deployedActivator");
        IYieldRepurchaseFacilityV2Activator deployedActivator = IYieldRepurchaseFacilityV2Activator(
            deployed
        );

        assertEq(
            prefix,
            "olympus.proposals",
            "the activator should be recorded as a proposal helper"
        );
        assertEq(deployedActivator.timelock(), ocgTimelock, "timelock");
        assertEq(
            keccak256(abi.encode(deployedActivator.deployment())),
            keccak256(abi.encode(_deployment())),
            "the activator should be bound to the recorded contracts"
        );
        assertEq(
            keccak256(abi.encode(deployedActivator.launchParameters())),
            keccak256(abi.encode(_launchParameters())),
            "the activator should carry the launch values of env.json"
        );
        deployedActivator.checkPreconditions();
    }
}
