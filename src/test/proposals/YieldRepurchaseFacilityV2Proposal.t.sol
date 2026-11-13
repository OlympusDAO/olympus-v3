// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity ^0.8.24;

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2EnvFixture} from "./YieldRepurchaseFacilityV2Proposal/YieldRepurchaseFacilityV2EnvFixture.sol";

// Constants
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, EMERGENCY_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Timelock} from "src/external/governance/Timelock.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";
import {YieldRepurchaseFacilityV2Proposal} from "src/proposals/YieldRepurchaseFacilityV2Proposal.sol";
import {YieldRepurchaseFacilityV2ProposalFixtureHarness, YieldRepurchaseFacilityV2ProposalHarness, YieldRepurchaseFacilityV2ProposalSnapshotHarness} from "./YieldRepurchaseFacilityV2Proposal/YieldRepurchaseFacilityV2ProposalHarness.sol";
import {YieldRepurchaseFacilityV2ProposalRig} from "./YieldRepurchaseFacilityV2Proposal/YieldRepurchaseFacilityV2ProposalRig.sol";

// The suites walk the registry names, the Clearinghouses and the built actions of the fork
// forge-lint: disable-start(calls-loop)

// The two suites of one proposal belong to one file
// forge-lint: disable-start(multi-contract-file)

/// @notice The constant of the YieldRepurchaseFacility v1.2 that the description of the
///         proposal quotes, which the migration interface of v1.2 does not declare.
interface IYieldRepoV1Backing {
    function backingPerToken() external view returns (uint256);
}

