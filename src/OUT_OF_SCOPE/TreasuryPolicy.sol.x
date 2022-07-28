// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

/// DEPS

import "test-utils/convert.sol";
import "solmate/auth/Auth.sol";

/// LOCAL

import "interfaces/TreasuryAction.sol";
import "interfaces/EndStateVerifier.sol";

import "src/Kernel.sol";
import "src/modules/TRSRY.sol";

/// ERRORS

error TreasuryPolicy_RequestedTooMuch(uint256 delta_);
error TreasuryPolicy_BorrowerNotAllowed(address borrower_);
error TreasuryPolicy_FlashOperationFailed(
    address action_,
    address verifier_,
    string reason_
);

contract TreasuryPolicy is Auth, Policy {
    using convert for *;

    OlympusTreasury public treasury;
    EndStateVerifier public verifier;

    mapping(address => bool) public isAllowedBorrower;

    constructor(address kernel_)
        Auth(kernel_, Authority(address(0)))
        Policy(Kernel(kernel_))
    {}

    function configureReads() external override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
        treasury = OlympusTreasury(payable(getModuleAddress("TRSRY")));
    }

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Role[] memory roles)
    {
        roles = new Role[](1);
        permissions[0] = "TRSRY";
    }

    function flashOperation(address token, uint256 amount) external {
        address action = msg.sender;
        uint256 approved = treasury.withdrawApproval(action, token);

        // checks (TODO: think)
        if (approved < amount)
            revert TreasuryPolicy_RequestedTooMuch(amount - approved);

        // interactions
        treasury.changeApproval(action, token, amount, false);

        treasury.withdrawReserves(action, token, amount);

        TreasuryAction(action).execute();

        (bool result, string memory failMessage) = verifier.verify(); // will revert if verifier is addr 0

        if (!result)
            revert TreasuryPolicy_FlashOperationFailed(
                action,
                address(verifier),
                failMessage
            );

        verifier = EndStateVerifier(address(0));
    }

    function loanReserves(
        address borrower,
        address token,
        uint256 amount
    ) external requiresAuth {
        // checks TODO: think
        if (!isAllowedBorrower[borrower])
            revert TreasuryPolicy_BorrowerNotAllowed(borrower);

        // interactions
        treasury.loanReserves(borrower, token, amount);
    }

    function repayReserves(
        address debtor,
        address token,
        uint256 amount
    ) external requiresAuth {
        treasury.repayReserves(debtor, token, amount);
    }

    // ######################## ~ AUTHED ~ ########################

    function approveBorrower(address borrower) external requiresAuth {
        isAllowedBorrower[borrower] = true;
    }

    function removeBorrower(address borrower) external requiresAuth {
        isAllowedBorrower[borrower] = false;
    }

    function setVerifier(address verifier_) external requiresAuth {
        verifier = EndStateVerifier(verifier_);
    }

    /// @dev killed
    function setOwner(address) public override {}
}
