// SPDX-License-Identifier: AGPL-3.0-only

// The Voter Registration Policy is a permissioned policy to mint and burn votes to arbitrary addresses
pragma solidity 0.8.13;

import { Kernel, Policy } from "src/Kernel.sol";
import { Auth, Authority } from "solmate/auth/Auth.sol";
import { OlympusVotes } from "modules/VOTES.sol";

contract VoterRegistration is Policy, Auth {
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Policy Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    OlympusVotes public VOTES;

    constructor(Kernel kernel_) Policy(kernel_) Auth(address(kernel_), Authority(address(0))) {}

    function configureReads() external override {
        VOTES = OlympusVotes(getModuleAddress("VOTES"));
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestRoles() external view override returns (Role[] memory roles) {
        roles = new Role[](1);
        roles[0] = VOTES.ISSUER();
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                               User Actions                                  //
    /////////////////////////////////////////////////////////////////////////////////

    function issueVotesTo(address wallet_, uint256 amount_) external requiresAuth {
        // issue the votes in the VOTES module
        VOTES.mintTo(wallet_, amount_);
    }

    function revokeVotesFrom(address wallet_, uint256 amount_) external requiresAuth {
        // revoke the votes in the VOTES module
        VOTES.burnFrom(wallet_, amount_);
    }
}
