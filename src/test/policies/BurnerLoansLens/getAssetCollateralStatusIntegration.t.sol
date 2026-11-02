// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries

// Contracts
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensGetAssetCollateralStatusIntegrationTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-COLLATERAL-STATUS-P08.
    function test_givenRealDirectCustody_whenStatusRead(address caller_) public {
        _asset.mint(address(_core), 102);
        vm.startPrank(address(_core));
        _asset.approve(address(_depositManager), type(uint256).max);
        _depositManager.deposit(
            IDepositManager.DepositParams(IERC20(address(_asset)), 1, address(_core), 100, false)
        );
        _depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams(IERC20(address(_asset)), address(_core), 1)
        );
        _depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams(IERC20(address(_asset)), address(_core), 3, 1)
        );
        vm.stopPrank();
        vm.prank(caller_);
        IBurnerLoansCore.AssetCollateralStatus memory s = _lens.getAssetCollateralStatus(
            address(_asset)
        );
        assertEq(s.shares, 102, "Direct custody raw shares");
        assertEq(s.assets, 102, "Direct custody assets");
        assertEq(s.borrowed, 0, "Temporary borrowing settled");
        assertEq(s.liabilities, 100, "Original receipts retained");
        assertTrue(s.solvent, "Surplus is solvent");
        assertEq(s.claimableYield, 1, "Two units surplus retain one-unit yield buffer");
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P09.
    function test_givenRealVaultDonation_whenStatusRead(address caller_) public {
        MockERC20 token = new MockERC20("Vault asset", "V", 6);
        MockERC4626 vault = new MockERC4626(OZIERC20(address(token)), "Vault", "SV");
        _depositManager.addAsset(
            IERC20(address(token)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        _depositManager.addAssetPeriod(IERC20(address(token)), 1, address(_core));
        _price.setPrice(address(token), 1e18);
        _config.addAsset(
            address(token),
            100_000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12_500, 100, 30 days, 90 days, 1000e6),
            IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900),
            false
        );
        token.mint(address(_core), 3);
        vm.startPrank(address(_core));
        token.approve(address(_depositManager), 3);
        _depositManager.deposit(
            IDepositManager.DepositParams(IERC20(address(token)), 1, address(_core), 3, false)
        );
        vm.stopPrank();
        token.mint(address(vault), 1);
        vm.prank(caller_);
        IBurnerLoansCore.AssetCollateralStatus memory s = _lens.getAssetCollateralStatus(
            address(token)
        );
        assertEq(s.shares, 3, "Vault shares remain three");
        assertEq(s.assets, 4, "Donation converts three shares to four assets");
        assertEq(s.borrowed, 0, "No borrowing");
        assertEq(s.liabilities, 3, "Receipts retain principal");
        assertTrue(s.solvent, "Donation is solvent");
        assertEq(s.claimableYield, 0, "One-unit surplus retains buffer");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
