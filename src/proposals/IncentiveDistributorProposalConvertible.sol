// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.30;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";
import {console2} from "forge-std/console2.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IncentiveDistributorConvertible} from "src/policies/incentives/IncentiveDistributorConvertible.sol";
import {ConvertibleOHMTeller} from "src/policies/incentives/convertible/ConvertibleOHMTeller.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice Proposal to enable the Convertible OHM Incentive Distributor system
contract IncentiveDistributorProposalConvertible is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    /// TODO: Decide on the initial distributor mint cap
    /// @notice Per-creator mint cap (max outstanding convOHM) for the IncentiveDistributorConvertible (in OHM units, 9 decimals).
    ///         Also determines the initial MINTR approval head-room available to the teller.
    uint256 internal constant _INITIAL_DISTRIBUTOR_MINT_CAP = 1000e9;

    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant _ROLE_CONVERTIBLE_DISTRIBUTOR = bytes32("convertible_distributor");
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant _ROLE_INCENTIVE_MANAGER = bytes32("incentive_manager");

    /// @notice Expected periodic task count on the Heart after this proposal is executed.
    ///         The teller is appended at the end, so the count is the existing pre-proposal
    ///         count plus one. Snapshotted here to catch unexpected drift in the Heart's
    ///         periodic-task list between proposal authoring and execution.
    uint256 internal constant _EXPECTED_PERIODIC_TASK_COUNT = 7;

    /// @notice Index at which the teller is expected to live in the Heart's periodic-task list.
    uint256 internal constant _EXPECTED_TELLER_TASK_INDEX = 6;

    // ========== PROPOSAL ========== //

    /// TODO: change proposal id to actual
    function id() public pure override returns (uint256) {
        return 14;
    }

    function name() public pure override returns (string memory) {
        return "Convertible OHM Incentive Distributor Enablement";
    }

    /// TODO: Update description
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Olympus Engage: Convertible OHM Distributor Enablement\n\n",
                "## Summary\n\n",
                "This proposal enables the Convertible OHM distribution for the Olympus Engage incentive system, ",
                "consisting of the ConvertibleOHMTeller and IncentiveDistributorConvertible policies.\n\n",
                "## Proposal Actions\n\n",
                "1. Grant the `admin` role to the OCG timelock (if not already granted).\n",
                "2. Grant `convertible_distributor` role to IncentiveDistributorConvertible.\n",
                "3. Grant `incentive_manager` role to Distributor MS.\n",
                // TODO: specify the specific mint cap value when it becomes known
                "4. Enable the ConvertibleOHMTeller policy with the distributor's per-creator mint cap.\n",
                "5. Enable the IncentiveDistributorConvertible policy.\n",
                "6. Register the ConvertibleOHMTeller as a periodic task on the Heart so that ",
                "expired convertible tokens are swept on each Heart beat.\n\n",
                "## Result\n\n",
                "After execution, the Distributor MS will be able to post weekly merkle roots and deploy ",
                "Convertible OHM tokens for each epoch. Users will be able to claim their Convertible OHM incentives ",
                "and exercise them for OHM by paying the conversion price in the quote token.\n\n",
                "The ConvertibleOHMTeller is deployed with the following defaults (adjustable by governance):\n",
                "- `minDuration` = 1 day: minimum exercise window between eligible and expiry.\n",
                "- `minEligibleDelay` = 1 day: minimum delay between token deployment and eligibility, ",
                "providing the emergency role a time window to disable the contract if needed.\n\n",
                "The per-creator mint cap limits the cumulative convOHM the distributor can ever mint. ",
                "MINTR approval is adjusted atomically on create / exercise / sweep. ",
                "Expired tokens free up MINTR approval periodically when Heart sweeps them.\n\n",
                "## References\n\n",
                "TODO: Add RFC/OIP reference.\n",
                "TODO: Add link to PR.\n",
                "TODO: Add link to audit.\n"
            );
    }

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address) internal override {}

    function _build(Addresses addresses) internal override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address convertibleOhmTeller = addresses.getAddress(
            "olympus-policy-convertible-ohm-teller"
        );
        address incentiveDistributorConvertible = addresses.getAddress(
            "olympus-policy-incentive-distributor-convertible"
        );
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address distributorMS = addresses.getAddress("olympus-multisig-incentive-distributor");
        address timelock = addresses.getAddress("olympus-timelock");
        address heart = addresses.getAddress("olympus-policy-heart-1_7");

        // 1. Grant the admin role to the OCG timelock, if not already granted
        if (!roles.hasRole(timelock, ADMIN_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, ADMIN_ROLE, timelock),
                "Grant admin role to OCG Timelock"
            );
        } else {
            console2.log("OCG Timelock already has the admin role");
        }

        // 2. Grant convertible_distributor role to IncentiveDistributorConvertible
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                _ROLE_CONVERTIBLE_DISTRIBUTOR,
                incentiveDistributorConvertible
            ),
            "Grant convertible_distributor role to IncentiveDistributorConvertible"
        );

        // 3. Grant incentive_manager role to Distributor MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                _ROLE_INCENTIVE_MANAGER,
                distributorMS
            ),
            "Grant incentive_manager role to Distributor MS"
        );

        // 4. Enable ConvertibleOHMTeller with the distributor's mint cap
        {
            address[] memory creators = new address[](1);
            creators[0] = incentiveDistributorConvertible;
            uint256[] memory caps = new uint256[](1);
            caps[0] = _INITIAL_DISTRIBUTOR_MINT_CAP;
            _pushAction(
                convertibleOhmTeller,
                abi.encodeWithSelector(PolicyEnabler.enable.selector, abi.encode(creators, caps)),
                "Enable ConvertibleOHMTeller policy"
            );
        }

        // 5. Enable IncentiveDistributorConvertible
        _pushAction(
            incentiveDistributorConvertible,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, ""),
            "Enable IncentiveDistributorConvertible policy"
        );

        // 6. Register the teller as a periodic task on the Heart so that expired
        // convertible tokens are swept on each Heart beat.
        _pushAction(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTask.selector,
                convertibleOhmTeller
            ),
            "Register ConvertibleOHMTeller as a periodic task on the Heart"
        );
    }

    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    function _validate(Addresses addresses, address) internal view override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address convertibleOhmTeller = addresses.getAddress(
            "olympus-policy-convertible-ohm-teller"
        );
        address incentiveDistributorConvertible = addresses.getAddress(
            "olympus-policy-incentive-distributor-convertible"
        );
        address distributorMS = addresses.getAddress("olympus-multisig-incentive-distributor");
        address timelock = addresses.getAddress("olympus-timelock");
        address heart = addresses.getAddress("olympus-policy-heart-1_7");

        // Validate the OCG Timelock has the admin role
        require(roles.hasRole(timelock, ADMIN_ROLE), "OCG Timelock does not have the admin role");

        // Validate IncentiveDistributorConvertible has the convertible_distributor role
        require(
            roles.hasRole(incentiveDistributorConvertible, _ROLE_CONVERTIBLE_DISTRIBUTOR),
            "IncentiveDistributorConvertible does not have convertible_distributor role"
        );

        // Validate Distributor MS has the incentive_manager role
        require(
            roles.hasRole(distributorMS, _ROLE_INCENTIVE_MANAGER),
            "Distributor MS does not have incentive_manager role"
        );

        // Validate ConvertibleOHMTeller is enabled
        require(
            ConvertibleOHMTeller(convertibleOhmTeller).isEnabled(),
            "ConvertibleOHMTeller is not enabled"
        );

        // Validate the distributor's per-creator mint cap was set
        require(
            ConvertibleOHMTeller(convertibleOhmTeller).creatorMintCap(
                incentiveDistributorConvertible
            ) == _INITIAL_DISTRIBUTOR_MINT_CAP,
            "ConvertibleOHMTeller creator mint cap does not match _INITIAL_DISTRIBUTOR_MINT_CAP"
        );

        // Validate IncentiveDistributorConvertible is enabled
        require(
            IncentiveDistributorConvertible(incentiveDistributorConvertible).isEnabled(),
            "IncentiveDistributorConvertible is not enabled"
        );

        // Validate the teller is registered as a periodic task on the Heart
        require(
            IPeriodicTaskManager(heart).hasPeriodicTask(convertibleOhmTeller),
            "ConvertibleOHMTeller is not registered as a Heart periodic task"
        );

        // Validate the Heart's periodic-task list ends with the teller at the expected index,
        // catching any drift in the upstream task list between proposal authoring and execution.
        require(
            IPeriodicTaskManager(heart).getPeriodicTaskCount() == _EXPECTED_PERIODIC_TASK_COUNT,
            "Heart periodic task count does not match _EXPECTED_PERIODIC_TASK_COUNT"
        );
        (address tellerTaskAddr, ) = IPeriodicTaskManager(heart).getPeriodicTaskAtIndex(
            _EXPECTED_TELLER_TASK_INDEX
        );
        require(
            tellerTaskAddr == convertibleOhmTeller,
            "Heart periodic task at expected index is not the ConvertibleOHMTeller"
        );
    }
}

contract IncentiveDistributorProposalConvertibleScript is ProposalScript {
    constructor() ProposalScript(new IncentiveDistributorProposalConvertible()) {}
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
