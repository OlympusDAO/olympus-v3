// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

contract Burner is Policy, RolesConsumer {
    using TransferHelper for ERC20;

    // ========= STATE ========= //

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;

    // Olympus contract dependencies
    ERC20 public immutable ohm; // OHM Token

    // ========= POLICY SETUP ========= //

    constructor(Kernel kernel_, ERC20 ohm_) Policy(kernel_) {
        ohm = ohm_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ohm.safeApprove(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        requests = new Permissions[](4);
        requests[0] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
    }

    // ========= BURN FUNCTIONS ========= //

    /// @notice Burn OHM from the treasury
    /// @param amount_ Amount of OHM to burn
    function burnFromTreasury(uint256 amount_) external onlyRole("burner_admin") {
        // Withdraw OHM from the treasury
        TRSRY.increaseWithdrawApproval(address(this), ohm, amount_);
        TRSRY.withdrawReserves(address(this), ohm, amount_);

        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);
    }

    /// @notice Burn OHM from an address
    /// @param from_ Address to burn OHM from
    /// @param amount_ Amount of OHM to burn
    /// @dev Burning OHM from an address requires it to have approved the MINTR for their OHM.
    ///      Here, we transfer from the user and burn from this address to avoid approving a
    ///      a different contract.
    function burnFrom(address from_, uint256 amount_) external onlyRole("burner_admin") {
        // Transfer OHM from the user to this contract
        ohm.safeTransferFrom(from_, address(this), amount_);

        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);
    }

    /// @notice Burn OHM in this contract
    /// @param amount_ Amount of OHM to burn
    function burn(uint256 amount_) external onlyRole("burner_admin") {
        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);
    }
}
