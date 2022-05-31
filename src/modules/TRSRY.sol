// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS

import "test-utils/convert.sol";
import "solmate/utils/SafeTransferLib.sol";

/// LOCAL

import "../Kernel.sol";

/// INTERFACES

interface WETH {
    function deposit() external payable;
}

// CONST

address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

/// @title TSY - OlympusTreasury
/// @notice Treasury holds reserves, LP tokens and all other assets under the control
/// of the protocol. Any contracts that need access to treasury assets should
/// be whitelisted by governance.
// TODO should only allow approved amounts for a policy?
contract TreasuryModule is Module {
    using SafeTransferLib for ERC20;
    using convert for *;

    // ######################## ~ VARS ~ ########################

    address immutable self;

    // token - contract - approved amount
    mapping(address => mapping(address => uint256)) public approvals;

    // token - debt
    mapping(address => uint256) public debt;

    // ######################## ~ EVENTS + ERRORS ~ ########################

    event DebtIncreased(address token, uint256 delta);

    event DebtReduced(address token, uint256 delta);

    event ActionApprovalRevoked(address action, address token, uint256 delta);

    event ActionApprovedForWithdrawal(
        address action,
        address token,
        uint256 delta
    );

    // ######################## ~ CONSTRUCTOR ~ ########################

    constructor(address kernel_) Module(Kernel(kernel_)) {
        self = address(this);
    }

    function KEYCODE() public pure override returns (bytes5) {
        return "TRSRY";
    }

    receive() external payable {
        WETH(WETH_ADDRESS).deposit{value: msg.value}();
    }

    /// @dev make treasury policy also be able to note debt for some contracts
    /// assumption is that caller is not malicious (onlyPermitted), modifier in changeDebt
    function loanReserves(
        address recipient,
        address token,
        uint256 amount
    ) external {
        changeDebt(token, amount, true);
        ERC20(token).safeTransfer(recipient, amount);
    }

    /// @dev modifier in changeDebt
    function repayReserves(
        address debtor,
        address token,
        uint256 amount
    ) external {
        ERC20(token).safeTransferFrom(debtor, self, amount);
        changeDebt(token, amount, false);
    }

    function withdrawReserves(
        address recipient,
        address token,
        uint256 amount
    ) external onlyPermitted {
        ERC20(token).safeTransfer(recipient, amount);
    }

    function getReserveBalance(address token) external view returns (uint256) {
        return ERC20(token).balanceOf(self) + debt[token];
    }

    function changeDebt(
        address token,
        uint256 delta,
        bool increase
    ) public onlyPermitted {
        if (increase) {
            debt[token] += delta;
            emit DebtIncreased(token, delta);
        } else {
            debt[token] -= delta;
            emit DebtReduced(token, delta);
        }
    }

    /// @dev debt is not accounted for since should execute in one go
    /// otherwise changeDebt
    function changeApproval(
        address action,
        address token,
        uint256 delta,
        bool increase
    ) public onlyPermitted {
        if (increase) {
            approvals[token][action] += delta;

            emit ActionApprovedForWithdrawal(action, token, delta);
        } else {
            approvals[token][action] -= delta;
            emit ActionApprovalRevoked(action, token, delta);
        }
    }
}
