// SPDX-License-Identifier: AGPL-3.0-only

// The Voter Registration Policy is a permissioned policy to mint and burn votes to arbitrary addresses
pragma solidity 0.8.15;

import "src/Kernel.sol";
import {OlympusVotes} from "modules/VOTES.sol";

contract VoterRegistration is Policy {
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Policy Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    OlympusVotes public VOTES;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("VOTES");

        VOTES = OlympusVotes(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](2);
        permissions[0] = Permissions(VOTES.KEYCODE(), VOTES.mintTo.selector);
        permissions[1] = Permissions(VOTES.KEYCODE(), VOTES.burnFrom.selector);
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                               User Actions                                  //
    /////////////////////////////////////////////////////////////////////////////////

    function issueVotesTo(address wallet_, uint256 amount_) external onlyRole("voter_admin") {
        // issue the votes in the VOTES module
        VOTES.mintTo(wallet_, amount_);
    }

    function revokeVotesFrom(address wallet_, uint256 amount_) external onlyRole("voter_admin") {
        // revoke the votes in the VOTES module
        VOTES.burnFrom(wallet_, amount_);
    }
}
