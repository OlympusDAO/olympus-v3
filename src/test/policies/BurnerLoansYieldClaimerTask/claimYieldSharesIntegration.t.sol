// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";

// Contracts
import {YieldClaimerModularTest} from "./fixtures/YieldClaimerModularTest.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

contract BurnerLoansYieldClaimerTaskClaimYieldSharesIntegrationTest is YieldClaimerModularTest {
    // Scenarios: BLYC-CLAIM-YIELD-N01, BLYC-CLAIM-YIELD-P07.
    function test_givenSubShareSurplus_whenClaimedRepeatedly(address caller_) public {
        (MockERC20 token, MockERC4626 vault) = _newVault(true);
        _deposit(address(token), 2);
        token.mint(address(vault), 1);
        for (uint256 i; i < 2; ++i) {
            IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
                address(token)
            );
            assertEq(quote.requestedAssetAmount, 1, "Three held assets minus two liabilities");
            assertEq(quote.amountOut, 0, "floor(1 asset * 2 shares / 3 assets) = 0");
            vm.prank(caller_);
            (address output, uint256 amount) = _claimer.claimYield(address(token));
            assertEq(output, address(vault), "Output uses share identity");
            assertEq(amount, 0, "Sub-share output allowed");
            assertEq(
                vault.balanceOf(address(_depositManager)),
                2,
                "Zero output preserves custody shares"
            );
        }
        token.mint(address(vault), 1);
        // Four assets minus two liabilities = 2 asset request; floor(2*2/4)=1 share.
        IBurnerLoansYieldClaim.ClaimYieldPreview memory later = _claimer.previewClaimYield(
            address(token)
        );
        assertEq(later.amountOut, 1, "Later growth reaches one-share breakpoint");
        vm.prank(caller_);
        (, uint256 paid) = _claimer.claimYield(address(token));
        assertEq(paid, 1, "Exact one-share payment");
        assertEq(vault.balanceOf(_payout.treasury()), 1, "Treasury receives the share once");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            2,
            "Principal remains covered"
        );
        _assertNoPayoutCustody(address(vault));
    }

    // Scenarios: BLYC-CLAIM-YIELD-P03.
    function test_givenExternalShares_whenClaimed(
        address caller_,
        bool feeFlag_,
        bool yieldFlag_,
        bool sameDecimals_
    ) public {
        MockERC20 token = new MockERC20("External share underlying", "U", sameDecimals_ ? 6 : 18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            true,
            true
        );
        _admitVault(address(token), address(vault), true);
        _deposit(address(token), 2000e18);
        token.mint(address(vault), 100e18);
        RevenueDistributor distributor = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        distributor.enable("");
        _payout.setRevenueDistributor(address(distributor));
        _payout.setSendFeesToDistributor(feeFlag_);
        _payout.setSendYieldToDistributor(yieldFlag_);
        address recipient = yieldFlag_ ? address(distributor) : _payout.treasury();
        uint256 otherBefore = _yieldAsset.balanceOf(address(_yieldVault));
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(token)
        );
        // 100e18 surplus * 2000e6 shares / 2100e18 assets = 95,238,095 shares, floor.
        assertEq(quote.amountOut, 95_238_095, "External share amount in six decimals");
        assertEq(quote.tokenOut, vault.share(), "Separate ERC7575 share token");
        assertEq(quote.recipient, recipient, "Yield flag alone selects route");
        vm.prank(caller_);
        (address output, uint256 paid) = _claimer.claimYield(address(token));
        assertEq(output, vault.share(), "External output token forwarded");
        assertEq(paid, 95_238_095, "Actual six-decimal output");
        assertEq(
            IERC20(output).balanceOf(recipient),
            paid,
            "Custody pays live destination directly"
        );
        assertEq(
            token.balanceOf(address(vault)),
            2100e18,
            "Share transfer never redeems underlying"
        );
        assertEq(
            _yieldAsset.balanceOf(address(_yieldVault)),
            otherBefore,
            "Other market unaffected"
        );
        _assertNoPayoutCustody(output);
    }

    // Scenarios: BLYC-CLAIM-YIELD-P03.
    function test_givenUnderlyingOutput_whenYieldRoutingChanges(
        bool feeFlag_,
        bool yieldFlag_
    ) public {
        RevenueDistributor distributor = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        distributor.enable("");
        _payout.setRevenueDistributor(address(distributor));
        _payout.setSendFeesToDistributor(feeFlag_);
        _payout.setSendYieldToDistributor(yieldFlag_);
        _yieldAsset.mint(address(_yieldVault), 3);
        address recipient = yieldFlag_ ? address(distributor) : _payout.treasury();
        uint256 before = _yieldAsset.balanceOf(recipient);
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(_yieldAsset)
        );
        assertEq(quote.recipient, recipient, "Yield uses current route independently of fees");
        (, uint256 amount) = _claimer.claimYield(address(_yieldAsset));
        assertEq(amount, 1, "Fixed rounding regression");
        assertEq(_yieldAsset.balanceOf(recipient) - before, 1, "Exact routed delivery");
    }

    // Scenarios: BLYC-CLAIM-YIELD-I01.
    function test_givenZeroYieldAndUnsupportedMode_whenClaimed_reverts() public {
        MockERC20 token = new MockERC20("Mode collateral", "MC", 18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            false,
            true
        );
        _admitVault(address(token), address(vault), false);
        vault.setCapabilities(false, true, true, true);
        bytes memory reason = abi.encodeWithSelector(
            IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
            address(token),
            address(vault)
        );
        vm.expectRevert(reason);
        _claimer.previewClaimYield(address(token));
        vm.expectRevert(reason);
        _claimer.claimYield(address(token));
    }

    // Scenarios: BLYC-CLAIM-YIELD-P03.
    function test_givenVaultShares_whenYieldRoutingChanges(
        bool feeFlag_,
        bool yieldFlag_,
        address caller_
    ) public {
        (MockERC20 token, MockERC4626 vault) = _newVault(true);
        _deposit(address(token), 2);
        token.mint(address(vault), 2);
        RevenueDistributor distributor = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        distributor.enable("");
        _payout.setRevenueDistributor(address(distributor));
        _payout.setSendFeesToDistributor(feeFlag_);
        _payout.setSendYieldToDistributor(yieldFlag_);
        address recipient = yieldFlag_ ? address(distributor) : _payout.treasury();
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(token)
        );
        assertEq(quote.tokenOut, address(vault), "Vault is its own share token");
        assertEq(quote.amountOut, 1, "floor(2 surplus * 2 shares / 4 assets)=1 share");
        assertEq(quote.recipient, recipient, "Fee flag does not affect yield route");
        vm.prank(caller_);
        (address output, uint256 amount) = _claimer.claimYield(address(token));
        assertEq(output, address(vault), "Six-decimal shares match underlying decimals");
        assertEq(amount, 1, "One share delivered");
        assertEq(vault.balanceOf(recipient), 1, "Exact direct share payment");
        assertEq(token.balanceOf(address(vault)), 4, "Share mode retains underlying");
        _assertNoPayoutCustody(output);
    }

    // Scenarios: BLYC-CLAIM-YIELD-P03.
    function test_givenTreasuryUpgraded_whenClaimed() public {
        address oldTreasury = _payout.treasury();
        OlympusTreasury replacement = new OlympusTreasury(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        _yieldAsset.mint(address(_yieldVault), 3);
        assertEq(
            _claimer.previewClaimYield(address(_yieldAsset)).recipient,
            address(replacement),
            "Preview resolves live Treasury"
        );
        (, uint256 amount) = _claimer.claimYield(address(_yieldAsset));
        assertEq(amount, 1, "Expected fixed output");
        assertEq(
            _yieldAsset.balanceOf(address(replacement)),
            1,
            "Replacement Treasury receives yield"
        );
        assertEq(_yieldAsset.balanceOf(oldTreasury), 0, "Old module gets no yield");
    }
}
