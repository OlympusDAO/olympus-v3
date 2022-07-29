// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { Auth, Authority } from "solmate/auth/Auth.sol";

import { Kernel, Policy } from "src/Kernel.sol";
import { OlympusTreasury } from "src/modules/TRSRY.sol";

// ERRORS
error PolicyStillActive();
error PolicyNotFound();

// Generic contract to allow authorized contracts to interact with treasury
// Use cases include setting and removing approvals, as well as allocating assets for yield
contract TreasuryCustodian is Policy, Auth {
    /* ========== STATE VARIABLES ========== */
    event ApprovalRevoked(address indexed policy_, ERC20[] tokens_);

    // Modules
    OlympusTreasury internal TRSRY;

    /* ========== CONSTRUCTOR ========== */

    constructor(Kernel kernel_) Policy(kernel_) Auth(address(kernel_), Authority(address(0))) {}

    /* ========== FRAMEWORK CONFIGURATION ========== */
    function configureReads() external override {
        TRSRY = OlympusTreasury(getModuleAddress("TRSRY"));
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestRoles() external view override returns (Role[] memory roles) {
        roles = new Role[](2);
        roles[0] = TRSRY.APPROVER();
        roles[1] = TRSRY.DEBT_ADMIN();
    }

    function grantApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external requiresAuth {
        TRSRY.setApprovalFor(for_, token_, amount_);
    }

    // Anyone can call to revoke a terminated policy's approvals.
    // TODO Currently allows anyone to revoke any approval EXCEPT approved policies.
    // TODO must reorg policy storage to be able to check for unapproved policies.
    function revokePolicyApprovals(address policy_, ERC20[] memory tokens_) external {
        if (kernel.approvedPolicies(policy_)) revert PolicyStillActive();

        // TODO Make sure `policy_` is an actual policy and not a random address.

        uint256 len = tokens_.length;
        for (uint256 j; j < len; ) {
            TRSRY.setApprovalFor(policy_, tokens_[j], 0);
            unchecked {
                ++j;
            }
        }

        emit ApprovalRevoked(policy_, tokens_);
    }

    // Debt admin functions for authorized addresses to manipulate debt in special cases

    function increaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external requiresAuth {
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(token_, debtor_, debt + amount_);
    }

    function decreaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external requiresAuth {
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(token_, debtor_, debt - amount_);
    }
}