/// @notice The build stage: the proposal's `_deploy` and `_build` called directly on the
///         harness, with no simulation, so that every fail-closed precondition of `_build` can
///         be proved on the state that leaves exactly that precondition unmet; then the built
///         action list, the conditional actions, the replay of the actions from the timelock
///         on a state that moved after the build, and the gas of the execution.
/// @dev    Forge restores the post-`setUp` state before every test, so the harness starts each
///         test with an empty action list.
contract YieldRepurchaseFacilityV2ProposalTests_build is YieldRepurchaseFacilityV2ProposalRig {
    /// @notice The number of registry names the build resolves.
    uint256 internal constant REGISTRY_NAME_COUNT = 19;

    /// @notice The number of contracts of the activator the build compares.
    uint256 internal constant COMPARED_MEMBER_COUNT = 15;

    /// @notice The transaction gas limit of mainnet (EIP-7825).
    uint256 internal constant TRANSACTION_GAS_LIMIT = 2 ** 24;

    function setUp() public virtual override {
        super.setUp();

        // The action dump of `getProposalActions` belongs to the simulation, not to the direct
        // build calls of this suite
        proposal.setDebug(false);
        // The deploy hook resolves the Kernel, and the hook after it reads the state the
        // validation compares the end state with; every test of this suite builds after both
        proposal.deploy(addresses, address(this));
        proposal.afterDeploy(addresses, address(this));
    }

    // ========== HELPERS ========== //

    /// @notice Builds the proposal. A single external call, so that a revert expectation set
    ///         right before it binds to the build.
    function _build() internal {
        proposal.build(addresses);
    }

    /// @notice Replaces the proposal of the rig with one that reads the supplied desired state.
    function _useDesiredState(YieldRepurchaseFacilityV2EnvFixture.State memory state_) internal {
        proposal = new YieldRepurchaseFacilityV2ProposalFixtureHarness(
            YieldRepurchaseFacilityV2EnvFixture.toJson(state_, _CHAIN)
        );
        vm.label(address(proposal), "YieldRepurchaseFacilityV2ProposalFixtureHarness");
        proposal.deploy(addresses, address(this));
        proposal.afterDeploy(addresses, address(this));
    }

    /// @notice The registry name at `index_` of the names the build resolves, in its order.
    function _registryName(uint256 index_) internal pure returns (string memory name) {
        string[REGISTRY_NAME_COUNT] memory names = [
            _ACTIVATOR_NAME,
            _ORACLE_NAME,
            _ORACLE_TIMELOCK_NAME,
            _CONFIG_NAME,
            _CONFIG_TIMELOCK_NAME,
            _FACILITY_NAME,
            "olympus-policy-yieldrepurchasefacility-1_2",
            "olympus-policy-heart-1_7",
            "olympus-policy-price-config-2_0",
            "olympus-module-roles",
            "olympus-policy-roles-admin",
            "olympus-legacy-ohm",
            "external-tokens-usds",
            "external-tokens-susds",
            "external-tokens-usde",
            "external-tokens-susde",
            "olympus-multisig-dao",
            "olympus-multisig-emergency",
            "olympus-timelock"
        ];
        return names[index_];
    }

    /// @notice Returns a copy of the deployment with the compared member at `index_` replaced,
    ///         the name the build reports the member under, and the value the build expects.
    function _deploymentWith(
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment_,
        uint256 index_,
        address value_
    )
        internal
        pure
        returns (
            IYieldRepurchaseFacilityV2Activator.Deployment memory d,
            string memory field,
            address expected
        )
    {
        // A copy, so that the deployment of the caller keeps its members
        d = abi.decode(abi.encode(deployment_), (IYieldRepurchaseFacilityV2Activator.Deployment));
        if (index_ == 0) (field, expected, d.kernel) = ("activator kernel", d.kernel, value_);
        else if (index_ == 1)
            (field, expected, d.backingOracle) = (
                "activator backingOracle",
                d.backingOracle,
                value_
            );
        else if (index_ == 2)
            (field, expected, d.backingOracleConfigTimelock) = (
                "activator backingOracleConfigTimelock",
                d.backingOracleConfigTimelock,
                value_
            );
        else if (index_ == 3) (field, expected, d.config) = ("activator config", d.config, value_);
        else if (index_ == 4)
            (field, expected, d.configTimelock) = (
                "activator configTimelock",
                d.configTimelock,
                value_
            );
        else if (index_ == 5)
            (field, expected, d.facility) = ("activator facility", d.facility, value_);
        else if (index_ == 6)
            (field, expected, d.yieldRepoV1) = ("activator yieldRepoV1", d.yieldRepoV1, value_);
        else if (index_ == 7) (field, expected, d.heart) = ("activator heart", d.heart, value_);
        else if (index_ == 8)
            (field, expected, d.priceConfig) = ("activator priceConfig", d.priceConfig, value_);
        else if (index_ == 9)
            (field, expected, d.usdeUsdPriceFeed) = (
                "activator usdeUsdPriceFeed",
                d.usdeUsdPriceFeed,
                value_
            );
        else if (index_ == 10) (field, expected, d.ohm) = ("activator ohm", d.ohm, value_);
        else if (index_ == 11) (field, expected, d.usds) = ("activator usds", d.usds, value_);
        else if (index_ == 12) (field, expected, d.sUsds) = ("activator sUsds", d.sUsds, value_);
        else if (index_ == 13) (field, expected, d.usde) = ("activator usde", d.usde, value_);
        else (field, expected, d.sUsde) = ("activator sUsde", d.sUsde, value_);
    }

    function _expectRevertAddressMismatch(
        string memory field_,
        address actual_,
        address expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AddressMismatch
                    .selector,
                field_,
                actual_,
                expected_
            )
        );
    }

    function _expectRevertParameterMismatch(
        string memory name_,
        uint256 actual_,
        uint256 expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_ParameterMismatch
                    .selector,
                name_,
                actual_,
                expected_
            )
        );
    }

    function _expectRevertFlagMismatch(string memory name_, bool actual_, bool expected_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_FlagMismatch
                    .selector,
                name_,
                actual_,
                expected_
            )
        );
    }

    /// @notice The message the library that reads `env.json` rejects a backing vault with.
    function _backingVaultRefusal(
        string memory name_,
        string memory declaration_,
        string memory reason_
    ) internal pure returns (bytes memory message) {
        return
            bytes(
                string.concat(
                    "YieldRepurchaseFacilityV2ConfigLib: the backing vault ",
                    name_,
                    " (.current.mainnet.olympus.config.YieldRepurchaseFacilityV2.backingVault) is declared with ",
                    declaration_,
                    " under .current.mainnet.olympus.config.YieldRepurchaseFacilityV2.assets; ",
                    reason_
                )
            );
    }

    /// @notice The number of built actions that carry exactly the payload.
    function _builtCount(bytes memory payload_) internal view returns (uint256 count) {
        // Only the payloads are inspected
        // forge-lint: disable-next-line(unused-return)
        (, , bytes[] memory payloads) = proposal.getProposalActions();
        for (uint256 i = 0; i < payloads.length; ++i) {
            if (keccak256(payloads[i]) == keccak256(payload_)) ++count;
        }
    }

    // ========== ERROR CONDITIONS: THE REGISTRY ========== //

    // given the registry does not record the Kernel
    //   when the proposal is deployed
    //     [X] it reverts with AddressNotRecorded naming the Kernel

    function test_givenKernelNotRecorded_reverts() public {
        vm.mockCallRevert(
            address(addresses),
            abi.encodeWithSignature("getAddress(string)", "olympus-kernel"),
            ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AddressNotRecorded
                    .selector,
                "olympus-kernel"
            )
        );
        proposal.deploy(addresses, address(this));
    }

    // given the registry does not record one of the addresses the build resolves
    //   when the proposal is built
    //     [X] it reverts with AddressNotRecorded naming the entry

    function test_givenRegistryEntryNotRecorded_reverts() public {
        // Every name the build resolves, one at a time
        for (uint256 i = 0; i < REGISTRY_NAME_COUNT; ++i) {
            string memory name = _registryName(i);
            bytes memory lookup = abi.encodeWithSignature("getAddress(string)", name);
            address recorded = addresses.getAddress(name);
            vm.mockCallRevert(address(addresses), lookup, "");

            vm.expectRevert(
                abi.encodeWithSelector(
                    YieldRepurchaseFacilityV2Proposal
                        .YieldRepurchaseFacilityV2Proposal_AddressNotRecorded
                        .selector,
                    name
                )
            );
            proposal.build(addresses);

            // The entry is recorded again for the names that follow
            vm.mockCall(address(addresses), lookup, abi.encode(recorded));
        }
    }

    // ========== ERROR CONDITIONS: THE ACTIVATOR AGAINST THE REGISTRY ========== //

    // given the registry records a contract that is not an activator
    //   when the proposal is built
    //     [X] it reverts with InvalidActivator naming the contract

    function test_givenRecordedActivatorIsAnotherContract_reverts() public {
        addresses.changeAddress(_ACTIVATOR_NAME, address(facility));

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_InvalidActivator
                    .selector,
                address(facility)
            )
        );
        _build();
    }

    // given the registry records an address without code as the activator
    //   when the proposal is built
    //     [X] it reverts with InvalidActivator naming the address

    function test_givenRecordedActivatorHasNoCode_reverts() public {
        address account = makeAddr("accountWithoutCode");
        addresses.changeAddress(_ACTIVATOR_NAME, account);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_InvalidActivator
                    .selector,
                account
            )
        );
        _build();
    }

    // given the recorded activator accepts another caller than the OCG timelock
    //   when the proposal is built
    //     [X] it reverts with AddressMismatch naming the timelock of the activator

    function test_givenActivatorBoundToAnotherTimelock_reverts() public {
        address otherTimelock = makeAddr("otherTimelock");
        YieldRepurchaseFacilityV2Activator other = new YieldRepurchaseFacilityV2Activator(
            otherTimelock,
            _deploymentOf(),
            _launchParametersOf(_desired())
        );
        vm.label(address(other), "otherActivator");
        addresses.changeAddress(_ACTIVATOR_NAME, address(other));

        _expectRevertAddressMismatch("activator timelock", otherTimelock, ocgTimelock);
        _build();
    }

    // given the recorded activator reports another contract than the registry records
    //   when the proposal is built
    //     [X] it reverts with AddressMismatch naming the contract, the reported and the recorded address

    function test_givenActivatorReportsAnotherContract_reverts() public {
        address other = makeAddr("otherContract");
        IYieldRepurchaseFacilityV2Activator.Deployment memory carried = activator.deployment();
        // Every compared contract of the activator, one at a time; each mock replaces the
        // one before it
        for (uint256 i = 0; i < COMPARED_MEMBER_COUNT; ++i) {
            (
                IYieldRepurchaseFacilityV2Activator.Deployment memory reported,
                string memory field,
                address expected
            ) = _deploymentWith(carried, i, other);
            vm.mockCall(
                address(activator),
                abi.encodeWithSelector(IYieldRepurchaseFacilityV2Activator.deployment.selector),
                abi.encode(reported)
            );

            _expectRevertAddressMismatch(field, other, expected);
            _build();
        }
    }

    // ========== ERROR CONDITIONS: THE ACTIVATOR AGAINST env.json ========== //

    // given env.json declares another backing than the activator carries
    //   when the proposal is built
    //     [X] it reverts with ParameterMismatch naming the backing, the value of the activator and of env.json

    function test_givenEnvDeclaresAnotherBacking_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 carried = state.backing;
        state.backing = carried + 1;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator backing", carried, carried + 1);
        proposal.build(addresses);
    }

    // given env.json declares another initial discount than the activator carries
    //   when the proposal is built
    //     [X] it reverts with ParameterMismatch naming the initial discount

    function test_givenEnvDeclaresAnotherInitialDiscount_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 carried = state.config.parameters.initialDiscount;
        state.config.parameters.initialDiscount = carried + 1;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator initialDiscount", carried, carried + 1);
        proposal.build(addresses);
    }

    // given env.json declares another maximum price premium than the activator carries
    //   when the proposal is built
    //     [X] it reverts with ParameterMismatch naming the maximum price premium

    function test_givenEnvDeclaresAnotherMaxPricePremium_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 carried = state.config.parameters.maxPricePremium;
        state.config.parameters.maxPricePremium = carried + 1;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator maxPricePremium", carried, carried + 1);
        proposal.build(addresses);
    }

    // given env.json declares another yield buyback share of a vault than the activator carries
    //   when the proposal is built
    //     [X] it reverts with ParameterMismatch naming the share of the vault

    function test_givenEnvDeclaresAnotherSUsdsYieldBuybackShare_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        // The library sorts the assets by name: sUSDS first, sUSDe second
        uint256 carried = state.config.assets[0].yieldBuybackShare;
        state.config.assets[0].yieldBuybackShare = carried - 1;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator sUsds yieldBuybackShare", carried, carried - 1);
        proposal.build(addresses);
    }

    function test_givenEnvDeclaresAnotherSUsdeYieldBuybackShare_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 carried = state.config.assets[1].yieldBuybackShare;
        state.config.assets[1].yieldBuybackShare = carried - 1;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator sUsde yieldBuybackShare", carried, carried - 1);
        proposal.build(addresses);
    }

    // given env.json declares another payout mode of the sUSDe vault than the activator carries
    //   when the proposal is built
    //     [X] it reverts with FlagMismatch naming the payout mode of the vault

    function test_givenEnvDeclaresAnotherSellShares_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        bool carried = state.config.assets[1].sellShares;
        state.config.assets[1].sellShares = !carried;
        _useDesiredState(state);

        _expectRevertFlagMismatch("activator sUsde sellShares", carried, !carried);
        proposal.build(addresses);
    }

    // given the activator carries another payout mode of the sUSDS vault than env.json declares
    //   when the proposal is built
    //     [X] it reverts with FlagMismatch naming the payout mode of the vault

    function test_givenActivatorCarriesAnotherSUsdsSellShares_reverts() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory carried = activator
            .launchParameters();
        bool declared = carried.sUsds.sellShares;
        carried.sUsds.sellShares = !declared;
        vm.mockCall(
            address(activator),
            abi.encodeWithSelector(IYieldRepurchaseFacilityV2Activator.launchParameters.selector),
            abi.encode(carried)
        );

        _expectRevertFlagMismatch("activator sUsds sellShares", !declared, declared);
        _build();
    }

    // given env.json declares the sUSDS vault, the backing vault, with sellShares: true
    //   when the proposal is built
    //     [X] it reverts with the refusal of the library that reads env.json

    function test_givenEnvDeclaresSUsdsSellingShares_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        state.config.assets[0].sellShares = true;
        _useDesiredState(state);

        vm.expectRevert(
            _backingVaultRefusal(
                state.config.assets[0].name,
                "sellShares: true",
                "the backing vault cannot sell shares"
            )
        );
        proposal.build(addresses);
    }

    // given env.json declares the sUSDS vault, the backing vault, with enabled: false
    //   when the proposal is built
    //     [X] it reverts with the refusal of the library that reads env.json

    function test_givenEnvDeclaresSUsdsDisabled_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        state.config.assets[0].enabled = false;
        _useDesiredState(state);

        vm.expectRevert(
            _backingVaultRefusal(
                state.config.assets[0].name,
                "enabled: false",
                "the facility cannot disable the backing vault"
            )
        );
        proposal.build(addresses);
    }

    // given env.json declares a third asset
    //   when the proposal is built
    //     [X] it reverts with AssetSetMismatch naming the number of declared assets

    function test_givenEnvDeclaresThirdAsset_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
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
        _useDesiredState(state);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AssetSetMismatch
                    .selector,
                3,
                true,
                true
            )
        );
        proposal.build(addresses);
    }

    // given env.json does not declare the sUSDe vault
    //   when the proposal is built
    //     [X] it reverts with AssetSetMismatch naming the missing vault

    function test_givenEnvDoesNotDeclareSUsde_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[]
            memory assets = new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](1);
        assets[0] = state.config.assets[0];
        state.config.assets = assets;
        _useDesiredState(state);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AssetSetMismatch
                    .selector,
                1,
                true,
                false
            )
        );
        proposal.build(addresses);
    }

    // given env.json does not declare the sUSDS vault
    //   when the proposal is built
    //     [X] it reverts with AssetSetMismatch naming the missing vault

    function test_givenEnvDoesNotDeclareSUsds_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[]
            memory assets = new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](1);
        assets[0] = state.config.assets[1];
        // The library requires a declared backing vault that pays out the reserve, so the
        // declaration is one it accepts: sUSDe alone, as the backing vault
        assets[0].sellShares = false;
        state.config.assets = assets;
        state.config.backingVault = address(sUsde);
        _useDesiredState(state);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AssetSetMismatch
                    .selector,
                1,
                false,
                true
            )
        );
        proposal.build(addresses);
    }

    // given env.json declares the sUSDe vault with enabled: false
    //   when the proposal is built
    //     [X] it reverts with AssetDeclaredDisabled naming the asset

    function test_givenEnvDeclaresSUsdeDisabled_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        state.config.assets[1].enabled = false;
        _useDesiredState(state);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AssetDeclaredDisabled
                    .selector,
                state.config.assets[1].name
            )
        );
        proposal.build(addresses);
    }

    // given env.json names the sUSDe vault as the backing vault
    //   when the proposal is built
    //     [X] it reverts with AddressMismatch naming the backing vault of env.json

    function test_givenEnvNamesAnotherBackingVault_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        // The library rejects a backing vault that sells shares, so the declaration is one it
        // accepts: sUSDe paying out the reserve
        state.config.assets[1].sellShares = false;
        state.config.backingVault = address(sUsde);
        _useDesiredState(state);

        _expectRevertAddressMismatch("env.json backingVault", address(sUsde), address(sUsds));
        proposal.build(addresses);
    }

    // given env.json declares one Clearinghouse fewer than the activator lists
    //   when the proposal is built
    //     [X] it reverts with ParameterMismatch naming both lengths

    function test_givenEnvDeclaresFewerClearinghouses_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 listed = state.config.clearinghouses.length;
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[]
            memory fewer = new YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[](
                listed - 1
            );
        for (uint256 i = 0; i < fewer.length; ++i) fewer[i] = state.config.clearinghouses[i];
        state.config.clearinghouses = fewer;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator clearinghouses length", listed, listed - 1);
        proposal.build(addresses);
    }

    // given env.json declares one Clearinghouse more than the activator lists
    //   when the proposal is built
    //     [X] it reverts with ParameterMismatch naming both lengths

    function test_givenEnvDeclaresMoreClearinghouses_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 listed = state.config.clearinghouses.length;
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[]
            memory more = new YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[](listed + 1);
        for (uint256 i = 0; i < listed; ++i) more[i] = state.config.clearinghouses[i];
        more[listed] = YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse({
            clearinghouse: makeAddr("fourthClearinghouse"),
            included: false,
            offset: 0
        });
        state.config.clearinghouses = more;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator clearinghouses length", listed, listed + 1);
        proposal.build(addresses);
    }

    // given env.json declares another Clearinghouse address, inclusion or offset than the activator lists
    //   when the proposal is built
    //     [X] it reverts with the mismatch naming the entry and the member

    function test_givenEnvDeclaresAnotherClearinghouseAddress_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        address carried = state.config.clearinghouses[1].clearinghouse;
        address other = makeAddr("otherClearinghouse");
        state.config.clearinghouses[1].clearinghouse = other;
        _useDesiredState(state);

        _expectRevertAddressMismatch("activator clearinghouses[1] address", carried, other);
        proposal.build(addresses);
    }

    function test_givenEnvDeclaresAnotherClearinghouseInclusion_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        bool carried = state.config.clearinghouses[2].included;
        state.config.clearinghouses[2].included = !carried;
        _useDesiredState(state);

        _expectRevertFlagMismatch("activator clearinghouses[2] included", carried, !carried);
        proposal.build(addresses);
    }

    function test_givenEnvDeclaresAnotherClearinghouseOffset_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        uint256 carried = state.config.clearinghouses[0].offset;
        state.config.clearinghouses[0].offset = carried + 1;
        _useDesiredState(state);

        _expectRevertParameterMismatch("activator clearinghouses[0] offset", carried, carried + 1);
        proposal.build(addresses);
    }

    // given env.json declares another USDe/USD feed than the activator registers
    //   when the proposal is built
    //     [X] it reverts with AddressMismatch naming the feed of the activator

    function test_givenEnvDeclaresAnotherUsdeFeed_reverts() public {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();
        address other = makeAddr("otherFeed");
        state.usdeUsdPriceFeed = other;
        _useDesiredState(state);

        _expectRevertAddressMismatch("activator usdeUsdPriceFeed", address(usdeUsdFeed), other);
        proposal.build(addresses);
    }

    // given the activator accepts a smaller next yield than the proposal passes
    //   when the proposal is built
    //     [X] it reverts with NextYieldTooHigh naming the value and the maximum

    function test_givenActivatorMaximumBelowNextYield_reverts() public {
        uint256 nextYield = proposal.SUSDE_NEXT_YIELD();
        vm.mockCall(
            address(activator),
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator.MAX_SUSDE_NEXT_YIELD.selector
            ),
            abi.encode(nextYield - 1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_NextYieldTooHigh
                    .selector,
                nextYield,
                nextYield - 1
            )
        );
        _build();
    }

    // ========== ERROR CONDITIONS: ROLES AND STATE ========== //

    // given the activator already holds one of its two roles
    //   when the proposal is built
    //     [X] it reverts with UnexpectedRole naming the role and the activator

    function test_givenActivatorHoldsAdmin_reverts() public {
        _grantRole(ADMIN_ROLE, address(activator));

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_UnexpectedRole
                    .selector,
                ADMIN_ROLE,
                address(activator)
            )
        );
        _build();
    }

    function test_givenActivatorHoldsLoopDaddy_reverts() public {
        _grantRole(_LOOP_DADDY_ROLE, address(activator));

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_UnexpectedRole
                    .selector,
                _LOOP_DADDY_ROLE,
                address(activator)
            )
        );
        _build();
    }

    // given the OCG timelock does not hold admin
    //   when the proposal is built
    //     [X] it reverts with MissingRole naming admin and the timelock

    function test_givenTimelockWithoutAdmin_reverts() public {
        _revokeRole(ADMIN_ROLE, ocgTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_MissingRole
                    .selector,
                ADMIN_ROLE,
                ocgTimelock
            )
        );
        _build();
    }

    // given the OCG timelock does not administer RolesAdmin
    //   when the proposal is built
    //     [X] it reverts with AddressMismatch naming the admin of RolesAdmin

    function test_givenTimelockDoesNotAdministerRolesAdmin_reverts() public {
        address otherAdmin = makeAddr("otherRolesAdmin");
        RolesAdmin rigRolesAdmin = rolesAdmin;
        vm.prank(ocgTimelock);
        rigRolesAdmin.pushNewAdmin(otherAdmin);
        vm.prank(otherAdmin);
        rigRolesAdmin.pullNewAdmin();

        _expectRevertAddressMismatch("RolesAdmin admin", otherAdmin, ocgTimelock);
        _build();
    }

    // given RolesAdmin reports another Kernel than the recorded one
    //   when the proposal is built
    //     [X] it reverts with AddressMismatch naming the Kernel of RolesAdmin

    function test_givenRolesAdminOfAnotherKernel_reverts() public {
        address otherKernel = makeAddr("otherKernel");
        vm.mockCall(
            address(rolesAdmin),
            abi.encodeWithSignature("kernel()"),
            abi.encode(otherKernel)
        );

        _expectRevertAddressMismatch("RolesAdmin kernel", otherKernel, address(kernel));
        _build();
    }

    // given a precondition of the activator does not hold
    //   when the proposal is built
    //     [X] it reverts with the named error of the activator

    function test_givenActivatorPreconditionNotMet_reverts() public {
        _setCallbackAuthStatus(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized
                    .selector,
                address(bondAuctioneer)
            )
        );
        _build();
    }

    // ========== SUCCESS CONDITIONS ========== //

    // given the proposal contract
    //   [X] it reports the OCG proposal id and the proposal name

    function test_proposalId() public view {
        assertEq(proposal.id(), _PROPOSAL_ID, "The proposal id should be 20");
        assertEq(proposal.name(), _PROPOSAL_NAME, "The proposal name should be the rollout name");
    }

    // given the proposal contract
    //   [X] its description opens with the proposal name as an H1
    //   [X] the launch parameters of the description, as raw values and as the readable values
    //       next to them, are the values of the activator and of the proposal

    function test_proposalDescription() public view {
        string memory description = proposal.description();
        assertTrue(
            _startsWith(description, string.concat("# ", _PROPOSAL_NAME, "\n")),
            "The description should open with the proposal name as an H1"
        );

        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters = activator
            .launchParameters();
        // 12.04e18 (18 decimals) -> "12.04 USDS per OHM (12040000000000000000)"
        _assertDescribed(
            description,
            string.concat(
                "Backing value of the BackingOracle: ",
                _formatAmount(parameters.backing, 18),
                " USDS per OHM (",
                vm.toString(parameters.backing),
                ")"
            ),
            "the backing"
        );
        // 3e16 of 1e18 -> "3% below the OHM price of the PRICE module (30000000000000000)"
        _assertDescribed(
            description,
            string.concat(
                "a bond market opens with a bid ",
                _formatPercent(parameters.initialDiscount),
                " below the OHM price of the PRICE module (",
                vm.toString(parameters.initialDiscount),
                ")"
            ),
            "the initial discount"
        );
        // 1e17 of 1e18 -> "10% above the OHM price of the PRICE module for one OHM
        // (100000000000000000)"
        _assertDescribed(
            description,
            string.concat(
                "a bond market pays at most ",
                _formatPercent(parameters.maxPricePremium),
                " above the OHM price of the PRICE module for one OHM (",
                vm.toString(parameters.maxPricePremium),
                ")"
            ),
            "the maximum price premium"
        );
        // 20985832534428681085040 (18 decimals) -> "20,985.83 USDe (20985832534428681085040)",
        // floored to two fraction digits
        _assertDescribed(
            description,
            string.concat(
                "Its first weekly withdrawal is ",
                _formatAmount(proposal.SUSDE_NEXT_YIELD(), 18),
                " USDe (",
                vm.toString(proposal.SUSDE_NEXT_YIELD()),
                ")"
            ),
            "the sUSDe next yield"
        );
        // 100000e18 (18 decimals) -> "100,000 USDe (100000000000000000000000)"
        _assertDescribed(
            description,
            string.concat(
                "The activator rejects a value above ",
                _formatAmount(activator.MAX_SUSDE_NEXT_YIELD(), 18),
                " USDe (",
                vm.toString(activator.MAX_SUSDE_NEXT_YIELD()),
                ")"
            ),
            "the next yield cap"
        );
        _assertDescribed(description, activator.USDE_EXPECTED_PRICE(), "the expected USDe price");
        // The backing constant of v1.2: 1133e7 (9 decimals) -> "11.33 USDS"
        _assertDescribed(
            description,
            string.concat(
                "at a constant of ",
                _formatAmount(IYieldRepoV1Backing(address(yieldRepoV1)).backingPerToken(), 9),
                " USDS"
            ),
            "the backing constant of v1.2"
        );
        // 86400 seconds -> "24 hours"; 100 basis points -> "1%"
        _assertDescribed(
            description,
            string.concat(
                "has been updated within the last ",
                vm.toString(uint256(activator.USDE_FEED_UPDATE_THRESHOLD()) / 1 hours),
                " hours and reports a price within ",
                vm.toString(uint256(activator.USDE_PRICE_TOLERANCE_BPS()) / 100),
                "% of 1 USD"
            ),
            "the registration bounds of the USDe feed as an assumption"
        );
        assertEq(
            activator.USDE_FEED_UPDATE_THRESHOLD() % 1 hours,
            0,
            "The update threshold should be whole hours"
        );
        assertEq(
            activator.USDE_PRICE_TOLERANCE_BPS() % 100,
            0,
            "The tolerance should be whole percents"
        );
        _assertDescribed(
            description,
            string.concat(
                "older than ",
                vm.toString(uint256(activator.USDE_FEED_UPDATE_THRESHOLD())),
                " seconds"
            ),
            "the update threshold of the USDe feed"
        );
        _assertDescribed(
            description,
            string.concat(
                "within ",
                vm.toString(uint256(activator.USDE_PRICE_TOLERANCE_BPS())),
                " basis points"
            ),
            "the tolerance of the USDe price"
        );
        // 1e18 of 1e18 -> "100% of its yield is routed to buybacks (1000000000000000000)"
        _assertDescribed(
            description,
            string.concat(
                "sUSDS (",
                vm.toString(address(sUsds)),
                "): the backing vault. The V2 facility burns the purchased OHM against withdrawals from this vault, and the yield of this vault (the backing yield) includes the interest of the Clearinghouses below. ",
                _formatPercent(parameters.sUsds.yieldBuybackShare),
                " of its yield is routed to buybacks (",
                vm.toString(parameters.sUsds.yieldBuybackShare),
                "); its markets pay out USDS"
            ),
            "the sUSDS vault"
        );
        assertFalse(parameters.sUsds.sellShares, "The description says sUSDS pays out USDS");
        _assertDescribed(
            description,
            string.concat(
                "sUSDe (",
                vm.toString(address(sUsde)),
                "): ",
                _formatPercent(parameters.sUsde.yieldBuybackShare),
                " of its yield is routed to buybacks (",
                vm.toString(parameters.sUsde.yieldBuybackShare),
                "); its markets pay out sUSDe shares"
            ),
            "the sUSDe vault"
        );
        assertTrue(parameters.sUsde.sellShares, "The description says sUSDe pays out shares");
        _assertDescribed(
            description,
            string.concat("Chainlink USDe/USD (", vm.toString(address(usdeUsdFeed)), ")"),
            "the USDe feed"
        );
        for (uint256 i = 0; i < parameters.clearinghouses.length; ++i) {
            _assertDescribed(
                description,
                string.concat(
                    "(",
                    vm.toString(parameters.clearinghouses[i].clearinghouse),
                    parameters.clearinghouses[i].included
                        ? "), which lends DAI: included in the backing yield, receivables offset "
                        : "), which lends USDS: not included explicitly, since a Clearinghouse that lends USDS counts toward the backing yield by default; receivables offset ",
                    vm.toString(parameters.clearinghouses[i].offset),
                    "."
                ),
                "a Clearinghouse"
            );
        }
    }

    // given the deployed stack
    //   [X] the delays, the execution windows and the grace periods of the authority model in
    //       the description are the ones the contracts report

    function test_proposalDescription_terms() public view {
        string memory description = proposal.description();

        // 86400 s -> "1 day", 259200 s -> "3 days", 432000 s -> "5 days"
        uint256 gracePeriod = facility.gracePeriod();
        assertEq(
            config.gracePeriod(),
            gracePeriod,
            "One grace period for the configuration policy"
        );
        assertEq(configTimelock.gracePeriod(), gracePeriod, "One grace period for the timelock");
        _assertDescribed(
            description,
            string.concat(
                "which anyone can execute after a delay of ",
                _formatDays(configTimelock.timelockDelay()),
                " and within ",
                _formatDays(configTimelock.EXECUTION_WINDOW()),
                " after that. It can re-enable the V2 facility, the configuration policy and the timelock within ",
                _formatDays(gracePeriod),
                " after a disable"
            ),
            "the terms of yrf_admin"
        );

        // 86400 s -> "1 day", 604800 s -> "7 days"
        uint256 oracleGracePeriod = backingOracle.gracePeriod();
        assertEq(
            backingOracleConfigTimelock.gracePeriod(),
            oracleGracePeriod,
            "One grace period for the oracle and its timelock"
        );
        _assertDescribed(
            description,
            string.concat(
                "which anyone can execute after a delay of ",
                _formatDays(backingOracleConfigTimelock.timelockDelay()),
                " and within ",
                _formatDays(backingOracleConfigTimelock.EXECUTION_WINDOW()),
                " after that; the oracle limits each update to "
            ),
            "the terms of backing_admin"
        );
        _assertDescribed(
            description,
            string.concat(
                "It can re-enable the oracle and its timelock within ",
                _formatDays(oracleGracePeriod),
                " after a disable"
            ),
            "the grace period of the oracle"
        );
    }

    /// @notice Formats a fixed-point amount with thousands separators, floored to two fraction
    ///         digits, which are left out when both are zero: 20985832534428681085040 with 18
    ///         decimals is "20,985.83", and 100000e18 is "100,000".
    function _formatAmount(
        uint256 value_,
        uint8 decimals_
    ) internal pure returns (string memory text) {
        uint256 unit = 10 ** decimals_;
        // The digits of the whole part, grouped in threes from the right
        bytes memory digits = bytes(vm.toString(value_ / unit));
        bytes memory grouped;
        for (uint256 i = 0; i < digits.length; ++i) {
            if (i != 0 && (digits.length - i) % 3 == 0) grouped = abi.encodePacked(grouped, ",");
            grouped = abi.encodePacked(grouped, digits[i]);
        }
        text = string(grouped);

        // fraction (decimals) * 100 / unit -> hundredths, floored
        uint256 hundredths = ((value_ % unit) * 100) / unit;
        if (hundredths == 0) return text;
        return string.concat(text, hundredths < 10 ? ".0" : ".", vm.toString(hundredths));
    }

    /// @notice Formats a share of 1e18 as a whole percentage: 3e16 is "3%".
    function _formatPercent(uint256 share_) internal pure returns (string memory text) {
        // share (18 decimals) * 100 / 1e18 -> percent
        assertEq((share_ * 100) % _ONE, 0, "The share should be a whole percentage");
        return string.concat(vm.toString((share_ * 100) / _ONE), "%");
    }

    /// @notice Formats a duration of whole days: 86400 is "1 day", 259200 is "3 days".
    function _formatDays(uint256 seconds_) internal pure returns (string memory text) {
        assertEq(seconds_ % 1 days, 0, "The duration should be whole days");
        uint256 count = seconds_ / 1 days;
        return string.concat(vm.toString(count), count == 1 ? " day" : " days");
    }

    function _assertDescribed(
        string memory description_,
        uint256 value_,
        string memory label_
    ) internal pure {
        _assertDescribed(description_, string.concat("(", vm.toString(value_), ")"), label_);
    }

    function _assertDescribed(
        string memory description_,
        string memory fragment_,
        string memory label_
    ) internal pure {
        assertTrue(
            vm.contains(description_, fragment_),
            string.concat("The description should state ", label_, ": ", fragment_)
        );
    }

    // given the state before the proposal
    //   when the proposal is built
    //     [X] it builds the action list the live state calls for, and no more
    //     [X] the activate action carries the next yield of the proposal

    function test_givenPreparedState_whenBuilt() public {
        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        _build();

        _assertBuiltActions(expected);

        // The five actions around the activator are always built
        address activatorAddress = address(activator);
        assertEq(
            _builtCount(
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, ADMIN_ROLE, activatorAddress)
            ),
            1,
            "The grant of admin to the activator should be built once"
        );
        assertEq(
            _builtCount(
                abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    _LOOP_DADDY_ROLE,
                    activatorAddress
                )
            ),
            1,
            "The revocation of loop_daddy from the activator should be built once"
        );
        uint256 activateIndex = _actionIndexOf(
            IYieldRepurchaseFacilityV2Activator.activate.selector
        );
        assertEq(
            activateIndex,
            _actionIndexOf(RolesAdmin.revokeRole.selector) - 1,
            "The first revocation should follow the activation"
        );
        // 20,985.83 USDe (18 decimals), the value derived in the proposal
        assertEq(
            proposal.SUSDE_NEXT_YIELD(),
            20_985_832_534_428_681_085_040,
            "The next yield of the sUSDe vault"
        );
    }

    // given the DAO MS and the OCG timelock hold neither operational role, and both hold loop_daddy
    //   when the proposal is built
    //     [X] it builds all nine actions

    function test_givenNoConditionMet_whenBuilt() public {
        _revokeRole(YRF_ADMIN_ROLE, daoMS);
        _revokeRole(BACKING_ADMIN_ROLE, daoMS);
        _grantRole(_LOOP_DADDY_ROLE, daoMS);
        _grantRole(_LOOP_DADDY_ROLE, ocgTimelock);

        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        assertEq(expected.length, _MAX_ACTION_COUNT, "Every action should be expected");
        _build();

        _assertBuiltActions(expected);
    }

    // given the DAO MS already holds yrf_admin
    //   when the proposal is built
    //     [X] the grant of yrf_admin is not built

    function test_givenDaoMSHoldsYrfAdmin_whenBuilt() public {
        _grantRole(YRF_ADMIN_ROLE, daoMS);

        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        _build();

        _assertBuiltActions(expected);
        assertEq(
            _builtCount(
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, YRF_ADMIN_ROLE, daoMS)
            ),
            0,
            "The grant of yrf_admin should not be built"
        );
    }

    // given the DAO MS already holds backing_admin
    //   when the proposal is built
    //     [X] the grant of backing_admin is not built

    function test_givenDaoMSHoldsBackingAdmin_whenBuilt() public {
        _grantRole(BACKING_ADMIN_ROLE, daoMS);

        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        _build();

        _assertBuiltActions(expected);
        assertEq(
            _builtCount(
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, BACKING_ADMIN_ROLE, daoMS)
            ),
            0,
            "The grant of backing_admin should not be built"
        );
    }

    // given the DAO MS does not hold loop_daddy
    //   when the proposal is built
    //     [X] the revocation of loop_daddy from the DAO MS is not built

    function test_givenDaoMSWithoutLoopDaddy_whenBuilt() public {
        _revokeRole(_LOOP_DADDY_ROLE, daoMS);

        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        _build();

        _assertBuiltActions(expected);
        assertEq(
            _builtCount(
                abi.encodeWithSelector(RolesAdmin.revokeRole.selector, _LOOP_DADDY_ROLE, daoMS)
            ),
            0,
            "The revocation from the DAO MS should not be built"
        );
    }

    // given the OCG timelock does not hold loop_daddy
    //   when the proposal is built
    //     [X] the revocation of loop_daddy from the OCG timelock is not built

    function test_givenTimelockWithoutLoopDaddy_whenBuilt() public {
        _revokeRole(_LOOP_DADDY_ROLE, ocgTimelock);

        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        _build();

        _assertBuiltActions(expected);
        assertEq(
            _builtCount(
                abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    _LOOP_DADDY_ROLE,
                    ocgTimelock
                )
            ),
            0,
            "The revocation from the OCG timelock should not be built"
        );
    }

    // ========== THE SNAPSHOT OF env.json ========== //

    // given the proposal is not submitted yet
    //   [X] the snapshot of env.json declares the desired state of the tracked file

    function test_snapshotDeclaresTheTrackedDesiredState() public {
        // After the submission the tracked file moves on and the snapshot stays
        if (IS_SUBMITTED) return;

        YieldRepurchaseFacilityV2ProposalSnapshotHarness snapshot = new YieldRepurchaseFacilityV2ProposalSnapshotHarness();
        vm.label(address(snapshot), "YieldRepurchaseFacilityV2ProposalSnapshotHarness");

        assertEq(
            keccak256(
                abi.encode(YieldRepurchaseFacilityV2EnvFixture.read(snapshot.readEnv(), _CHAIN))
            ),
            keccak256(abi.encode(_desired())),
            "The snapshot should declare the desired state of the tracked env.json: refresh src/scripts/proposals/snapshots/YieldRepurchaseFacilityV2Proposal.env.json"
        );
    }

    // given the proposal reads the snapshot of env.json
    //   when the proposal is built
    //     [X] it builds the same action list

    function test_givenSnapshotOfEnv_whenBuilt() public {
        ExpectedAction[] memory expected = _expectedActions(proposal.SUSDE_NEXT_YIELD());
        proposal = new YieldRepurchaseFacilityV2ProposalSnapshotHarness();
        vm.label(address(proposal), "YieldRepurchaseFacilityV2ProposalSnapshotHarness");
        proposal.deploy(addresses, address(this));
        proposal.afterDeploy(addresses, address(this));
        _build();

        _assertBuiltActions(expected);
    }

    // given the proposal reads the tracked env.json
    //   [X] the harness returns the file unchanged

    function test_harnessReadsTheTrackedEnv() public {
        YieldRepurchaseFacilityV2ProposalHarness tracked = new YieldRepurchaseFacilityV2ProposalHarness();
        vm.label(address(tracked), "trackedEnvHarness");

        // The path is the tracked file; the rig itself reads the env.json of its proposal
        assertEq(
            keccak256(bytes(tracked.readEnv())),
            keccak256(bytes(vm.readFile(_ENV_PATH))),
            "The proposal harness should read the tracked env.json unchanged"
        );
    }

    // given the rig
    //   [X] its expected values come from the env.json its proposal reads

    function test_rigReadsTheEnvOfItsProposal() public view {
        assertEq(
            keccak256(bytes(_env)),
            keccak256(bytes(proposal.readEnv())),
            "The rig should expect the values of the env.json its proposal reads"
        );
    }

    // ========== REPLAY FROM THE TIMELOCK ========== //

    // given the proposal is built
    //   given nothing changes
    //     when the actions are replayed from the timelock
    //       [X] every action succeeds and the launch completes
    //       [X] the proposal validates the end state

    function test_givenBuilt_whenReplayedFromTheTimelock() public {
        LaunchInputs memory inputs = _launchInputs();
        _build();

        _replayAll();

        _assertMigrated(inputs, proposal.SUSDE_NEXT_YIELD());
        assertFalse(roles.hasRole(address(activator), ADMIN_ROLE), "activator admin");
        assertFalse(roles.hasRole(address(activator), _LOOP_DADDY_ROLE), "activator loop_daddy");
        proposal.validate(addresses, proposer);
    }

    // given USDe is registered in the PRICE module before the proposal, with another update
    // threshold than the one of the activator
    //   when the actions are replayed from the timelock
    //     [X] the launch leaves that registration in place
    //     [X] the proposal validates the end state: the registration is not the one of the
    //         activator and is not compared

    function test_givenUsdeRegisteredBefore_whenReplayedFromTheTimelock() public {
        uint48 earlierThreshold = activator.USDE_FEED_UPDATE_THRESHOLD() + 1 hours;
        _registerUsdeAsDaoMS(earlierThreshold);
        // The hook reads whether USDe is registered before the actions run
        proposal.afterDeploy(addresses, address(this));
        _build();

        _replayAll();

        IPRICEv2.Component[] memory feeds = abi.decode(
            price.getAssetData(address(usde)).feeds,
            (IPRICEv2.Component[])
        );
        ChainlinkPriceFeeds.OneFeedParams memory params = abi.decode(
            feeds[0].params,
            (ChainlinkPriceFeeds.OneFeedParams)
        );
        assertEq(
            params.updateThreshold,
            earlierThreshold,
            "The launch should leave the earlier registration in place"
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal is built
    //   given the Heart beats before the execution
    //     when the actions are replayed from the timelock
    //       [X] the launch completes with the state v1.2 has then

    function test_givenBuilt_givenHeartBeats_whenReplayedFromTheTimelock() public {
        _build();
        _beat();
        LaunchInputs memory inputs = _launchInputs();

        _replayAll();

        _assertMigrated(inputs, proposal.SUSDE_NEXT_YIELD());
    }

    // given the proposal is built
    //   given the owner of the bond auctioneer then revokes the callback authorization
    //     when the actions are replayed from the timelock
    //       [X] the replay fails at the activation with CallbackNotAuthorized
    //     when the proposal runs through the governor
    //       [X] it reverts with the generic execution error of the timelock

    function test_givenBuilt_givenCallbackRevoked_replayFailsAtTheActivation() public {
        _build();
        _setCallbackAuthStatus(false);

        _replay(
            _actionIndexOf(IYieldRepurchaseFacilityV2Activator.activate.selector),
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized
                    .selector,
                address(bondAuctioneer)
            )
        );
    }

    function test_givenBuilt_givenCallbackRevoked_whenSimulated_reverts() public {
        _build();
        _setCallbackAuthStatus(false);

        vm.expectRevert(Timelock.Timelock_InvalidTx_ExecReverted.selector);
        proposal.simulate(addresses);
    }

    // given the proposal is built
    //   given a holder of loop_daddy then shuts v1.2 down
    //     when the actions are replayed from the timelock
    //       [X] the replay fails at the activation with V1ShutDown

    function test_givenBuilt_givenV1ShutDown_replayFailsAtTheActivation() public {
        _build();
        _shutdownV1(daoMS);

        _replay(
            _actionIndexOf(IYieldRepurchaseFacilityV2Activator.activate.selector),
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_V1ShutDown
                    .selector
            )
        );
    }

    // given the proposal is built
    //   given the answer of the USDe/USD feed is older than one day at the execution
    //     when the actions are replayed from the timelock
    //       [X] the replay fails at the activation with UsdeFeedNotReadable

    function test_givenBuilt_givenUsdeFeedStale_replayFailsAtTheActivation() public {
        _build();
        uint256 threshold = activator.USDE_FEED_UPDATE_THRESHOLD();
        uint256 staleAt = vm.getBlockTimestamp() - threshold - 1;
        _setUsdeFeed(usdeFeedAnswer, staleAt);

        _replay(
            _actionIndexOf(IYieldRepurchaseFacilityV2Activator.activate.selector),
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable
                    .selector,
                address(usdeUsdFeed),
                abi.encodeWithSelector(
                    ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
                    address(usdeUsdFeed),
                    staleAt,
                    vm.getBlockTimestamp() - threshold
                )
            )
        );
    }

    // ========== GAS ========== //

    // given the proposal is queued on the governor
    //   when it is executed in one transaction
    //     [X] the execution fits the transaction gas limit of mainnet with a margin of a half

    function test_givenQueued_whenExecutedThroughTheGovernor_gas() public {
        _build();
        uint256 proposalId = _queueOnGovernor();

        governor.execute(proposalId);
        uint256 gasUsed = vm.lastFrameGas().gasTotalUsed;

        emit log_named_uint("gas of GovernorBravoDelegate.execute()", gasUsed);
        assertTrue(activator.isActivated(), "The execution should activate the stack");
        // 2^24 = 16,777,216 gas per transaction (EIP-7825); the runbook recommends a gas limit
        // with a margin above this measurement
        assertLt(
            gasUsed,
            TRANSACTION_GAS_LIMIT / 2,
            "The execution should use less than a half of the transaction gas limit"
        );
    }
}

