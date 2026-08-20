// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.24;

// NOTE: The following registry keys must be added to `src/proposals/addresses.json` once
//       the contracts are deployed. They are referenced by this proposal but do not
//       exist in the registry yet:
//       - "olympus-policy-yieldrepurchasefacility-2_0": the YieldRepurchaseFacilityV2 policy
//       - "olympus-policy-yieldrepurchasefacility-config-timelock-1_0": the YieldRepurchaseFacilityConfigTimelock policy
//       - "olympus-policy-backing-oracle-1_0": the BackingOracle policy
//       - "olympus-yrf-v2-activator": the YieldRepurchaseFacilityV2Activator
//       - "external-tokens-sUSDe": 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497
//       - "external-tokens-USDe": 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Constants
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";

/// @notice OCG proposal that migrates the Yield Repurchase Facility (YRF) from the
///         deployed v1.2 to the multi-asset v2 stack (YieldRepurchaseFacilityV2,
///         YieldRepurchaseFacilityConfigTimelock) and the BackingOracle.
///
///         The YieldRepurchaseFacilityV2Activator performs the enablement, the v1.2
///         shutdown, the state migration, the asset registration, the Clearinghouse
///         configuration, the cycle seeding, and the Heart task swap in a single
///         proposal action, so that reading the v1.2 seeds and sweeping its funds are
///         atomic.
///
///         Assumes:
///         - The v2 stack and the activator have been deployed on Ethereum mainnet.
///         - The DAO MS has already activated the BackingOracle, the YieldRepurchaseFacilityConfigTimelock, and
///           the YieldRepurchaseFacilityV2 policies in the Kernel.
///         - The Bond Protocol multisig has already authorized the v2 facility as a
///           market callback on the SDA auctioneer.
contract YieldRepurchaseFacilityV2Proposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    /// @notice The `loop_daddy` role of YRF v1.2, granted to the activator for the
    ///         duration of the activation so that it can call `shutdown` on v1.2.
    bytes32 internal constant _LOOP_DADDY_ROLE = "loop_daddy";

    /// @notice The expected Heart periodic task count after the swap (unchanged from the
    ///         Convertible Deposits pipeline). This intentionally couples proposal
    ///         validation to the live task pipeline expected at submission; the activator
    ///         separately proves that its swap does not change the count.
    uint256 internal constant _EXPECTED_HEART_TASK_COUNT = 6;

    /// @notice The expected CHREG registry length at submission. This intentionally
    ///         couples proposal validation to the live registry expected at submission:
    ///         a Clearinghouse registered between authoring and execution must be
    ///         re-reviewed for its backing-yield treatment.
    uint256 internal constant _EXPECTED_CLEARINGHOUSE_COUNT = 3;

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 19;
    }

    function name() public pure override returns (string memory) {
        return "Yield Repurchase Facility V2 - Migration";
    }

    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                _descriptionSummary(),
                _descriptionPrerequisites(),
                _descriptionActions(),
                _descriptionFollowOn()
            );
    }

    function _descriptionSummary() private pure returns (string memory) {
        return
            string.concat(
                "# Yield Repurchase Facility V2 - Migration\n",
                "\n",
                "This proposal migrates the Yield Repurchase Facility (YRF) from the deployed v1.2 to the multi-asset v2.\n",
                "\n",
                "## Summary\n",
                "\n",
                "The proposal has three main components:\n",
                "\n",
                "1. Grant the operational roles of the v2 stack (`yrf_admin`, `backing_admin`) to the DAO MS.\n",
                "2. Execute the one-shot YieldRepurchaseFacilityV2Activator, which wires and enables the YieldRepurchaseFacilityConfigTimelock, the BackingOracle, and the YieldRepurchaseFacilityV2, shuts down YRF v1.2, migrates its accounting into the v2 seeds, registers sUSDe as a second yield asset, includes the Cooler v1 Clearinghouses in the backing yield, resumes the interrupted v1.2 week, and swaps the Heart periodic task from v1.2 to v2.\n",
                "3. Revoke the temporary roles from the activator and retire the v1.2 `loop_daddy` role.\n",
                "\n",
                "The migration preserves the v1.2 economics for sUSDS through a 100% yield buyback share and a 3% initial market discount. It adds a max price premium parameter that bounds the maximum value the bond market will pay for a single OHM token. The premium applies to the initial market price, which is already discounted, so the bound is `oraclePrice * (1 - initialDiscount) * (1 + maxPricePremium)`. The initial value is 10%: if the oracle price is $18, the maximum paid per OHM is $18 * 0.97 * 1.10 = $19.206. The new sUSDe asset also starts with a 100% yield buyback share. Backing launches at the current liquid backing value of 12.04 USDS per OHM, replacing the 11.33 value hardcoded in v1.2.\n",
                "\n",
                "The `yrf_admin` role queues bounded facility parameter changes through the YieldRepurchaseFacilityConfigTimelock, which launches with a 1-day delay, a 3-day permissionless execution window, and emergency cancellation. It can also re-enable the facility during its 5-day grace period and rescue untracked token balances or excess balances above the facility's accounting. The `backing_admin` role queues backing updates through the BackingOracle's 1-day timelock; each executed update is limited to a 10% increase or decrease, execution is permissionless for 7 days, and the emergency role can cancel queued updates. The OCG timelock's `admin` role retains a direct setter subject to the same 10% bound.\n",
                "\n",
                "## Affected Contracts\n",
                "\n",
                "- YieldRepurchaseFacility policy (existing - 1.2, shut down)\n",
                "- Heart policy (existing - 1.7, task slot 4 swapped)\n",
                "- YieldRepurchaseFacilityV2 policy (new - 2.0)\n",
                "- YieldRepurchaseFacilityConfigTimelock policy (new - 1.0)\n",
                "- BackingOracle policy (new - 1.0)\n",
                "\n"
            );
    }

    function _descriptionPrerequisites() private pure returns (string memory) {
        return
            string.concat(
                "## Pre-requisites\n",
                "\n",
                "The following must be completed before this proposal is queued. The OCG timelock's 24-hour execution window is too short to coordinate multisig actions between queueing and execution, and the activator reverts (failing the whole proposal) if any of them is missing:\n",
                "\n",
                "- The DAO MS has executed `kernel.executeAction(ActivatePolicy, ...)` for the BackingOracle, the YieldRepurchaseFacilityConfigTimelock, and the YieldRepurchaseFacilityV2 policies.\n",
                "- The Bond Protocol multisig (0x007BD11FCa0dAaeaDD455b51826F9a015f2f0969) has executed `setCallbackAuthStatus` on the SDA auctioneer for the YieldRepurchaseFacilityV2 address.\n",
                "- The DAO MS (the `price_admin` role holder) has registered USDe in the PRICE module through the PriceConfig v2 policy (`addAsset` with a Chainlink USDe/USD feed), so that `PRICE.getPriceIn(OHM, USDe)` resolves. The facility prices each asset live through `PRICE.getPriceIn(OHM, reserve)`, and both its `addAsset` registration probe and the activator precondition check depend on the resolution.\n",
                "\n"
            );
    }

    function _descriptionActions() private pure returns (string memory) {
        return string.concat(_descriptionActionsInstall(), _descriptionActionsCleanup());
    }

    function _descriptionActionsInstall() private pure returns (string memory) {
        return
            string.concat(
                "## Actions\n",
                "\n",
                "1. Grant the `yrf_admin` role to the DAO MS.\n",
                "2. Grant the `backing_admin` role to the DAO MS.\n",
                "3. Grant the temporary `admin` role to the activator.\n",
                "4. Grant the temporary `loop_daddy` role to the activator, so that the v1.2 shutdown runs inside `activate()`: reading the v1.2 seeds, burning its OHM balance, and sweeping its reserve funds.\n",
                "5. Execute `YieldRepurchaseFacilityV2Activator.activate()`, which:\n",
                "   - Validates the pre-requisites (Kernel activation, callback authorization, YRF v1.2 in Heart slot 4).\n",
                "   - Wires the YieldRepurchaseFacilityConfigTimelock to the facility and enables it.\n",
                "   - Enables the BackingOracle with the current liquid backing value of 12.04 USDS per OHM, replacing the 11.33 value hardcoded in YRF v1.2. The value becomes governance-updatable; `backing_admin` updates are timelocked and bounded to +/-10% per executed update.\n",
                "   - Enables the facility with a 3% initial discount, a 10% maximum price premium, and an empty seed array.\n",
                "   - Reads the v1.2 accounting (epoch, projected next yield, yield snapshots, residual funds) and shuts v1.2 down, burning its entire OHM balance and sweeping its USDS and sUSDS to the treasury.\n",
                "   - Registers sUSDS as the backing vault (100% buyback share) with the migrated v1.2 seeds.\n",
                "   - Registers sUSDe as a sell-shares yield asset (100% buyback share). Because it has no v1 history to migrate, its snapshots use the live treasury position and its fixed next-yield seed is a 4% annualized estimate: approximately 23,543 USDe for the first full week.\n",
                "   - Includes the Cooler v1 Clearinghouses (v1 and v1.1) in the backing yield.\n",
                "   - Seeds the running week: resumes the v1.2 epoch and re-injects the unspent v1.2 weekly budget into the sUSDS budget.\n",
                "   - Replaces YRF v1.2 with the v2 facility in slot 4 of the Heart periodic tasks.\n"
            );
    }

    function _descriptionActionsCleanup() private pure returns (string memory) {
        return
            string.concat(
                "6. Revoke the `loop_daddy` role from the activator.\n",
                "7. Revoke the `admin` role from the activator.\n",
                "8. Revoke the `loop_daddy` role from the DAO MS.\n",
                "9. Revoke the `loop_daddy` role from the OCG timelock.\n",
                "\n"
            );
    }

    function _descriptionFollowOn() private pure returns (string memory) {
        return
            string.concat(
                "## Follow-on MS Actions\n",
                "\n",
                "After this proposal executes, the DAO MS should:\n",
                "\n",
                "- Execute `kernel.executeAction(DeactivatePolicy, ...)` for the YRF v1.2 policy: the activator shuts it down, but only the Kernel executor can deactivate it.\n",
                "- Update the emergency configuration (the emergency multisig batch scripts) to target the v2 facility instead of v1.2."
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    function _build(Addresses addresses) internal override {
        address rolesAddr = addresses.getAddress("olympus-module-roles");
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address activator = addresses.getAddress("olympus-yrf-v2-activator");

        _requireNonZeroAddress(rolesAddr, "olympus-module-roles");
        _requireNonZeroAddress(rolesAdmin, "olympus-policy-roles-admin");
        _requireNonZeroAddress(daoMS, "olympus-multisig-dao");
        _requireNonZeroAddress(activator, "olympus-yrf-v2-activator");

        ROLESv1 roles = ROLESv1(rolesAddr);

        // 1. Grant the yrf_admin role to the DAO MS (conditional)
        if (!roles.hasRole(daoMS, YRF_ADMIN_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, YRF_ADMIN_ROLE, daoMS),
                "Grant yrf_admin role to the DAO MS"
            );
        }

        // 2. Grant the backing_admin role to the DAO MS (conditional)
        if (!roles.hasRole(daoMS, BACKING_ADMIN_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, BACKING_ADMIN_ROLE, daoMS),
                "Grant backing_admin role to the DAO MS"
            );
        }

        // 3. Grant the temporary admin role to the activator
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, ADMIN_ROLE, activator),
            "Grant admin role to temporary activator contract"
        );

        // 4. Grant the temporary loop_daddy role to the activator. The v1.2 shutdown must
        //    run inside `activate()`: reading the v1.2 seeds and sweeping its funds are
        //    atomic, so no external transaction can move the v1.2 state in between.
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, _LOOP_DADDY_ROLE, activator),
            "Grant loop_daddy role to temporary activator contract"
        );

        // 5. Execute the activator (single action: enablement + v1.2 shutdown + state
        //    migration + asset registration + Clearinghouse config + cycle seeding +
        //    Heart task swap).
        _pushAction(
            activator,
            abi.encodeWithSelector(YieldRepurchaseFacilityV2Activator.activate.selector),
            "Execute YieldRepurchaseFacilityV2Activator"
        );

        // 6. Revoke the temporary loop_daddy role from the activator
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, _LOOP_DADDY_ROLE, activator),
            "Revoke loop_daddy role from temporary activator contract"
        );

        // 7. Revoke the temporary admin role from the activator
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, ADMIN_ROLE, activator),
            "Revoke admin role from temporary activator contract"
        );

        // 8.-9. Retire the loop_daddy role together with YRF v1.2 (conditional). The role
        //       gates only the v1.x operational levers, including a re-`initialize` that
        //       would revive the shut-down v1.2.
        address timelock = addresses.getAddress("olympus-timelock");
        _requireNonZeroAddress(timelock, "olympus-timelock");

        if (roles.hasRole(daoMS, _LOOP_DADDY_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.revokeRole.selector, _LOOP_DADDY_ROLE, daoMS),
                "Revoke loop_daddy role from the DAO MS"
            );
        }

        if (roles.hasRole(timelock, _LOOP_DADDY_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.revokeRole.selector, _LOOP_DADDY_ROLE, timelock),
                "Revoke loop_daddy role from the OCG timelock"
            );
        }
    }

    function _run(Addresses addresses, address) internal override {
        // Simulates actions on TimelockController
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    function _validate(Addresses addresses, address) internal view override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        YieldRepurchaseFacilityV2Activator activator = YieldRepurchaseFacilityV2Activator(
            addresses.getAddress("olympus-yrf-v2-activator")
        );
        address yieldRepo = addresses.getAddress("olympus-policy-yieldrepurchasefacility-2_0");
        address yieldRepoV1 = addresses.getAddress("olympus-policy-yieldrepurchasefacility-1_2");

        // 1. Validate that the activator immutables match the registry
        {
            require(
                activator.YIELD_REPO() == yieldRepo,
                "Activator YIELD_REPO does not match the registry"
            );
            require(
                activator.CONFIG_TIMELOCK() ==
                    addresses.getAddress(
                        "olympus-policy-yieldrepurchasefacility-config-timelock-1_0"
                    ),
                "Activator CONFIG_TIMELOCK does not match the registry"
            );
            require(
                activator.BACKING_ORACLE() ==
                    addresses.getAddress("olympus-policy-backing-oracle-1_0"),
                "Activator BACKING_ORACLE does not match the registry"
            );
        }

        // 2. Validate that YRF v1.2 is shut down and swept
        {
            address usds = addresses.getAddress("external-tokens-USDS");
            address susds = addresses.getAddress("external-tokens-sUSDS");

            require(IYieldRepo(yieldRepoV1).isShutdown() == true, "YRF v1.2 is not shut down");
            require(
                IERC20(usds).balanceOf(yieldRepoV1) == 0,
                "YRF v1.2 still holds a USDS balance"
            );
            require(
                IERC20(susds).balanceOf(yieldRepoV1) == 0,
                "YRF v1.2 still holds an sUSDS balance"
            );
        }

        // 3. Validate the v2 facility state
        {
            address susds = addresses.getAddress("external-tokens-sUSDS");
            address susde = addresses.getAddress("external-tokens-sUSDe");
            IYieldRepurchaseFacilityV2 yrf = IYieldRepurchaseFacilityV2(yieldRepo);

            require(Policy(yieldRepo).isActive() == true, "YRF v2 policy is not active");
            require(IEnabler(yieldRepo).isEnabled() == true, "YRF v2 is not enabled");
            require(
                yrf.backingOracle() == addresses.getAddress("olympus-policy-backing-oracle-1_0"),
                "YRF v2 backing oracle does not match the registry"
            );
            require(
                yrf.timelock() ==
                    addresses.getAddress(
                        "olympus-policy-yieldrepurchasefacility-config-timelock-1_0"
                    ),
                "YRF v2 timelock does not match the registry"
            );
            require(
                yrf.bondAuctioneer() == activator.BOND_AUCTIONEER(),
                "YRF v2 bond auctioneer is incorrect"
            );
            require(yrf.bondTeller() == activator.BOND_TELLER(), "YRF v2 teller is incorrect");

            address[] memory vaults = yrf.getVaults();
            require(vaults.length == 2, "YRF v2 does not have exactly two vaults");
            require(vaults[0] == susds, "YRF v2 vault 0 is not sUSDS");
            require(vaults[1] == susde, "YRF v2 vault 1 is not sUSDe");
            require(yrf.backingVault() == susds, "YRF v2 backing vault is not sUSDS");

            IYieldRepurchaseFacilityV2.ReserveAsset memory susdsConfig = yrf.getAssetConfig(susds);
            require(
                susdsConfig.yieldBuybackShare == activator.SUSDS_BUYBACK_SHARE(),
                "sUSDS buyback share is not 100%"
            );
            require(susdsConfig.sellShares == false, "sUSDS must not sell shares");
            // The migrated v1.2 projection must have been carried over
            require(susdsConfig.nextYield > 0, "sUSDS next yield was not migrated");

            IYieldRepurchaseFacilityV2.ReserveAsset memory susdeConfig = yrf.getAssetConfig(susde);
            require(
                susdeConfig.yieldBuybackShare == activator.SUSDE_BUYBACK_SHARE(),
                "sUSDe buyback share is not 100%"
            );
            require(susdeConfig.sellShares == true, "sUSDe must sell shares");
            require(
                susdeConfig.nextYield == activator.SUSDE_NEXT_YIELD_SEED(),
                "sUSDe next yield does not match the fixed seed"
            );

            // The activator's `seedCycle` consumes the seeding window that its `enable`
            // opened (no heart beat runs inside the proposal execution).
            require(yrf.isCycleSeedable() == false, "YRF v2 cycle was not seeded");
            // The seeded epoch resumes the v1.2 counter, which the shutdown leaves in
            // place.
            require(
                yrf.epoch() == IYieldRepo(yieldRepoV1).epoch(),
                "YRF v2 epoch does not resume the v1.2 epoch"
            );
            require(
                yrf.initialDiscount() == activator.INITIAL_DISCOUNT(),
                "YRF v2 initial discount is incorrect"
            );
            require(
                yrf.maxPricePremium() == activator.MAX_PRICE_PREMIUM(),
                "YRF v2 max price premium is incorrect"
            );
        }

        // 4. Validate the Clearinghouse configuration
        {
            IYieldRepurchaseFacilityV2 yrf = IYieldRepurchaseFacilityV2(yieldRepo);
            CHREGv1 chreg = CHREGv1(address(_kernel.getModuleForKeycode(toKeycode("CHREG"))));
            address usds = addresses.getAddress("external-tokens-USDS");

            // Every registry Clearinghouse must count toward the backing yield: through
            // the USDS reserve-token filter or through an explicit inclusion. The
            // DAI-denominated v1 and v1.1 Clearinghouses lack a `reserve()` returning
            // USDS, so they must be the included ones.
            uint256 registryCount = chreg.registryCount();
            require(
                registryCount == _EXPECTED_CLEARINGHOUSE_COUNT,
                "CHREG registry count does not match the expected count"
            );
            for (uint256 i = 0; i < registryCount; i++) {
                address clearinghouse = chreg.registry(i);
                require(
                    yrf.isClearinghouseIncluded(clearinghouse) ||
                        _readClearinghouseReserve(clearinghouse) == usds,
                    "A registry Clearinghouse does not count toward the backing yield"
                );
                require(
                    yrf.clearinghouseOffset(clearinghouse) == 0,
                    "A Clearinghouse offset should be unset"
                );
            }

            require(
                yrf.isClearinghouseIncluded(activator.CLEARINGHOUSE_V1()) == true,
                "Cooler v1 Clearinghouse v1 is not included"
            );
            require(
                yrf.isClearinghouseIncluded(activator.CLEARINGHOUSE_V1_1()) == true,
                "Cooler v1 Clearinghouse v1.1 is not included"
            );
        }

        // 5. Validate the backing oracle
        {
            address backingOracle = addresses.getAddress("olympus-policy-backing-oracle-1_0");

            require(Policy(backingOracle).isActive() == true, "BackingOracle is not active");
            require(IEnabler(backingOracle).isEnabled() == true, "BackingOracle is not enabled");
            require(
                IBackingOracle(backingOracle).backing() == activator.BACKING(),
                "BackingOracle backing is incorrect"
            );
        }

        // 6. Validate the config timelock
        {
            address configTimelock = addresses.getAddress(
                "olympus-policy-yieldrepurchasefacility-config-timelock-1_0"
            );

            require(
                Policy(configTimelock).isActive() == true,
                "YieldRepurchaseFacilityConfigTimelock is not active"
            );
            require(
                IEnabler(configTimelock).isEnabled() == true,
                "YieldRepurchaseFacilityConfigTimelock is not enabled"
            );
            require(
                IYieldRepurchaseFacilityConfigTimelock(configTimelock).facility() == yieldRepo,
                "YieldRepurchaseFacilityConfigTimelock facility is not the v2 facility"
            );
        }

        // 7. Validate the Heart periodic task swap
        {
            address heart = addresses.getAddress("olympus-policy-heart-1_7");

            (address task, ) = IPeriodicTaskManager(heart).getPeriodicTaskAtIndex(
                activator.HEART_YRF_TASK_INDEX()
            );
            require(task == yieldRepo, "Heart slot 4 is not the v2 facility");
            require(
                IPeriodicTaskManager(heart).getPeriodicTaskCount() == _EXPECTED_HEART_TASK_COUNT,
                "Heart does not have the expected number of periodic tasks"
            );
        }

        // 8. Validate the roles
        {
            address daoMS = addresses.getAddress("olympus-multisig-dao");

            require(
                roles.hasRole(daoMS, YRF_ADMIN_ROLE) == true,
                "DAO MS does not have the yrf_admin role"
            );
            require(
                roles.hasRole(daoMS, BACKING_ADMIN_ROLE) == true,
                "DAO MS does not have the backing_admin role"
            );
            require(
                roles.hasRole(address(activator), ADMIN_ROLE) == false,
                "Activator should not have the admin role"
            );
            require(
                roles.hasRole(address(activator), _LOOP_DADDY_ROLE) == false,
                "Activator should not have the loop_daddy role"
            );
            require(
                roles.hasRole(daoMS, _LOOP_DADDY_ROLE) == false,
                "DAO MS should not have the loop_daddy role"
            );
            require(
                roles.hasRole(addresses.getAddress("olympus-timelock"), _LOOP_DADDY_ROLE) == false,
                "OCG timelock should not have the loop_daddy role"
            );
        }

        // 9. Validate that the activator is spent
        require(activator.isActivated() == true, "Activator is not marked as activated");

        // 10. Validate the bond callback authorization
        require(
            IBondAuctioneer(activator.BOND_AUCTIONEER()).callbackAuthorized(yieldRepo) == true,
            "YRF v2 is not callback-authorized on the auctioneer"
        );
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Reverts if the address is zero, including the registry key in the message.
    function _requireNonZeroAddress(address addr_, string memory key_) internal pure {
        require(addr_ != address(0), string.concat(key_, " address is zero"));
    }

    /// @notice Reads `reserve()` of a Clearinghouse, treating a revert or a malformed
    ///         return as the zero address (the v1 and v1.1 Clearinghouses expose
    ///         `dai()` instead).
    function _readClearinghouseReserve(address clearinghouse_) internal view returns (address) {
        (bool success, bytes memory data) = clearinghouse_.staticcall(
            abi.encodeWithSignature("reserve()")
        );
        if (!success || data.length < 32) return address(0);
        return abi.decode(data, (address));
    }
}

contract YieldRepurchaseFacilityV2ProposalScript is ProposalScript {
    constructor() ProposalScript(new YieldRepurchaseFacilityV2Proposal()) {}
}
