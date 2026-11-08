// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansDebtPriceCallbackTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtPriceCallbackTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtBorrowPriceCallbacksTest is BurnerLoansDebtPriceCallbackTest {
    // Scenarios: BLDEBT-BORROW-C05.
    function test_givenCacheBorrows_whenGlobalRoomConsumed_thenOuterRechecksAndRollsBack(
        uint128 nested_,
        uint128 outer_,
        uint128 room_
    ) public {
        nested_ = uint128(bound(nested_, 1, 800e9));
        outer_ = uint128(bound(outer_, 1, 800e9));
        room_ = uint128(bound(room_, 0, uint256(outer_) - 1));

        _inventory.setGlobalDebtCap(nested_ + room_);
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), nested_, _borrower, address(_cache), uint256(0), address(0))
            ),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                uint256(outer_),
                uint256(room_)
            )
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), outer_, _borrower, _borrower, 0, address(0));
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "Nested funding rolls back with outer cap failure"
        );
        assertEq(_ohm.balanceOf(address(_cache)), 0, "No nested principal escapes");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            0,
            "Nested debt rolls back"
        );
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-C06.
    function test_givenCacheBorrows_whenAssetRoomConsumed_thenOuterRechecksAndRollsBack(
        uint128 nested_,
        uint128 outer_,
        uint128 room_
    ) public {
        nested_ = uint128(bound(nested_, 1, 800e9));
        outer_ = uint128(bound(outer_, 1, 800e9));
        room_ = uint128(bound(room_, 0, uint256(outer_) - 1));

        _config.setAssetDebtCap(address(_asset), nested_ + room_);
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), nested_, _borrower, address(_cache), uint256(0), address(0))
            ),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_AssetDebtCapExceeded.selector,
                address(_asset),
                uint256(outer_),
                uint256(room_)
            )
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), outer_, _borrower, _borrower, 0, address(0));
        assertEq(_inventory.activePrincipalOhm(), 0, "Nested asset exposure rolls back");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-C07.
    function test_givenCacheBorrows_whenRoomRemains_thenBothSettlementsUseLiveDebt(
        uint128 nested_,
        uint128 outer_
    ) public {
        nested_ = uint128(bound(nested_, 1, 800e9));
        outer_ = uint128(bound(outer_, 1, 800e9));

        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), nested_, _borrower, address(_cache), uint256(0), address(0))
            ),
            true
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            outer_,
            _borrower,
            _borrower,
            0,
            address(0)
        );
        assertEq(
            result.resultingDebtOhm,
            uint256(nested_) + outer_,
            "Outer uses refreshed principal"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            uint256(nested_) + outer_,
            "Both funding draws reconciled"
        );
        assertEq(_ohm.balanceOf(address(_cache)), nested_, "Nested funding once");
        assertEq(_ohm.balanceOf(_borrower), outer_, "Outer funding once");
        assertEq(
            result.maturity,
            block.timestamp + 30 days,
            "Outer top-up preserves nested episode maturity"
        );
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            uint256(nested_) + outer_,
            "No stale overwrite in canonical market principal"
        );
    }

    // Scenarios: BLDEBT-BORROW-C03.
    function test_givenUnauthorizedCacheAction_whenCaught_thenOuterSucceeds() public {
        vm.prank(_borrower);
        _core.cancelAuthorization(address(_cache));
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, address(_cache), uint256(0), address(0))
            ),
            false
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        assertEq(
            _cache.rejection(),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            "Exact caught auth failure, not a Core guard"
        );
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Only outer funding");
    }

    // Scenarios: BLDEBT-BORROW-C04.
    function test_givenUnauthorizedCacheAction_whenPropagated_thenOuterRollsBack() public {
        vm.prank(_borrower);
        _core.cancelAuthorization(address(_cache));
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, address(_cache), uint256(0), address(0))
            ),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        assertEq(_inventory.activePrincipalOhm(), 0, "No funding after refresh callback failure");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast, unused-return)
