// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ICoolerTreasuryBorrower} from "policies/interfaces/cooler/ICoolerTreasuryBorrower.sol";

/**
 * @title Cooler Treasury Borrower
 * @notice Policy which can borrow from Treasury on behalf of Cooler
 *  - Cooler will always represent the debt amount in 18 decimal places.
 *  - If the actual debt token is changed (with a new deployment of this contract) to a non 18dp asset
 *    eg USDC, then borrow() and repay() will need to do the conversion.
 */
contract CoolerTreasuryBorrower is ICoolerTreasuryBorrower, Policy {
    using SafeTransferLib for ERC20;

    /// @inheritdoc ICoolerTreasuryBorrower
    address public immutable override cooler;

    /// @inheritdoc ICoolerTreasuryBorrower
    uint8 public constant override DECIMALS = 18;

    /// @notice Olympus V3 Treasury Module
    TRSRYv1 public TRSRY;

    /// @notice sUSDS is used within TRSRY to generate yield on idle USDS
    ERC4626 public immutable susds;

    /// @dev The SKY USDS token
    ERC20 private immutable _usds;

    constructor(
        address kernel_,
        address cooler_,
        address susds_
    ) Policy(Kernel(kernel_)) {
        cooler = cooler_;
        susds = ERC4626(susds_);
        _usds = ERC20(susds.asset());

        // This particular implemenation can only handle an 18dp debtToken
        // If (for example) USDC were to be used then logic should be added
        // within borrow() and repay() to do the conversions.
        if (_usds.decimals() != 18) revert InvalidParam();
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TRSRY");
        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1]);
        if (TRSRY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
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
    function debtToken() external override view returns (ERC20) {
        return _usds;
    }

    /// @dev debtTokenAmount is a USD amount, and always 18dp
    /// @dev If the debtToken is 6dp (eg USDC) then this contract needs to convert it
    /// @inheritdoc ICoolerTreasuryBorrower
    function borrow(uint256 amount, address recipient) external override onlyCooler {
        if (amount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();

        uint256 outstandingDebt = TRSRY.reserveDebt(_usds, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: _usds,
            amount_: outstandingDebt + amount
        });

        // Since TRSRY holds sUSDS, a conversion must be done before funding.
        // Withdraw that sUSDS amount locally and then redeem to USDS sending to the recipient
        uint256 susdsAmount = susds.previewWithdraw(amount);
        TRSRY.increaseWithdrawApproval(address(this), susds, susdsAmount);
        TRSRY.withdrawReserves(address(this), susds, susdsAmount);
        susds.redeem(susdsAmount, recipient, address(this));
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function repay() external override onlyCooler {
        uint256 amount = _usds.balanceOf(address(this));
        if (amount == 0) revert ExpectedNonZero();

        // This policy is allowed to overpay TRSRY, in which case it's debt is set to zero
        // and any future repayments are just deposited. There are no 'credits' for overpaying
        uint256 outstandingDebt = TRSRY.reserveDebt(_usds, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: _usds,
            amount_: (outstandingDebt > amount) ? outstandingDebt - amount : 0
        });

        _usds.safeApprove(address(susds), amount);
        susds.deposit(amount, address(TRSRY));
    }

    modifier onlyCooler() {
        if (msg.sender != cooler) revert OnlyCooler();
        _;
    }
}