// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import "src/Kernel.sol";
import {RolesConsumer, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";

interface IDaiUsds {
    function daiToUsds(address usr, uint256 wad) external;
}

contract ReserveMigrator is Policy, RolesConsumer {
    // ========== ERRORS ========== //

    error ReserveMigrator_InvalidParams();
    error ReserveMigrator_BadMigration();

    // ========== EVENTS ========== //

    event MigratedReserves(address indexed from, address indexed to, uint256 amount);

    // ========== STATE VARIABLES ========== //

    // Modules
    TRSRYv1 internal TRSRY;

    // Reserves to migrate
    ERC20 public immutable from;
    ERC4626 public immutable sFrom;
    ERC20 public immutable to;
    ERC4626 public immutable sTo;

    // Migration contract
    IDaiUsds public migrator;

    bool public locallyActive;

    // ========== SETUP ========== //

    constructor(Kernel kernel_, address sFrom_, address sTo_, address migrator_) Policy(kernel_) {
        // Confirm the addresses are not null
        if (sFrom_ == address(0) || sTo_ == address(0) || migrator_ == address(0))
            revert ReserveMigrator_InvalidParams();

        sFrom = ERC4626(sFrom_);
        from = ERC20(sFrom.asset());
        sTo = ERC4626(sTo_);
        to = ERC20(sTo.asset());
        migrator = IDaiUsds(migrator_);

        locallyActive = true;
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (ROLES_MAJOR != 1 || TRSRY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        permissions = new Permissions[](2);
        permissions[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        permissions[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
    }

    // ========== MIGRATE RESERVES ========== //

    /// @notice migrate reserves and wrapped reserves in the treasury to the new reserve token
    /// @dev this function is restricted to the heart role to avoid complications with opportunistic conversions
    function migrate() external onlyRole("heart") {
        // Do nothing if the policy is not active
        if (!locallyActive) return;

        // Get the from and sFrom balances from the TRSRY
        // Note: we want actual token balances, not "reserveBalances" that include debt.
        uint256 fromBalance = from.balanceOf(address(TRSRY));
        uint256 sFromBalance = sFrom.balanceOf(address(TRSRY));

        // Withdraw the reserves from the TRSRY
        if (fromBalance > 0) {
            // Increase withdrawal approval and withdraw the reserves from the TRSRY
            TRSRY.increaseWithdrawApproval(address(this), from, fromBalance);
            TRSRY.withdrawReserves(address(this), from, fromBalance);
        }

        if (sFromBalance > 0) {
            // Increase withdrawal approval and withdraw the wrapped reserves from the TRSRY
            TRSRY.increaseWithdrawApproval(address(this), sFrom, sFromBalance);
            TRSRY.withdrawReserves(address(this), sFrom, sFromBalance);
        }

        // Update the sFrom balance to include any existing tokens in this contract
        // as well as the ones withdrawn from the TRSRY
        sFromBalance = sFrom.balanceOf(address(this));
        if (sFromBalance > 0) {
            sFrom.redeem(sFromBalance, address(this), address(this));
        }

        // Update the from balance based on any existing tokens, withdrawals, or redemptions
        fromBalance = from.balanceOf(address(this));

        // If the total is greater than 0, migrate the reserves
        if (fromBalance > 0) {
            // Approve the migrator for the total amount of from reserves
            from.approve(address(migrator), fromBalance);

            // Cache the balance of the to token
            uint256 toBalance = to.balanceOf(address(this));

            // Migrate the reserves
            migrator.daiToUsds(address(this), fromBalance);

            uint256 newToBalance = to.balanceOf(address(this));

            // Confirm that the to balance has increased by at least the previous from balance
            if (newToBalance < toBalance + fromBalance) revert ReserveMigrator_BadMigration();

            // Wrap the to reserves and deposit them into the TRSRY
            to.approve(address(sTo), newToBalance);
            sTo.deposit(newToBalance, address(TRSRY));

            // Emit event
            emit MigratedReserves(address(from), address(to), fromBalance);
        }
    }

    // ========== ADMIN FUNCTIONS ========== //

    function activate() external onlyRole("reserve_migrator_admin") {
        locallyActive = true;
    }

    function deactivate() external onlyRole("reserve_migrator_admin") {
        locallyActive = false;
    }

    function rescue(address token_) external onlyRole("reserve_migrator_admin") {
        ERC20 token = ERC20(token_);
        token.transfer(address(TRSRY), token.balanceOf(address(this)));
    }
}
