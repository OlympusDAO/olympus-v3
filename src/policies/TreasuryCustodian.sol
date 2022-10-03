// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {OlympusTreasury} from "src/modules/TRSRY.sol";
import {OlympusRoles, RolesConsumer} from "src/modules/ROLES.sol";
import "src/Kernel.sol";

// Generic contract to allow authorized contracts to interact with treasury
// Use cases include setting and removing approvals, as well as allocating assets for yield
contract TreasuryCustodian is Policy, RolesConsumer {
    event ApprovalRevoked(address indexed policy_, ERC20[] tokens_);

    error PolicyStillActive();
    error PolicyNotFound();

    OlympusTreasury public TRSRY;

    //OlympusRoles public ROLES;

    /*//////////////////////////////////////////////////////////////
                            POLICY INTERFACE
    //////////////////////////////////////////////////////////////*/
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("ROLES");

        TRSRY = TRSRY_V1(getModuleAddress(dependencies[0]));
        ROLES = ROLES_V1(getModuleAddress(dependencies[1]));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        requests = new Permissions[](5);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawerApproval.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseWithdrawerApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.increaseDebtorApproval.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseDebtorApproval.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function grantWithdrawerApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        //ROLES.requireRole("custodian", msg.sender);
        TRSRY.increaseWithdrawerApproval(for_, token_, amount_);
    }

    function grantDebtorApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external {
        ROLES.requireRole("custodian", msg.sender);
        TRSRY.increaseDebtorApproval(for_, token_, amount_);
    }

    /// @notice Anyone can call to revoke a deactivated policy's approvals.
    function revokePolicyApprovals(address policy_, ERC20[] memory tokens_) external {
        if (Policy(policy_).isActive()) revert PolicyStillActive();

        uint256 len = tokens_.length;
        for (uint256 j; j < len; ) {
            uint256 wApproval = TRSRY.withdrawApproval(policy_, tokens_[j]);
            if (wApproval > 0) TRSRY.decreaseWithdrawerApproval(policy_, tokens_[j], wApproval);

            uint256 dApproval = TRSRY.debtApproval(policy_, tokens_[j]);
            if (dApproval > 0) TRSRY.decreaseDebtorApproval(policy_, tokens_[j], dApproval);

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
    ) external {
        ROLES.requireRole("custodian", msg.sender);
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(debtor_, token_, debt + amount_);
    }

    function decreaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external {
        ROLES.requireRole("custodian", msg.sender);
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(debtor_, token_, debt - amount_);
    }
}
