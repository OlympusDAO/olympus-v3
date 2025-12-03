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
import {RewardDistributorUSDS} from "src/policies/RewardDistributorUSDS.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice Proposal to activate the USDSRewardDistributor
contract RewardDistributorProposalUSDS is GovernorBravoProposal {
    Kernel internal _kernel;

    function id() public pure override returns (uint256) {
        return 13;
    }

    function name() public pure override returns (string memory) {
        return "Activate USDS Reward Distributor";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Activate USDS Reward Distributor\n\n",
                "## Summary\n\n",
                "This proposal activates the USDS Reward Distributor policy to enable merkle-based ",
                "USDS rewards distribution to protocol users.\n\n",
                "## Proposal Actions\n\n",
                "1. Activate the USDSRewardDistributor policy in the Kernel\n",
                "2. Grant `rewards_merkle_updater` role to Distributor MS\n",
                "3. Enable the USDSRewardDistributor policy\n\n",
                "## Result\n\n",
                "After execution, the Distributor MS will be able to post weekly merkle roots, ",
                "and users will be able to claim their USDS rewards.\n"
            );
    }

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address) internal override {}

    function _build(Addresses addresses) internal override {
        address usdsRewardDistributor = addresses.getAddress(
            "olympus-policy-usdsrewarddistributor"
        );
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address distributorMS = addresses.getAddress("olympus-multisig-reward_distributor");

        // 1. Activate USDSRewardDistributor policy
        _pushAction(
            address(_kernel),
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                usdsRewardDistributor
            ),
            "Activate USDSRewardDistributor policy in Kernel"
        );

        // 2. Grant rewards_merkle_updater role to Distributor MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("rewards_merkle_updater"),
                distributorMS
            ),
            "Grant rewards_merkle_updater role to Distributor MS"
        );

        // 3. Enable the USDSRewardDistributor
        _pushAction(
            usdsRewardDistributor,
            abi.encodeWithSignature("enable(bytes)", ""),
            "Enable USDSRewardDistributor policy"
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
        address usdsRewardDistributor = addresses.getAddress(
            "olympus-policy-usdsrewarddistributor"
        );
        address distributorMS = addresses.getAddress("olympus-multisig-reward_distributor");

        // Validate policy is active
        require(
            Policy(usdsRewardDistributor).isActive(),
            "USDSRewardDistributor policy is not active"
        );

        // Validate Distributor MS has the merkle updater role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(distributorMS, bytes32("rewards_merkle_updater")),
            "Distributor MS does not have rewards_merkle_updater role"
        );

        // Validate policy is enabled
        require(
            RewardDistributorUSDS(usdsRewardDistributor).isEnabled(),
            "RewardDistributorUSDS is not enabled"
        );
    }
}

contract USDSRewardDistributorProposalScript is ProposalScript {
    constructor() ProposalScript(new RewardDistributorProposalUSDS()) {}
}
