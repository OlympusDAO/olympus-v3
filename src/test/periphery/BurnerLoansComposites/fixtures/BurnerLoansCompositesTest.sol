// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {signCompositesGrant} from "./SignCompositesGrant.sol";

// Contracts
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {MockCompositesFlashLender} from "./MockCompositesFlashLender.sol";
import {MockCompositesMigrator} from "./MockCompositesMigrator.sol";
import {MockCompositesSwapAdapter} from "./MockCompositesSwapAdapter.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract BurnerLoansCompositesTest is BurnerLoansModularTest {
    BurnerLoansComposites internal _executor;
    IExecutor.Integrations internal _integrationConfig;
    uint256 internal constant _SIGNER_KEY = 0xA11CE;

    function setUp() public virtual override {
        super.setUp();
        _integrationConfig = _integrations();
        _executor = new BurnerLoansComposites(
            address(_core),
            address(_collateral),
            address(_debt),
            address(this),
            _integrationConfig
        );
        _executor.enable("");
        vm.prank(_borrower);
        _asset.approve(address(_executor), type(uint256).max);
    }

    function _integrations() internal virtual returns (IExecutor.Integrations memory) {
        return
            IExecutor.Integrations(
                address(new MockCompositesMigrator(_asset, _ohm)),
                address(new MockCompositesSwapAdapter()),
                address(new MockCompositesFlashLender(_asset))
            );
    }

    function _funding(
        address token_,
        uint256 amount_
    ) internal pure returns (IExecutor.Funding[] memory inputs) {
        inputs = new IExecutor.Funding[](1);
        inputs[0] = IExecutor.Funding(token_, amount_);
    }

    function _deposit(uint128 amount_) internal view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Deposit,
                abi.encode(IExecutor.Deposit(address(_asset), amount_))
            );
    }

    function _borrow(
        uint128 amount_,
        uint256 maxFee_,
        address recipient_
    ) internal view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Borrow,
                abi.encode(
                    IExecutor.Borrow(address(_asset), amount_, recipient_, maxFee_, address(0))
                )
            );
    }

    function _repay(uint128 amount_) internal view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Repay,
                abi.encode(IExecutor.Repay(address(_asset), amount_))
            );
    }

    function _convertDaiUsds(
        address tokenIn_,
        address tokenOut_,
        uint256 amount_
    ) internal pure returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.ConvertDaiUsds,
                abi.encode(IExecutor.ConvertDaiUsds(tokenIn_, tokenOut_, amount_, amount_))
            );
    }

    function _single(
        IExecutor.Operation memory operation_
    ) internal pure returns (IExecutor.Operation[] memory operations) {
        operations = new IExecutor.Operation[](1);
        operations[0] = operation_;
    }

    function _position() internal view returns (IBurnerLoansCore.Position memory) {
        return _lens.getPosition(address(_asset), _borrower);
    }

    function _signedGrant(
        IOperatorAuth.Grant memory grant_
    ) internal view returns (IExecutor.SignedGrant memory) {
        return _signedGrantWithKey(grant_, _SIGNER_KEY);
    }

    function _signedGrantWithKey(
        IOperatorAuth.Grant memory grant_,
        uint256 signingKey_
    ) internal view returns (IExecutor.SignedGrant memory) {
        return signCompositesGrant(vm, _auth, grant_, signingKey_);
    }

    modifier givenReusableGrant() {
        _approveOperator(_borrower, address(_executor), type(uint48).max);
        _;
    }
}
