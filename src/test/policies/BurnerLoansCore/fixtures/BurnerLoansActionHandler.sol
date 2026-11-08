// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

/// @dev Independent single-market model with fixed $1 prices, OHM9/asset6 and real Risk.
///      Models successful transfer amounts, never obtains expected accounting from implementation views.
contract BurnerLoansActionHandler is Test {
    BurnerLoansCollateral internal _collateral;
    BurnerLoansDebt internal _debt;
    BurnerLoansSeize internal _seize;
    MockERC20 internal _asset;
    MockERC20 internal _ohm;
    MockPrice internal _price;
    uint128 public collateral;
    uint128 public principal;
    uint256 public deposits;
    uint256 public borrows;
    uint256 public repayments;
    uint256 public withdrawals;
    uint256 public defaults;

    constructor(
        BurnerLoansCollateral collateral_,
        BurnerLoansDebt debt_,
        BurnerLoansSeize seize_,
        MockERC20 asset_,
        MockERC20 ohm_,
        MockPrice price_,
        address core_
    ) {
        _collateral = collateral_;
        _debt = debt_;
        _seize = seize_;
        _asset = asset_;
        _ohm = ohm_;
        _price = price_;
        asset_.approve(core_, type(uint256).max);
        ohm_.approve(core_, type(uint256).max);
    }

    function deposit(uint128 amount_) external {
        amount_ = uint128(bound(amount_, 1, 10000e6));
        _asset.mint(address(this), uint256(amount_) + 100e6);
        _collateral.depositCollateral(address(_asset), amount_, address(this));
        collateral += amount_;
        ++deposits;
    }

    function borrow(uint128 amount_) external {
        // Conservative independent bound: at most 50% collateral value; production requires <=80%.
        uint256 room = uint256(collateral) * 500;
        if (room <= principal || principal >= 100000e9) return;
        room -= principal;
        if (room > 100000e9 - principal) room = 100000e9 - principal;
        amount_ = uint128(bound(amount_, 1, room));
        _asset.mint(address(this), 100000e6);
        _debt.borrow(
            address(_asset),
            amount_,
            address(this),
            address(this),
            type(uint256).max,
            address(0)
        );
        principal += amount_;
        ++borrows;
    }

    function repay(uint128 amount_) external {
        if (principal == 0) return;
        amount_ = uint128(bound(amount_, 1, principal));
        vm.roll(block.number + 1);
        _ohm.mint(address(this), amount_);
        _debt.repay(address(_asset), amount_, address(this));
        principal -= amount_;
        ++repayments;
    }

    function withdraw(uint128 amount_) external {
        // Retain twice the debt value, rounded up, independent of the production health calculator.
        uint256 required = (uint256(principal) + 499) / 500;
        if (collateral <= required) return;
        amount_ = uint128(bound(amount_, 1, uint256(collateral) - required));
        _collateral.withdrawCollateral(address(_asset), amount_, address(this), address(this));
        collateral -= amount_;
        ++withdrawals;
    }

    function seizeExpired() external {
        if (principal == 0) return;
        vm.warp(vm.getBlockTimestamp() + 30 days);
        _price.setTimestamp(uint48(block.timestamp));
        address[] memory borrowers = new address[](1);
        borrowers[0] = address(this);
        _seize.seize(address(_asset), borrowers);
        collateral = 0;
        principal = 0;
        ++defaults;
    }
}
