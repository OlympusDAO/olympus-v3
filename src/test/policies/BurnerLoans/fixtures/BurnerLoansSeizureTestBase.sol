// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BURNER_LOANS_SEIZER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansBorrowTestBase} from "./BurnerLoansBorrowTestBase.sol";

abstract contract BurnerLoansSeizureTestBase is BurnerLoansBorrowTestBase {
    address internal bob;
    address internal keeper;
    address internal protocolSeizer;

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public virtual override {
        super.setUp();
        bob = makeAddr("bob");
        keeper = makeAddr("keeper");
        protocolSeizer = makeAddr("protocolSeizer");

        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, protocolSeizer);

        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 1_000e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(burnerLoans), address(usds), riskConfig);
    }

    function _borrow(address borrower_, uint128 collateral_, uint128 debt_) internal {
        usds.mint(borrower_, collateral_ + 100e18);
        vm.startPrank(borrower_);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), collateral_, borrower_);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            debt_,
            borrower_
        );
        burnerLoans.borrow(address(usds), debt_, borrower_, borrower_, preview.fee);
        vm.stopPrank();
    }

    function _makeUnhealthy(address borrower_) internal {
        _borrow(borrower_, 2_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);
    }

    function _makeMatured(address borrower_) internal {
        _borrow(borrower_, 2_000e18, 100e9);
        vm.warp(block.timestamp + 30 days);
        price.setTimestamp(uint48(block.timestamp));
    }

    function _single(address borrower_) internal pure returns (address[] memory borrowers) {
        borrowers = new address[](1);
        borrowers[0] = borrower_;
    }

    function _pair(
        address first_,
        address second_
    ) internal pure returns (address[] memory borrowers) {
        borrowers = new address[](2);
        borrowers[0] = first_;
        borrowers[1] = second_;
    }
}
