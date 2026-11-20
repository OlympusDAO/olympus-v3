// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";

contract MockERC20BalanceQueryFailure is ERC20Mock {
    enum Failure {
        None,
        Revert,
        EmptyData,
        ShortData
    }

    error BalanceQueryFailed(address account);
    error InvalidAccount();

    address internal _failureAccount;
    uint256 internal _failureBalance;
    Failure internal _failure;

    function setBalanceQueryFailure(address account_, uint256 balance_, Failure failure_) external {
        if (account_ == address(0)) revert InvalidAccount();
        _failureAccount = account_;
        _failureBalance = balance_;
        _failure = failure_;
    }

    function balanceOf(address account_) public view override returns (uint256) {
        uint256 balance = super.balanceOf(account_);
        if (account_ != _failureAccount || balance != _failureBalance) return balance;

        if (_failure == Failure.Revert) revert BalanceQueryFailed(account_);
        if (_failure == Failure.EmptyData) {
            // forge-lint: disable-next-line(inline-assembly)
            assembly {
                return(0, 0)
            }
        }
        if (_failure == Failure.ShortData) {
            // forge-lint: disable-next-line(inline-assembly)
            assembly {
                mstore(0, 1)
                return(31, 1)
            }
        }
        return balance;
    }
}
