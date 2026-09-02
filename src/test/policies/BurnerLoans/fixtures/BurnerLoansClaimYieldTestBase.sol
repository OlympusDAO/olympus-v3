// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Actions} from "src/Kernel.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockYieldRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRecipient.sol";

abstract contract BurnerLoansClaimYieldTestBase is BurnerLoansTest {
    uint128 internal constant _COLLATERAL_AMOUNT = 100e6;

    MockERC20 internal vaultAsset;
    MockERC4626 internal vault;

    function setUp() public virtual override {
        super.setUp();
        _setDefaultGlobalDebtCap();
        _configureClaimAsset();
    }

    /// @notice Adds a vault-backed asset used by claim tests.
    function _configureClaimAsset() internal {
        (vaultAsset, vault) = _addVaultAssetForTest();
    }

    /// @notice Deposits the fixture collateral amount for Alice.
    function _depositCollateral() internal {
        vaultAsset.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        vaultAsset.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(vaultAsset), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
    }

    /// @notice Mints vault assets to simulate earned yield.
    function _addYield(uint256 amount_) internal {
        vaultAsset.mint(address(vault), amount_);
    }

    /// @notice Burns vault assets to simulate a custody shortfall.
    function _causeShortfall(uint256 amount_) internal {
        vaultAsset.burn(address(vault), amount_);
    }

    /// @notice Deploys and configures one test yield recipient route.
    function _configureYieldRouting(
        address asset_,
        address vault_,
        uint16 bps_
    ) internal returns (MockYieldRecipient recipient) {
        vm.startPrank(admin);
        recipient = new MockYieldRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(vault_, asset_, true);
        burnerLoansConfig.setYieldRecipient(address(recipient));
        burnerLoansConfig.setYieldRecipientAssetBps(asset_, bps_);
        vm.stopPrank();
    }

    /// @notice Asserts every borrower position field is unchanged.
    function _assertPositionEq(
        IBurnerLoans.Position memory actual_,
        IBurnerLoans.Position memory expected_
    ) internal pure {
        assertEq(actual_.depositedCollateral, expected_.depositedCollateral, "collateral");
        assertEq(actual_.debtOhm, expected_.debtOhm, "debt");
        assertEq(actual_.maturity, expected_.maturity, "maturity");
        assertEq(actual_.lastBorrowBlock, expected_.lastBorrowBlock, "last borrow block");
    }
}
