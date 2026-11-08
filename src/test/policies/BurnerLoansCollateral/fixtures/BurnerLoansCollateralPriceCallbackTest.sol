// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Contracts
import {BurnerLoansPriceCacheTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansPriceCacheTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

abstract contract BurnerLoansCollateralPriceCallbackTest is BurnerLoansPriceCacheTest {
    function _openDebt() internal {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        vm.roll(block.number + 1);
    }

    function _armUnauthorized(bool propagate_) internal {
        vm.prank(_borrower);
        _core.cancelAuthorization(address(_cache));
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, address(_cache), uint256(0), address(0))
            ),
            propagate_
        );
    }

    function _accountingDigest(address asset_) internal view returns (bytes32) {
        uint256 id = _depositManager.getReceiptTokenId(IERC20(asset_), 1, address(_core));
        bytes32 custody = keccak256(
            abi.encode(
                _asset.balanceOf(_borrower),
                _asset.balanceOf(_recipient),
                _asset.balanceOf(address(_core)),
                _asset.balanceOf(address(_depositManager)),
                _asset.balanceOf(address(_cache)),
                _asset.allowance(_borrower, address(_core)),
                _asset.allowance(address(_core), address(_depositManager)),
                _depositManager.getOperatorLiabilities(IERC20(asset_), address(_core)),
                _depositManager.getReceiptTokenManager().balanceOf(address(_core), id)
            )
        );
        return
            keccak256(
                abi.encode(
                    custody,
                    _lens.getPosition(asset_, _borrower),
                    _inventory.activePrincipalOhm(),
                    _floan.getMarketPrincipalDue(_core.marketId(asset_)),
                    _ohm.balanceOf(address(_cache)),
                    _ohm.balanceOf(_borrower),
                    _ohm.balanceOf(address(_core)),
                    _ohm.balanceOf(address(_inventory))
                )
            );
    }

    function _assertDirectCollateral(uint128 expected_) internal view {
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            expected_,
            "Actual final collateral"
        );
        assertEq(_asset.balanceOf(address(_depositManager)), expected_, "Actual direct custody");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            expected_,
            "Actual receipt liability"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
