// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";
import {BurnerLoansPriceCacheTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansPriceCacheTest.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

/// @dev Adversarial cache replacement, not production PriceCache functionality.
/// The parent fixture separately selects the mock as admin and grants it borrower operator authority.
abstract contract BurnerLoansDebtPriceCallbackTest is
    BurnerLoansDebtTest,
    BurnerLoansPriceCacheTest
{
    function setUp() public override(BurnerLoansModularTest, BurnerLoansPriceCacheTest) {
        BurnerLoansPriceCacheTest.setUp();
    }

    function _prepareDebtAndCacheRepayer() internal {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0);
        vm.roll(block.number + 1);
        _ohm.mint(address(_cache), 100e9);
        vm.prank(address(_cache));
        _ohm.approve(address(_core), 100e9);
        vm.prank(_borrower);
        _ohm.approve(address(_core), 100e9);
    }

    function _armUnauthorizedBorrow(bool propagate_) internal {
        vm.prank(_borrower);
        _core.cancelAuthorization(address(_cache));
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, address(_cache), uint256(0))
            ),
            propagate_
        );
    }

    function _priceStateDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _stateDigest(address(_cache)),
                    _cache.rejection(),
                    _cache.getCachedPrice(address(_ohm), address(_asset)),
                    _cache.getCachedPrice(address(_asset), address(_ohm))
                )
            );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
