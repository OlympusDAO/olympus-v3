// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {BurnerLoansBorrowTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansBorrowTestBase.sol";

abstract contract BurnerLoansCompositesTest is BurnerLoansBorrowTestBase {
    bytes32 internal constant _AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );

    uint128 internal constant _COLLATERAL = 2_000e6;
    uint128 internal constant _BORROW = 100e9;
    uint256 internal constant _MAX_FEE = 10e6;

    BurnerLoansComposites internal composites;
    address internal recipient;

    function setUp() public virtual override {
        super.setUp();
        composites = new BurnerLoansComposites(address(burnerLoans), address(ohm));
        recipient = makeAddr("recipient");
    }

    function _emptyAuthorization()
        internal
        pure
        returns (IOperatorAuth.Authorization memory authorization)
    {}

    function _emptySignature() internal pure returns (IOperatorAuth.Signature memory signature) {}

    function _authorize(address account_) internal {
        vm.prank(account_);
        burnerLoans.setAuthorization(address(composites), uint48(block.timestamp + 1 days));
    }

    function _signedAuthorization(
        address account_,
        uint256 privateKey_
    )
        internal
        view
        returns (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        )
    {
        authorization = IOperatorAuth.Authorization({
            account: account_,
            authorized: address(composites),
            authorizationDeadline: uint48(block.timestamp + 1 days),
            nonce: burnerLoans.authorizationNonces(account_),
            signatureDeadline: uint48(block.timestamp + 1 hours)
        });
        bytes32 structHash = keccak256(abi.encode(_AUTHORIZATION_TYPEHASH, authorization));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", burnerLoans.DOMAIN_SEPARATOR(), structHash)
        );
        (signature.v, signature.r, signature.s) = vm.sign(privateKey_, digest);
    }

    function _depositParams(
        address asset_,
        address recipient_
    ) internal pure returns (IBurnerLoansComposites.DepositAndBorrowParams memory) {
        return
            IBurnerLoansComposites.DepositAndBorrowParams({
                asset: asset_,
                collateralAmount: _COLLATERAL,
                ohmAmount: _BORROW,
                recipient: recipient_,
                maxFee: _MAX_FEE
            });
    }

    function _fundAndApproveCollateral(address asset_, address account_, uint256 amount_) internal {
        deal(asset_, account_, amount_);
        vm.prank(account_);
        IBurnerLoansCompositesToken(asset_).approve(address(composites), amount_);
    }

    function _openPosition()
        internal
        returns (IBurnerLoansComposites.DepositAndBorrowResult memory)
    {
        _authorize(alice);
        _fundAndApproveCollateral(address(usds), alice, _COLLATERAL + _MAX_FEE);
        vm.prank(alice);
        IBurnerLoansComposites.DepositAndBorrowResult memory result = composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(usds), alice)
        );
        vm.roll(block.number + 1);
        return result;
    }

    function _assertCompositeBalances(address collateralAsset_) internal view {
        assertEq(
            IBurnerLoansCompositesToken(collateralAsset_).balanceOf(address(composites)),
            0,
            "composite collateral"
        );
        assertEq(ohm.balanceOf(address(composites)), 0, "composite OHM");
    }
}

interface IBurnerLoansCompositesToken {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}