/// @notice The execution stage: the proposal run through the governor by the simulator, then
///         the end state, the `_validate` gates, the rebuild, and the authority the launch
///         leaves with the DAO MS and the Emergency MS.
contract YieldRepurchaseFacilityV2ProposalTests_execution is YieldRepurchaseFacilityV2ProposalRig {
    /// @notice The state the launch reads, captured before the proposal executes.
    LaunchInputs internal inputs;

    function setUp() public virtual override {
        super.setUp();

        inputs = _launchInputs();

        suite.setDebug(true);
        _simulateProposal();

        // Re-read addresses in case the simulation updated them
        addresses = suite.addresses();
    }

    // ========== HELPERS ========== //

    function _expectRevertParameterMismatch(
        string memory name_,
        uint256 actual_,
        uint256 expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_ParameterMismatch
                    .selector,
                name_,
                actual_,
                expected_
            )
        );
    }

    /// @notice Makes the facility report the asset of the vault with the unfunded yield.
    function _mockUnfundedYield(address vault_, uint256 unfundedYield_) internal {
        IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility.getAssetConfig(vault_);
        asset.unfundedYield = unfundedYield_;
        vm.mockCall(
            address(facility),
            abi.encodeWithSelector(facility.getAssetConfig.selector, vault_),
            abi.encode(asset)
        );
    }

    /// @notice Makes the PRICE module report the registration of USDe with the feed and the
    ///         update threshold.
    function _mockUsdeFeed(address feed_, uint48 updateThreshold_) internal {
        IPRICEv2.Asset memory asset = price.getAssetData(address(usde));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        feeds[0].params = abi.encode(feed_, updateThreshold_);
        asset.feeds = abi.encode(feeds);
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(IPRICEv2.getAssetData.selector, address(usde)),
            abi.encode(asset)
        );
    }

    // ========== END STATE ========== //

    // given the proposal has executed
    //   [X] v1.2 is shut down and the facility continues its weekly cycle with its funds
    //   [X] the five policies are enabled, with the launch values of the activator
    //   [X] the DAO MS holds yrf_admin and backing_admin, and nobody known holds loop_daddy
    //   [X] the activator holds no role and is activated
    //   [X] USDe is registered in the PRICE module

    function test_proposalEndState() public view {
        _assertMigrated(inputs, proposal.SUSDE_NEXT_YIELD());

        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters = activator
            .launchParameters();
        address[5] memory policies = _stackPolicies();
        for (uint256 i = 0; i < policies.length; ++i) {
            assertTrue(
                IEnabler(policies[i]).isEnabled(),
                string.concat("policy should be enabled: ", vm.toString(policies[i]))
            );
        }
        assertEq(backingOracle.backing(), parameters.backing, "backing");
        assertEq(facility.initialDiscount(), parameters.initialDiscount, "initialDiscount");
        assertEq(facility.maxPricePremium(), parameters.maxPricePremium, "maxPricePremium");
        assertEq(
            backingOracle.configOperator(),
            address(backingOracleConfigTimelock),
            "oracle config operator"
        );
        assertEq(config.configOperator(), address(configTimelock), "config operator");
        for (uint256 i = 0; i < parameters.clearinghouses.length; ++i) {
            assertEq(
                facility.isClearinghouseIncluded(parameters.clearinghouses[i].clearinghouse),
                parameters.clearinghouses[i].included,
                "Clearinghouse inclusion"
            );
            assertEq(
                facility.clearinghouseOffset(parameters.clearinghouses[i].clearinghouse),
                parameters.clearinghouses[i].offset,
                "Clearinghouse offset"
            );
        }

        // Roles
        assertTrue(roles.hasRole(daoMS, YRF_ADMIN_ROLE), "The DAO MS should hold yrf_admin");
        assertTrue(
            roles.hasRole(daoMS, BACKING_ADMIN_ROLE),
            "The DAO MS should hold backing_admin"
        );
        assertTrue(roles.hasRole(ocgTimelock, ADMIN_ROLE), "The OCG timelock should hold admin");
        assertTrue(
            roles.hasRole(emergencyMS, EMERGENCY_ROLE),
            "The Emergency MS should hold emergency"
        );
        assertFalse(roles.hasRole(address(activator), ADMIN_ROLE), "activator admin");
        assertFalse(roles.hasRole(address(activator), _LOOP_DADDY_ROLE), "activator loop_daddy");
        assertFalse(roles.hasRole(daoMS, _LOOP_DADDY_ROLE), "DAO MS loop_daddy");
        assertFalse(roles.hasRole(ocgTimelock, _LOOP_DADDY_ROLE), "OCG timelock loop_daddy");

        assertTrue(price.isAssetApproved(address(usde)), "USDe should be registered");
    }

    // given the proposal has executed
    //   when the proposal validates the state
    //     [X] it passes

    function test_givenExecuted_whenValidated() public view {
        proposal.validate(addresses, proposer);
    }

    // ========== VALIDATION GATES ========== //

    // given the proposal has executed
    //   given the Emergency MS has disabled the facility
    //     when the proposal validates the state
    //       [X] it reverts with PolicyNotEnabled naming the facility

    function test_givenExecuted_givenFacilityDisabled_whenValidated_reverts() public {
        address facilityAddress = address(facility);
        vm.prank(emergencyMS);
        facility.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_PolicyNotEnabled
                    .selector,
                facilityAddress
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has revoked the config operator of the configuration policy
    //     when the proposal validates the state
    //       [X] it reverts with AddressMismatch naming the config operator

    function test_givenExecuted_givenConfigOperatorRevoked_whenValidated_reverts() public {
        vm.prank(ocgTimelock);
        config.setConfigOperator(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AddressMismatch
                    .selector,
                "YieldRepurchaseFacilityV2Config configOperator",
                address(0),
                address(configTimelock)
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has changed the initial discount
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the initial discount

    function test_givenExecuted_givenInitialDiscountChanged_whenValidated_reverts() public {
        uint256 launched = facility.initialDiscount();
        vm.prank(ocgTimelock);
        config.setInitialDiscount(launched + 1);

        _expectRevertParameterMismatch(
            "YieldRepurchaseFacilityV2 initialDiscount",
            launched + 1,
            launched
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has changed the yield buyback share of the sUSDe vault
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the share of the vault

    function test_givenExecuted_givenYieldBuybackShareChanged_whenValidated_reverts() public {
        uint256 launched = facility.getAssetConfig(address(sUsde)).yieldBuybackShare;
        address vault = address(sUsde);
        vm.prank(ocgTimelock);
        config.setYieldBuybackShare(vault, launched - 1);

        _expectRevertParameterMismatch("sUSDe yieldBuybackShare", launched - 1, launched);
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has excluded an included Clearinghouse
    //     when the proposal validates the state
    //       [X] it reverts with FlagMismatch naming the Clearinghouse

    function test_givenExecuted_givenClearinghouseExcluded_whenValidated_reverts() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters = activator
            .launchParameters();
        address included;
        for (uint256 i = 0; i < parameters.clearinghouses.length; ++i) {
            if (!parameters.clearinghouses[i].included) continue;
            included = parameters.clearinghouses[i].clearinghouse;
            break;
        }
        require(included != address(0), "env: the launch should include a Clearinghouse");
        vm.prank(ocgTimelock);
        config.excludeClearinghouse(included);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_FlagMismatch
                    .selector,
                string.concat("Clearinghouse ", vm.toString(included), " included"),
                false,
                true
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given a third party has transferred USDS to v1.2
    //     when the proposal validates the state
    //       [X] it reverts with V1BalanceLeft naming the token and the balance

    function test_givenExecuted_givenTokenTransferredToV1_whenValidated_reverts() public {
        deal(address(usds), address(yieldRepoV1), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_V1BalanceLeft
                    .selector,
                address(usds),
                1
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given a third party has transferred an sUSDS share to the facility
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the shares of the sUSDS buyback pool

    function test_givenExecuted_givenShareTransferredToTheFacility_whenValidated_reverts() public {
        IERC20 shares = IERC20(address(sUsds));
        address facilityAddress = address(facility);
        // The shares that cover the funds of v1.2, which the end state test asserts
        uint256 held = shares.balanceOf(facilityAddress);
        vm.prank(treasury);
        shares.transfer(facilityAddress, 1);

        _expectRevertParameterMismatch("sUSDS buyback pool shares", held + 1, held);
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given a vault carries unfunded yield
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the unfunded yield of the vault

    function test_givenExecuted_givenSUsdsUnfundedYield_whenValidated_reverts() public {
        _mockUnfundedYield(address(sUsds), 1);

        _expectRevertParameterMismatch("sUSDS unfundedYield", 1, 0);
        proposal.validate(addresses, proposer);
    }

    function test_givenExecuted_givenSUsdeUnfundedYield_whenValidated_reverts() public {
        _mockUnfundedYield(address(sUsde), 1);

        _expectRevertParameterMismatch("sUSDe unfundedYield", 1, 0);
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the registration of USDe names another update threshold than the activator
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the update threshold of the feed
    //   given the registration of USDe names another feed than the activator
    //     when the proposal validates the state
    //       [X] it reverts with AddressMismatch naming the feed

    function test_givenExecuted_givenUsdeFeedThresholdChanged_whenValidated_reverts() public {
        uint48 launched = activator.USDE_FEED_UPDATE_THRESHOLD();
        _mockUsdeFeed(address(usdeUsdFeed), launched + 1);

        _expectRevertParameterMismatch("USDe feed updateThreshold", launched + 1, launched);
        proposal.validate(addresses, proposer);
    }

    function test_givenExecuted_givenUsdeFeedReplaced_whenValidated_reverts() public {
        address otherFeed = makeAddr("otherFeed");
        _mockUsdeFeed(otherFeed, activator.USDE_FEED_UPDATE_THRESHOLD());

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_AddressMismatch
                    .selector,
                "USDe feed",
                otherFeed,
                address(usdeUsdFeed)
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has removed the facility from the periodic tasks
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the number of periodic tasks

    function test_givenExecuted_givenFacilityTaskRemoved_whenValidated_reverts() public {
        IPeriodicTaskManager rigHeart = IPeriodicTaskManager(address(heart));
        address facilityAddress = address(facility);
        vm.prank(ocgTimelock);
        rigHeart.removePeriodicTask(facilityAddress);

        _expectRevertParameterMismatch(
            "Heart periodic task count",
            inputs.heartTaskCount - 1,
            inputs.heartTaskCount
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the Heart has beaten since
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the epoch counter: the validation
    //           describes the state the execution leaves, and the facility has moved on from
    //           the epoch v1.2 stopped at

    function test_givenExecuted_givenHeartBeats_whenValidated_reverts() public {
        _beat();

        // The epoch counter is the first compared value a beat moves
        uint256 epochAfterBeat = facility.epoch();
        assertNotEq(epochAfterBeat, inputs.epoch, "The beat should move the epoch counter");
        _expectRevertParameterMismatch(
            "YieldRepurchaseFacilityV2 epoch",
            epochAfterBeat,
            inputs.epoch
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given loop_daddy has been granted to the DAO MS again
    //     when the proposal validates the state
    //       [X] it reverts with UnexpectedRole naming the role and the DAO MS

    function test_givenExecuted_givenLoopDaddyGranted_whenValidated_reverts() public {
        _grantRole(_LOOP_DADDY_ROLE, daoMS);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_UnexpectedRole
                    .selector,
                _LOOP_DADDY_ROLE,
                daoMS
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given yrf_admin has been revoked from the DAO MS
    //     when the proposal validates the state
    //       [X] it reverts with MissingRole naming the role and the DAO MS

    function test_givenExecuted_givenYrfAdminRevoked_whenValidated_reverts() public {
        _revokeRole(YRF_ADMIN_ROLE, daoMS);

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_MissingRole
                    .selector,
                YRF_ADMIN_ROLE,
                daoMS
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the PRICE module reports USDe as not registered
    //     when the proposal validates the state
    //       [X] it reverts with UsdeNotRegistered naming USDe

    function test_givenExecuted_givenUsdeNotRegistered_whenValidated_reverts() public {
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(IPRICEv2.isAssetApproved.selector, address(usde)),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_UsdeNotRegistered
                    .selector,
                address(usde)
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the activator reports that it is not activated
    //     when the proposal validates the state
    //       [X] it reverts with FlagMismatch naming the flag of the activator

    function test_givenExecuted_givenActivatorNotActivated_whenValidated_reverts() public {
        vm.mockCall(
            address(activator),
            abi.encodeWithSelector(IYieldRepurchaseFacilityV2Activator.isActivated.selector),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldRepurchaseFacilityV2Proposal
                    .YieldRepurchaseFacilityV2Proposal_FlagMismatch
                    .selector,
                "activator isActivated",
                false,
                true
            )
        );
        proposal.validate(addresses, proposer);
    }

    // ========== REBUILD AND AUTHORITY ========== //

    // given the proposal has executed
    //   when the proposal is built again
    //     [X] it reverts with the AlreadyActivated error of the activator

    function test_givenExecuted_whenBuiltAgain_reverts() public {
        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_AlreadyActivated
                .selector
        );
        proposal.build(addresses);
    }

    // given the proposal has executed
    //   when the OCG timelock calls the activator again
    //     [X] it reverts with AlreadyActivated

    function test_givenExecuted_whenActivatedAgain_reverts() public {
        YieldRepurchaseFacilityV2Activator target = activator;
        uint256 nextYield = proposal.SUSDE_NEXT_YIELD();

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_AlreadyActivated
                .selector
        );
        vm.prank(ocgTimelock);
        target.activate(nextYield);
    }

    // given the proposal has executed
    //   when the DAO MS queues a change of the initial discount and the delay elapses
    //     [X] anyone executes it and the facility carries the new discount
    //   when the DAO MS queues an update of the backing and the delay elapses
    //     [X] anyone executes it and the oracle carries the new backing

    function test_givenExecuted_daoMSOperatesThroughTheTimelocks() public {
        uint256 newDiscount = facility.initialDiscount() + 1e16;
        // An update inside the 10% bound of the oracle: 1% above the launch backing
        uint256 newBacking = (backingOracle.backing() * 101) / 100;
        address executor = makeAddr("permissionlessExecutor");

        vm.prank(daoMS);
        uint64 discountAction = configTimelock.queueSetInitialDiscount(newDiscount);
        vm.prank(daoMS);
        uint64 backingAction = backingOracleConfigTimelock.queueSetBacking(newBacking);

        skip(uint256(configTimelock.timelockDelay()) + 1);

        vm.prank(executor);
        configTimelock.executeQueuedAction(discountAction);
        vm.prank(executor);
        backingOracleConfigTimelock.executeQueuedAction(backingAction);

        assertEq(facility.initialDiscount(), newDiscount, "The discount should be the queued one");
        assertEq(backingOracle.backing(), newBacking, "The backing should be the queued one");
    }

    // given the proposal has executed
    //   when an update of the backing by 10% is validated by the oracle
    //     [X] it passes in both directions
    //   when an update one unit beyond 10% is validated by the oracle
    //     [X] it reverts with BackingChangeTooLarge naming the bounds
    //   [X] the description states the bound of 10%

    function test_givenExecuted_backingUpdateBound() public {
        uint256 backing = backingOracle.backing();
        // backing (18 decimals) * 90% and * 110%, rounded down as the oracle rounds them
        uint256 minBacking = (backing * 90) / 100;
        uint256 maxBacking = (backing * 110) / 100;

        backingOracle.validateSetBacking(minBacking);
        backingOracle.validateSetBacking(maxBacking);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBackingOracle.BackingOracle_BackingChangeTooLarge.selector,
                backing,
                maxBacking + 1,
                minBacking,
                maxBacking
            )
        );
        backingOracle.validateSetBacking(maxBacking + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBackingOracle.BackingOracle_BackingChangeTooLarge.selector,
                backing,
                minBacking - 1,
                minBacking,
                maxBacking
            )
        );
        backingOracle.validateSetBacking(minBacking - 1);

        string memory description = proposal.description();
        assertTrue(
            vm.contains(description, "the oracle limits each update to 10% of the current value"),
            "The description should state the bound of the backing_admin updates"
        );
        assertTrue(
            vm.contains(description, "within a limit of 10% per update"),
            "The justification should state the same bound"
        );
    }

    // given the proposal has executed
    //   when the Emergency MS disables the facility and returns its funds
    //     [X] the facility is disabled and holds no share of its buyback pool
    //   when the DAO MS re-enables the facility inside the grace window
    //     [X] the facility is enabled at the epoch it stopped at

    function test_givenExecuted_emergencyMSStopsAndDaoMSResumes() public {
        uint48 epoch = facility.epoch();
        uint256 treasurySharesBefore = IERC20(address(sUsds)).balanceOf(treasury);
        uint256 facilityShares = IERC20(address(sUsds)).balanceOf(address(facility));

        vm.prank(emergencyMS);
        facility.disable("");
        vm.prank(emergencyMS);
        facility.returnFundsToTreasury();

        assertFalse(facility.isEnabled(), "The facility should be disabled");
        assertEq(
            IERC20(address(sUsds)).balanceOf(address(facility)),
            0,
            "The facility should hold no sUSDS"
        );
        assertEq(
            IERC20(address(sUsds)).balanceOf(treasury),
            treasurySharesBefore + facilityShares,
            "The treasury should receive the shares of the buyback pool"
        );

        vm.prank(daoMS);
        facility.reEnable();

        assertTrue(facility.isEnabled(), "The facility should be enabled again");
        assertEq(facility.epoch(), epoch, "The facility should resume at the epoch it stopped at");
    }

    // given the proposal has executed
    //   when a former holder of loop_daddy initializes v1.2 again
    //     [X] it reverts: nobody known holds loop_daddy

    function test_givenExecuted_whenV1InitializedAgain_reverts() public {
        address v1 = address(yieldRepoV1);
        bytes memory payload = abi.encodeWithSignature(
            "initialize(uint256,uint256,uint256)",
            1,
            1,
            1
        );

        vm.prank(daoMS);
        // The initializer is not part of the migration interface of v1.2
        // forge-lint: disable-next-item(low-level-calls)
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, bytes memory data) = v1.call(payload);

        assertFalse(ok, "The DAO MS should not initialize v1.2 again");
        assertEq(
            data,
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, _LOOP_DADDY_ROLE),
            "The call should fail on the loop_daddy role"
        );
        assertTrue(yieldRepoV1.isShutdown(), "v1.2 should stay shut down");
    }
}

// forge-lint: disable-end(multi-contract-file)

// forge-lint: disable-end(calls-loop)
