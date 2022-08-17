// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {OlympusTreasury} from "src/modules/TRSRY.sol";
import "src/Kernel.sol";

// ERRORS
error PolicyStillActive();
error PolicyNotFound();

// Generic contract to allow authorized contracts to interact with treasury
// Use cases include setting and removing approvals, as well as allocating assets for yield
contract TreasuryCustodian is Policy {
    /* ========== STATE VARIABLES ========== */
    event ApprovalRevoked(address indexed policy_, ERC20[] tokens_);

    // Modules
    OlympusTreasury internal TRSRY;

    /* ========== CONSTRUCTOR ========== */

    constructor(Kernel kernel_) Policy(kernel_) {}

    /* ========== FRAMEWORK CONFIGURATION ========== */
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TRSRY");

        TRSRY = OlympusTreasury(getModuleAddress(dependencies[0]));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        requests = new Permissions[](2);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.setApprovalFor.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
    }

    function grantApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        TRSRY.setApprovalFor(for_, token_, amount_);
    }

    // Anyone can call to revoke a deactivated policy's approvals.
    // TODO Currently allows anyone to revoke any approval EXCEPT activated policies.
    // TODO must reorg policy storage to be able to check for deactivated policies.
    function revokePolicyApprovals(address policy_, ERC20[] memory tokens_) external {
        if (Policy(policy_).isActive()) revert PolicyStillActive();

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
    ) external onlyRole("custodian") {
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(token_, debtor_, debt + amount_);
    }

    function decreaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole("custodian") {
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(token_, debtor_, debt - amount_);
    }
}
