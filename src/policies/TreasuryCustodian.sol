// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {Auth, Authority} from "solmate/auth/Auth.sol";

import {Kernel, Policy} from "../Kernel.sol";
import {OlympusTreasury} from "../modules/TRSRY.sol";

error PolicyStillActive();

// Generic contract to allow authorized contracts to interact with treasury
// Use cases include setting and removing approvals, as well as allocating assets for yield
contract OlympusTreasuryCustodian is Policy, Auth {
    /* ========== STATE VARIABLES ========== */

    /// Modules
    OlympusTreasury internal TRSRY;

    /* ========== CONSTRUCTOR ========== */

    constructor(Kernel kernel_)
        Policy(kernel_)
        Auth(address(kernel_), Authority(address(0)))
    {}

    /* ========== FRAMEWORK CONFIGURATION ========== */
    function configureReads() external override {
        TRSRY = OlympusTreasury(getModuleAddress("TRSRY"));
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Kernel.Role[] memory roles)
    {
        roles = new Kernel.Role[](2);
        roles[0] = TRSRY.APPROVER();
        roles[1] = TRSRY.DEBT_ADMIN();
    }

    // Anyone can call to revoke a terminated policy's approvals
    function revokePolicyApprovals(address policy_, ERC20[] memory tokens_)
        external
    {
        if (kernel.approvedPolicies(policy_)) revert PolicyStillActive();

        uint256 len = tokens_.length;
        for (uint256 i; i < len; ) {
            TRSRY.setApprovalFor(policy_, tokens_[i], 0);
            unchecked {
                ++i;
            }
        }
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
