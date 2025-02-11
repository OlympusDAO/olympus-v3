// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ICoolerTreasuryBorrower} from "policies/interfaces/cooler/ICoolerTreasuryBorrower.sol";

/**
 * @title Cooler Treasury Borrower - USDS borrows, sUSDS at rest
 * @notice Policy which can borrow from Treasury on behalf of Cooler
 *  - Cooler will always represent the debt amount in 18 decimal places.
 *  - This logic is split out into a separate policy (rather than using `TreasuryCustodian`):
 *      1/ So the Cooler debt token can be updated if required in future to another stablecoin without a redeploy of Cooler.
 *      2/ In this case, debt is denominated in USDS but stored 'at rest' in Treasury into sUSDS for extra yield.
 *  - Upon an upgrade, if the actual debt token is changed (with a new deployment of this contract) to a non 18dp asset
 *    eg USDC, then borrow() and repay() will need to do the conversion.
 *  - This implementation borrows USDS from Treasury but deposits into sUSDS to benefit from savings yield.
 */
contract CoolerTreasuryBorrower is ICoolerTreasuryBorrower, Policy, PolicyEnabler {
    using SafeTransferLib for ERC20;

    /// @inheritdoc ICoolerTreasuryBorrower
    uint8 public constant override DECIMALS = 18;

    /// @notice Olympus V3 Treasury Module
    TRSRYv1 public TRSRY;

    /// @notice sUSDS is used within TRSRY to generate yield on idle USDS
    ERC4626 public immutable SUSDS;

    /// @dev The SKY USDS token
    ERC20 private immutable _USDS;

    bytes32 public constant COOLER_ROLE = bytes32("treasuryborrower_cooler");

    constructor(address kernel_, address susds_) Policy(Kernel(kernel_)) {
        SUSDS = ERC4626(susds_);
        _USDS = ERC20(SUSDS.asset());

        // This particular implemenation can only handle an 18dp debtToken
        // If (for example) USDC were to be used then logic should be added
        // within borrow() and repay() to do the conversions.
        if (_USDS.decimals() != DECIMALS) revert InvalidParam();
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));

        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (ROLES_MAJOR != 1 || TRSRY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        requests = new Permissions[](3);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function borrow(
        uint256 amountInWad,
        address recipient
    ) external override onlyEnabled onlyRole(COOLER_ROLE) {
        if (amountInWad == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();

        uint256 outstandingDebt = TRSRY.reserveDebt(_USDS, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: _USDS,
            amount_: outstandingDebt + amountInWad
        });

        // Since TRSRY holds sUSDS, a conversion must be done before funding.
        // Withdraw that sUSDS amount locally and then redeem to USDS sending to the recipient
        uint256 susdsAmount = SUSDS.previewWithdraw(amountInWad);
        TRSRY.increaseWithdrawApproval(address(this), SUSDS, susdsAmount);
        TRSRY.withdrawReserves(address(this), SUSDS, susdsAmount);
        SUSDS.redeem(susdsAmount, recipient, address(this));
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function repay() external override onlyEnabled onlyRole(COOLER_ROLE) {
        uint256 debtTokenAmount = _USDS.balanceOf(address(this));
        if (debtTokenAmount == 0) revert ExpectedNonZero();

        // This policy is allowed to overpay TRSRY, in which case it's debt is set to zero
        // and any future repayments are just deposited. There are no 'credits' for overpaying
        uint256 outstandingDebt = TRSRY.reserveDebt(_USDS, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: _USDS,
            amount_: (outstandingDebt > debtTokenAmount) ? outstandingDebt - debtTokenAmount : 0
        });

        _USDS.safeApprove(address(SUSDS), debtTokenAmount);
        SUSDS.deposit(debtTokenAmount, address(TRSRY));
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function setDebt(uint256 debtTokenAmount) external override onlyEnabled onlyRole(ADMIN_ROLE) {
        TRSRY.setDebt({debtor_: address(this), token_: _USDS, amount_: debtTokenAmount});
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function debtToken() external view override returns (IERC20) {
        return IERC20(address(_USDS));
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function convertToDebtTokenAmount(
        uint256 amountInWad
    ) external view override returns (IERC20 dToken, uint256 dTokenAmount) {
        dToken = IERC20(address(_USDS));
        dTokenAmount = amountInWad;
    }
}
