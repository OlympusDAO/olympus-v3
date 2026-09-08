// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test actions assert their effects directly; return values are intentionally unused.
// forge-lint: disable-start(unused-return)

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockYieldRepurchaseRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRepurchaseRecipient.sol";

abstract contract BurnerLoansClaimYieldTestBase is BurnerLoansTest {
    uint128 internal constant _COLLATERAL_AMOUNT = 100e6;

    MockERC20 internal vaultAsset;
    MockERC4626 internal vault;
    MockERC4626 internal mockYieldVault;

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

    /// @notice Creates claimable yield for a direct-custody asset through an over-repayment.
    function _addDirectCustodyYield(uint256 claimableYield_) internal {
        uint256 repaymentAmount = claimableYield_ + 1;
        usds.mint(alice, repaymentAmount);
        vm.prank(alice);
        usds.approve(address(depositManager), repaymentAmount);

        vm.prank(address(burnerLoans));
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: IERC20(address(usds)),
                payer: alice,
                amount: repaymentAmount,
                maxAmount: 0
            })
        );
    }

    /// @notice Replaces the mock's direct USDS custody with a vault-backed route for YRF tests.
    function _useMockVaultDepositManager() internal {
        _useMockDepositManager();
        mockYieldVault = new MockERC4626(usds, "Mock Yield Vault", "myvUSDS");
        mockDepositManager.addAsset(
            IERC20(address(usds)),
            IERC4626(address(mockYieldVault)),
            type(uint256).max,
            0
        );
    }

    /// @notice Burns vault assets to simulate a custody shortfall.
    function _causeShortfall(uint256 amount_) internal {
        vaultAsset.burn(address(vault), amount_);
    }

    /// @notice Deploys and configures one test yield repurchase recipient route.
    function _configureYieldRouting(
        address asset_,
        address vault_,
        uint16 bps_
    ) internal returns (MockYieldRepurchaseRecipient recipient) {
        vm.startPrank(admin);
        recipient = new MockYieldRepurchaseRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(vault_, asset_, true);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(recipient));
        burnerLoansConfig.setYieldAssetRouting(asset_, _repurchaseRouting(bps_));
        vm.stopPrank();
    }

    /// @notice Returns a Treasury/repurchase-only route.
    function _repurchaseRouting(
        uint16 repurchaseBps_
    ) internal pure returns (IBurnerLoans.AssetYieldRouting memory routing) {
        routing.repurchaseRecipientBps = repurchaseBps_;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](0);
    }

    /// @notice Returns a route with the supplied ordered direct allocations and Treasury remainder.
    function _directRouting(
        address[] memory recipients_,
        uint16[] memory bps_
    ) internal pure returns (IBurnerLoans.AssetYieldRouting memory routing) {
        uint256 count = recipients_.length;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](count);
        for (uint256 i; i < count; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: recipients_[i],
                bps: bps_[i]
            });
        }
    }

    /// @notice Stores one route through the authorized Config policy.
    function _setYieldAssetRouting(
        address asset_,
        IBurnerLoans.AssetYieldRouting memory routing_
    ) internal {
        vm.prank(admin);
        burnerLoansConfig.setYieldAssetRouting(asset_, routing_);
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

// forge-lint: disable-end(unused-return)
