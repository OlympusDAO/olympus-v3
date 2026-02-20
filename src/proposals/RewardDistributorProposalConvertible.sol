// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Contracts
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RewardDistributorConvertible} from "src/policies/rewards/RewardDistributorConvertible.sol";
import {ConvertibleOHMTeller} from "src/policies/rewards/convertible/ConvertibleOHMTeller.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice Proposal to activate the ConvertibleOHM Reward Distributor system
contract RewardDistributorProposalConvertible is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    /// TODO: Decide on the initial mint cap
    /// @notice Initial mint cap for the ConvertibleOHMTeller (in OHM units, 9 decimals)
    uint256 internal constant INITIAL_MINT_CAP = 1000e9;

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 14;
    }

    function name() public pure override returns (string memory) {
        return "Activate Convertible OHM Reward Distributor";
    }

    /// TODO: Update description
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Activate Convertible OHM Reward Distributor\n\n",
                "## Summary\n\n",
                "This proposal activates the Convertible OHM reward distribution system, ",
                "consisting of the ConvertibleOHMTeller and RewardDistributorConvertible policies.\n\n",
                "## Proposal Actions\n\n",
                "1. Grant `convertible_distributor` role to RewardDistributorConvertible.\n",
                "2. Grant `convertible_admin` role to DAO MS.\n",
                "3. Grant `rewards_manager` role to Distributor MS.\n",
                // TODO: specify the specific minting cap value when it becomes known
                "4. Enable the ConvertibleOHMTeller policy (with initial mint cap).\n",
                "5. Enable the RewardDistributorConvertible policy.\n\n",
                "## Result\n\n",
                "After execution, the Distributor MS will be able to post weekly merkle roots and deploy ",
                "convertible OHM tokens for each epoch. Users will be able to claim their convertible OHM rewards ",
                "and exercise them for OHM by paying the conversion price in the quote token.\n\n",
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
        address convertibleOHMTeller = addresses.getAddress(
            "olympus-policy-convertible-ohm-teller"
        );
        address rewardDistributorConvertible = addresses.getAddress(
            "olympus-policy-reward-distributor-convertible"
        );
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address distributorMS = addresses.getAddress("olympus-multisig-reward-distributor");

        // 1. Activate ConvertibleOHMTeller policy
        _pushAction(
            address(_kernel),
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                convertibleOHMTeller
            ),
            "Activate ConvertibleOHMTeller policy in Kernel"
        );

        // 2. Activate RewardDistributorConvertible policy
        _pushAction(
            address(_kernel),
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                rewardDistributorConvertible
            ),
            "Activate RewardDistributorConvertible policy in Kernel"
        );

        // 3. Grant convertible_distributor role to RewardDistributorConvertible
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("convertible_distributor"),
                rewardDistributorConvertible
            ),
            "Grant convertible_distributor role to RewardDistributorConvertible"
        );

        // 4. Grant convertible_admin role to DAO MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("convertible_admin"),
                daoMS
            ),
            "Grant convertible_admin role to DAO MS"
        );

        // 5. Grant rewards_manager role to Distributor MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("rewards_manager"),
                distributorMS
            ),
            "Grant rewards_manager role to Distributor MS"
        );

        // 6. Enable ConvertibleOHMTeller (with initial mint cap)
        _pushAction(
            convertibleOHMTeller,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, abi.encode(INITIAL_MINT_CAP)),
            "Enable ConvertibleOHMTeller policy"
        );

        // 7. Enable RewardDistributorConvertible
        _pushAction(
            rewardDistributorConvertible,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, ""),
            "Enable RewardDistributorConvertible policy"
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
        address convertibleOHMTeller = addresses.getAddress(
            "olympus-policy-convertible-ohm-teller"
        );
        address rewardDistributorConvertible = addresses.getAddress(
            "olympus-policy-reward-distributor-convertible"
        );
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address distributorMS = addresses.getAddress("olympus-multisig-reward-distributor");

        // Validate ConvertibleOHMTeller is active
        require(
            Policy(convertibleOHMTeller).isActive(),
            "ConvertibleOHMTeller policy is not active"
        );

        // Validate RewardDistributorConvertible is active
        require(
            Policy(rewardDistributorConvertible).isActive(),
            "RewardDistributorConvertible policy is not active"
        );

        // Validate RewardDistributorConvertible has the convertible_distributor role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(rewardDistributorConvertible, bytes32("convertible_distributor")),
            "RewardDistributorConvertible does not have convertible_distributor role"
        );

        // Validate DAO MS has the convertible_admin role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, bytes32("convertible_admin")),
            "DAO MS does not have convertible_admin role"
        );

        // Validate Distributor MS has the rewards_manager role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(distributorMS, bytes32("rewards_manager")),
            "Distributor MS does not have rewards_manager role"
        );

        // Validate ConvertibleOHMTeller is enabled
        require(
            ConvertibleOHMTeller(convertibleOHMTeller).isEnabled(),
            "ConvertibleOHMTeller is not enabled"
        );

        // Validate the teller's mint cap was set to INITIAL_MINT_CAP via enable(bytes)
        require(
            ConvertibleOHMTeller(convertibleOHMTeller).remainingMintApproval() == INITIAL_MINT_CAP,
            "ConvertibleOHMTeller mint cap does not match INITIAL_MINT_CAP"
        );

        // Validate RewardDistributorConvertible is enabled
        require(
            RewardDistributorConvertible(rewardDistributorConvertible).isEnabled(),
            "RewardDistributorConvertible is not enabled"
        );
    }
}

contract ConvertibleOHMRewardDistributorProposalScript is ProposalScript {
    constructor() ProposalScript(new RewardDistributorProposalConvertible()) {}
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
