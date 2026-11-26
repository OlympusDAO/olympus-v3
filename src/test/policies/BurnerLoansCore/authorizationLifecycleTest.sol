// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";

abstract contract BurnerLoansAuthorizationIntegrationTest is BurnerLoansCoreTest {
    function _boundedGrant(
        uint8 actions_,
        uint128 maxCollateral_,
        uint128 maxDebt_,
        uint128 minCollateral_,
        uint48 maxMaturity_
    ) internal view returns (IOperatorAuth.Grant memory grant) {
        grant = _operatorGrant(_borrower, _recipient, type(uint48).max);
        grant.actions = actions_;
        grant.permissions = abi.encode(
            IBurnerLoansAuth.Permissions({
                depositAsset: address(_asset),
                maxCollateral: maxCollateral_,
                borrowAsset: address(_asset),
                borrowRecipient: _recipient,
                maxDebt: maxDebt_,
                withdrawAsset: address(_asset),
                withdrawRecipient: _recipient,
                minCollateral: minCollateral_,
                extendAsset: address(_asset),
                maxMaturity: maxMaturity_
            })
        );
    }

    function _acceptBounded(IOperatorAuth.Grant memory grant_) internal {
        vm.prank(_borrower);
        _auth.approveGrant(grant_);
    }

    function _delegatedContext(
        uint8 action_
    ) internal view returns (IBurnerLoansCore.AuthorizationContext memory original) {
        (original.auth, original.globalAuthEpoch) = _core.authConfig();
        original.grantContext = _auth.captureAuthorization(_borrower, _recipient, action_);
    }

    function _fundOperator(uint128 amount_) internal {
        _asset.mint(_recipient, amount_);
        vm.prank(_recipient);
        _asset.approve(address(_core), type(uint256).max);
    }
}
// forge-lint: disable-end(unused-return)
