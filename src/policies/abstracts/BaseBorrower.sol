// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {LENDRv1} from "src/modules/LENDR/LENDR.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

/// @title Olympus Base Borrower Contract
contract BaseBorrower is Policy, RolesConsumer {
    // ========= STATE ========= //

    // Modules
    LENDRv1 public LENDR;
    MINTRv1 public MINTR;

    // User State
    mapping(address => uint256) public debtOutstanding; // Debt outstanding

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = LENDR.KEYCODE();
        dependencies[1] = MINTR.KEYCODE();
        dependencies[2] = ROLES.KEYCODE();

        LENDR = LENDRv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](5);
        permissions[0] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(LENDR.KEYCODE(), LENDR.borrow.selector);
        permissions[4] = Permissions(LENDR.KEYCODE(), LENDR.repay.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice         Borrow and deposit OHM into the system this policy is responsible for
    /// @param amount_  The amount of OHM to borrow and deposit
    function deposit(uint256 amount_) external virtual {}

    /// @notice         Withdraw and repay OHM from the system this policy is responsible for
    /// @param amount_  The amount of OHM to withdraw and repay
    function withdraw(uint256 amount_) external virtual {}

    /// @notice         Update the policy's state. Harvests yield, and manages amount of OHM deployed
    function update() external virtual {}

    /// @notice         Harvests accrued interest from the system this policy is responsible for
    function harvestYield() external virtual {}

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @notice         Returns the amount of OHM that is currently deployed (idle + borrowed) by this policy
    function getDeployedSupply() external view virtual returns (uint256) {}

    /// @notice         Returns the amount of OHM that should be deployed to achieve a target interest rate
    function getTargetDeployedSupply() external view virtual returns (uint256) {}

    /// @notice         Returns the amount of OHM deployed that is actively borrowed in the system this policy is responsible for
    function getBorrowedSupply() external view virtual returns (uint256) {}

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _borrow(uint256 amount_) internal {
        debtOutstanding[msg.sender] += amount_;
        LENDR.borrow(amount_);
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    function _repay(uint256 amount_) internal {
        debtOutstanding[msg.sender] -= amount_;
        MINTR.burnOhm(address(this), amount_);
        LENDR.repay(amount_);
    }
}
