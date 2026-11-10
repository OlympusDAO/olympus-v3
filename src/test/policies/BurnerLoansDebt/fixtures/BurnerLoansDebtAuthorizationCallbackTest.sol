// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {toKeycode} from "src/Kernel.sol";

// Contracts
import {BurnerLoansDebtTest} from "../BurnerLoansDebtTest.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

/// @dev A token owns the position so its real transfer callback can cancel/replace its own grant.
abstract contract BurnerLoansDebtAuthorizationCallbackTest is BurnerLoansDebtTest {
    function _prepareAuthorizationCallback(
        bool delivery_,
        bool extension_,
        bool replacement_
    ) internal returns (ReentrantFeeToken token) {
        if (delivery_) {
            // Preserve OHM's existing identity and ERC20 balances while adding its transfer hook.
            ReentrantFeeToken template = new ReentrantFeeToken();
            vm.etch(address(_ohm), address(template).code);
            token = ReentrantFeeToken(address(_ohm));
        } else {
            token = new ReentrantFeeToken();
            _asset = token;
            _price.setPrice(address(token), 1e18);
            _admit(address(token));
        }
        _borrower = address(token);
        // Asset units are 6 decimals for the original collateral, 18 for the fee-token fixture.
        uint128 collateral = delivery_ ? 2000e6 : 2000e18;
        vm.prank(_borrower);
        _asset.approve(address(_core), type(uint256).max);
        _depositCollateral(collateral);
        _mockRisk(0);
        if (extension_) {
            vm.prank(_borrower);
            _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        }
        _authorizeOperator(_recipient, type(uint48).max);
        if (!delivery_) {
            _mockRisk(7);
            _asset.mint(_recipient, 7);
            vm.prank(_recipient);
            _asset.approve(address(_core), 7);
        }
        bytes memory callback;
        if (replacement_) {
            // Identical permissions at the newly expected pair epoch must not replace the captured stamp.
            IOperatorAuth.Grant memory next = _operatorGrant(
                _borrower,
                _recipient,
                type(uint48).max
            );
            callback = abi.encodeCall(_auth.approveGrant, (next));
        } else {
            callback = abi.encodeCall(_auth.cancelGrant, (_recipient));
        }
        token.setCallbackFrom(
            delivery_ ? address(_inventory) : address(_core),
            address(_auth),
            callback
        );
        token.setCallbackPhases(delivery_, !delivery_);
        token.setBubbleCallbackFailure(true);
    }

    /// @dev Includes the funding source and complete permission payload, beyond position balances.
    function _authorizationRollbackDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _stateDigest(_recipient),
                    _inventory.suppliedIdleOhm(),
                    MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR")))).mintApproval(
                        address(_inventory)
                    ),
                    _auth.getGrant(_borrower, _recipient)
                )
            );
    }

    function _assertCallbackRollback(
        ReentrantFeeToken token_,
        bytes32 before_,
        uint256 epoch_
    ) internal view {
        assertEq(
            _authorizationRollbackDigest(),
            before_,
            "Stale authority restores FLOAN, funding, fee custody, balances and allowances"
        );
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            epoch_,
            "Callback cancellation/replacement rolls back with settlement"
        );
        assertTrue(
            token_.callbackEnabled(),
            "Callback execution state rolls back with token transfer"
        );
    }
}
// forge-lint: disable-end(unused-return)
