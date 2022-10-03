// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "src/Kernel.sol";

abstract contract TRSRYv1 is Module {
    // ERRORS
    error TRSRY_NotApproved();
    error TRSRY_NoDebtOutstanding();

    // EVENTS
    event IncreaseWithdrawerApproval(
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 newAmount_
    );
    event DecreaseWithdrawerApproval(
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 newAmount_
    );
    event Withdrawal(
        address indexed policy_,
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 amount_
    );
    event IncreaseDebtorApproval(address indexed debtor_, ERC20 indexed token_, uint256 newAmount_);
    event DecreaseDebtorApproval(address indexed debtor_, ERC20 indexed token_, uint256 newAmount_);
    event DebtIncurred(ERC20 indexed token_, address indexed policy_, uint256 amount_);
    event DebtRepaid(ERC20 indexed token_, address indexed policy_, uint256 amount_);
    event DebtSet(ERC20 indexed token_, address indexed policy_, uint256 amount_);

    // STATE

    /// @notice Mapping of who is approved for withdrawal.
    /// @dev    withdrawer -> token -> amount. Infinite approval is max(uint256).
    mapping(address => mapping(ERC20 => uint256)) public withdrawApproval;

    /// @notice Mapping of who is approved to incur debt.
    /// @dev    debtor -> token -> amount. Infinite approval is max(uint256).
    mapping(address => mapping(ERC20 => uint256)) public debtApproval;

    /// @notice Total debt for token across all withdrawals.
    mapping(ERC20 => uint256) public totalDebt;

    /// @notice Debt for particular token and debtor address
    mapping(ERC20 => mapping(address => uint256)) public reserveDebt;

    // FUNCTIONS
    function getReserveBalance(ERC20 token_) external view returns (uint256);

    function increaseWithdrawerApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external;

    function decreaseWithdrawerApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external;

    function withdrawReserves(
        address to_,
        ERC20 token_,
        uint256 amount_
    ) external;

    function increaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external;

    function decreaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external;

    function incurDebt(ERC20 token_, uint256 amount_) external;

    function repayDebt(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external;

    function setDebt(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external;
}
