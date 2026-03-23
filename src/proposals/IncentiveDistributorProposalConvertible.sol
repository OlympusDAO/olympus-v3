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
import {Kernel} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IncentiveDistributorConvertible} from "src/policies/incentives/IncentiveDistributorConvertible.sol";
import {IncentiveOHMTeller} from "src/policies/incentives/convertible/IncentiveOHMTeller.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice Proposal to enable the iOHM Incentive Distributor system
contract IncentiveDistributorProposalConvertible is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    /// TODO: Decide on the initial mint cap
    /// @notice Initial mint cap for the IncentiveOHMTeller (in OHM units, 9 decimals)
    uint256 internal constant INITIAL_MINT_CAP = 1000e9;

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 14;
    }

    function name() public pure override returns (string memory) {
        return "iOHM Incentive Distributor Enablement";
    }

    /// TODO: Update description
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# iOHM Incentive Distributor Enablement\n\n",
                "## Summary\n\n",
                "This proposal enables the iOHM incentive distribution system, ",
                "consisting of the IncentiveOHMTeller and IncentiveDistributorConvertible policies.\n\n",
                "## Proposal Actions\n\n",
                "1. Grant `incentive_distributor` role to IncentiveDistributorConvertible.\n",
                "2. Grant `convertible_admin` role to DAO MS.\n",
                "3. Grant `incentive_manager` role to Distributor MS.\n",
                // TODO: specify the specific minting cap value when it becomes known
                "4. Enable the IncentiveOHMTeller policy (with initial mint cap).\n",
                "5. Enable the IncentiveDistributorConvertible policy.\n\n",
                "## Result\n\n",
                "After execution, the Distributor MS will be able to post weekly merkle roots and deploy ",
                "iOHM tokens for each epoch. Users will be able to claim their iOHM incentives ",
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
        address iohmTeller = addresses.getAddress("olympus-policy-iohm-teller");
        address incentiveDistributorConvertible = addresses.getAddress(
            "olympus-policy-incentive-distributor-convertible"
        );
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address distributorMS = addresses.getAddress("olympus-multisig-incentive-distributor");

        // 1. Grant incentive_distributor role to IncentiveDistributorConvertible
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("incentive_distributor"),
                incentiveDistributorConvertible
            ),
            "Grant incentive_distributor role to IncentiveDistributorConvertible"
        );

        // 2. Grant convertible_admin role to DAO MS
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

        // 3. Grant incentive_manager role to Distributor MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("incentive_manager"),
                distributorMS
            ),
            "Grant incentive_manager role to Distributor MS"
        );

        // 4. Enable IncentiveOHMTeller (with initial mint cap)
        _pushAction(
            iohmTeller,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, abi.encode(INITIAL_MINT_CAP)),
            "Enable IncentiveOHMTeller policy"
        );

        // 5. Enable IncentiveDistributorConvertible
        _pushAction(
            incentiveDistributorConvertible,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, ""),
            "Enable IncentiveDistributorConvertible policy"
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
        address iohmTeller = addresses.getAddress("olympus-policy-iohm-teller");
        address incentiveDistributorConvertible = addresses.getAddress(
            "olympus-policy-incentive-distributor-convertible"
        );
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address distributorMS = addresses.getAddress("olympus-multisig-incentive-distributor");

        // Validate IncentiveDistributorConvertible has the incentive_distributor role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(incentiveDistributorConvertible, bytes32("incentive_distributor")),
            "IncentiveDistributorConvertible does not have incentive_distributor role"
        );

        // Validate DAO MS has the convertible_admin role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, bytes32("convertible_admin")),
            "DAO MS does not have convertible_admin role"
        );

        // Validate Distributor MS has the incentive_manager role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(distributorMS, bytes32("incentive_manager")),
            "Distributor MS does not have incentive_manager role"
        );

        // Validate IncentiveOHMTeller is enabled
        require(IncentiveOHMTeller(iohmTeller).isEnabled(), "IncentiveOHMTeller is not enabled");

        // Validate the teller's mint cap was set to INITIAL_MINT_CAP via enable(bytes)
        require(
            IncentiveOHMTeller(iohmTeller).remainingMintApproval() == INITIAL_MINT_CAP,
            "IncentiveOHMTeller mint cap does not match INITIAL_MINT_CAP"
        );

        // Validate IncentiveDistributorConvertible is enabled
        require(
            IncentiveDistributorConvertible(incentiveDistributorConvertible).isEnabled(),
            "IncentiveDistributorConvertible is not enabled"
        );
    }
}

contract IOHMIncentiveDistributorProposalScript is ProposalScript {
    constructor() ProposalScript(new IncentiveDistributorProposalConvertible()) {}
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
