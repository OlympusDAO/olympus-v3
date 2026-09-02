// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansClaimYieldTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansClaimYieldTestBase.sol";
import {MockYieldRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRecipient.sol";

contract BurnerLoansCustodyIntegrationTest is BurnerLoansClaimYieldTestBase {
    // integration
    // given a real DepositManager vault whose withdrawal conversion rounds down
    //  when credited collateral is withdrawn in amounts at and below one vault share
    //   then nonzero actual output is returned and zero-output dust remains credited
    function test_givenVaultWithdrawalRoundsDown_whenWithdrawing() public {
        uint128 depositedAmount = 3;
        vaultAsset.mint(alice, depositedAmount);
        vm.prank(alice);
        vaultAsset.approve(address(burnerLoans), depositedAmount);

        vm.prank(alice);
        burnerLoans.depositCollateral(address(vaultAsset), depositedAmount, alice);
        _addYield(1);

        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        // deposit = 3 assets = 3 shares (raw units)
        // donation = 1 asset, so 3 shares represent 4 assets
        // requested debit = 2 assets -> floor(2 * 3 / 4) = 1 share
        // actual output = floor(1 * 4 / 3) = 1 asset
        uint128 firstRequestedAmount = 2;
        IBurnerLoans.WithdrawPreview memory firstPreview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            firstRequestedAmount,
            alice
        );
        assertEq(firstPreview.returnAmount, 1, "first preview amount");
        assertEq(firstPreview.remainingDepositedCollateral, 1, "first preview remaining");
        assertTrue(firstPreview.executable, "first preview executable");

        vm.prank(alice);
        (, uint256 firstAmountOut, uint256 firstRemaining, ) = burnerLoans.withdrawCollateral(
            address(vaultAsset),
            firstRequestedAmount,
            alice,
            alice
        );
        assertEq(firstAmountOut, firstPreview.returnAmount, "first actual amount");
        assertEq(firstRemaining, firstPreview.remainingDepositedCollateral, "first remaining");
        assertEq(vaultAsset.balanceOf(alice), 1, "recipient balance after first withdrawal");

        // The final one-unit credit is worth less than one vault share. Debiting it would make the
        // borrower give up collateral without receiving an asset, so the withdrawal must revert.
        uint128 finalRequestedAmount = 1;
        IBurnerLoans.WithdrawPreview memory finalPreview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            finalRequestedAmount,
            alice
        );
        assertEq(finalPreview.returnAmount, 0, "final preview amount");
        assertEq(finalPreview.remainingDepositedCollateral, 0, "final preview remaining");
        assertFalse(finalPreview.executable, "final preview executable");

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal.selector);
        burnerLoans.withdrawCollateral(address(vaultAsset), finalRequestedAmount, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            finalRequestedAmount,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            finalRequestedAmount,
            "DepositManager liabilities"
        );
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            finalRequestedAmount,
            "receipt token balance"
        );
        assertEq(vaultAsset.balanceOf(alice), 1, "recipient balance after final withdrawal");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "Burner Loans asset residual");
    }

    // integration
    // given an indebted position with a withdrawal worth less than one vault share
    //  when the same zero-output withdrawal is attempted repeatedly
    //   then every attempt reverts without changing borrower or custody accounting
    function test_givenOutstandingDebt_whenSubShareWithdrawalIsRepeated_reverts() public {
        uint128 depositedAmount = 1_000_000e6;
        uint128 withdrawalAmount = 1e6;
        uint128 debtOhm = 1e9;
        vaultAsset.mint(alice, depositedAmount);
        vm.prank(alice);
        vaultAsset.approve(address(burnerLoans), depositedAmount);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(vaultAsset), depositedAmount, alice);

        vaultAsset.mint(address(vault), uint256(withdrawalAmount) * depositedAmount);
        price.setTimestamp(uint48(block.timestamp));
        _configurePrice(address(ohm), 1e18);
        _configurePrice(address(vaultAsset), 1e18);
        burnerLoans.setPositionForTest(
            address(vaultAsset),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: depositedAmount,
                debtOhm: debtOhm,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: uint48(block.number)
            })
        );

        assertEq(vault.convertToShares(withdrawalAmount), 0, "withdrawal shares");
        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            withdrawalAmount,
            alice
        );
        assertEq(preview.returnAmount, 0, "preview amount");
        assertGt(preview.resultingHealthFactor, 1e18, "preview health");
        assertFalse(preview.executable, "preview executable");

        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 operatorSharesBefore = vault.balanceOf(address(depositManager));

        for (uint256 i; i < 3; ++i) {
            vm.prank(alice);
            vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal.selector);
            burnerLoans.withdrawCollateral(address(vaultAsset), withdrawalAmount, alice, alice);

            IBurnerLoans.Position memory position = burnerLoans.getPosition(
                address(vaultAsset),
                alice
            );
            assertEq(position.depositedCollateral, depositedAmount, "position collateral");
            assertEq(position.debtOhm, debtOhm, "position debt");
            assertEq(
                depositManager.getOperatorLiabilities(
                    IERC20(address(vaultAsset)),
                    address(burnerLoans)
                ),
                depositedAmount,
                "DepositManager liabilities"
            );
            assertEq(
                receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
                depositedAmount,
                "receipt token balance"
            );
            assertEq(vault.totalAssets(), vaultAssetsBefore, "vault assets");
            assertEq(
                vault.balanceOf(address(depositManager)),
                operatorSharesBefore,
                "DepositManager vault shares"
            );
            assertEq(vaultAsset.balanceOf(alice), 0, "recipient balance");
            _assertFloanPositionMatchesBurnerLoans(address(vaultAsset), alice);
        }
    }

    // integration
    // given a real DepositManager vault whose share conversion rounds down
    //  when collateral is deposited
    //   then Burner Loans credits DepositManager's returned amount rather than the transferred amount
    function test_givenVaultRoundsDown_whenDepositing_creditsDepositManagerActualAmount() public {
        uint256 seedAmount = 3;
        vaultAsset.mint(address(this), seedAmount);
        vaultAsset.approve(address(vault), seedAmount);
        vault.deposit(seedAmount, address(this));
        _addYield(1);

        uint128 transferredAmount = 2;
        uint256 quotedAmount = vault.previewRedeem(vault.previewDeposit(transferredAmount));

        // seed = 3 assets -> 3 shares (raw units)
        // donation = 1 asset -> 4 assets backing 3 shares
        // deposit = 2 assets -> floor(2 * 3 / 4) = 1 share
        // credit = floor(1 * 6 / 4) = 1 asset after the deposit
        assertGt(quotedAmount, 0, "quoted collateral credit");
        assertLt(quotedAmount, transferredAmount, "quote demonstrates vault rounding");

        vaultAsset.mint(alice, transferredAmount);
        vm.prank(alice);
        vaultAsset.approve(address(burnerLoans), transferredAmount);
        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        vm.prank(alice);
        (uint256 depositedAmount, uint256 resultingCollateral) = burnerLoans.depositCollateral(
            address(vaultAsset),
            transferredAmount,
            alice
        );

        assertLt(depositedAmount, transferredAmount, "credited less than transferred amount");
        assertEq(depositedAmount, quotedAmount, "DepositManager actual amount");
        assertEq(resultingCollateral, depositedAmount, "returned total collateral");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            depositedAmount,
            "FLOAN position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            depositedAmount,
            "DepositManager liabilities"
        );
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            depositedAmount,
            "receipt token balance"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "Burner Loans asset residual");
    }

    // integration
    // given configuration and receipt identity
    //  when the integration flow is executed
    //   then it matches Burner Loans custody
    function test_configurationAndReceiptIdentity_matchBurnerLoansCustody() public {
        IDepositManager.AssetPeriodStatus memory period = depositManager.isAssetPeriod(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        assertTrue(period.isConfigured, "asset period configured");
        assertTrue(period.isEnabled, "asset period enabled");
        assertEq(depositManager.getOperatorName(address(burnerLoans)), "brn", "operator name");
        assertTrue(
            roles.hasRole(address(burnerLoans), _depositOperatorRole()),
            "deposit operator role"
        );

        _depositCollateral();
        (uint256 receiptTokenId, address wrappedToken) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        assertNotEq(receiptTokenId, 0, "receipt token id");
        assertNotEq(wrappedToken, address(0), "wrapped receipt token");
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            _COLLATERAL_AMOUNT,
            "receipt token balance"
        );
    }

    // integration
    // given real DepositManager vault custody receives borrower principal and earns yield
    //  when yield is claimed and all credited collateral is withdrawn
    //   then accounting reconciles and BurnerLoans retains no underlying or vault shares
    function test_depositClaimWithdraw_reconcilesCustodyWithoutPolicyResiduals() public {
        MockYieldRecipient recipient = _configureYieldRouting(
            address(vaultAsset),
            address(vault),
            7_000
        );
        _depositCollateral();
        IBurnerLoans.AssetCollateralStatus memory depositedStatus = burnerLoans
            .getAssetCollateralStatus(address(vaultAsset));
        assertEq(depositedStatus.liabilities, _COLLATERAL_AMOUNT, "deposit liabilities");
        assertEq(depositedStatus.assets, _COLLATERAL_AMOUNT, "deposit assets");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "deposit asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "deposit vault residual");

        _addYield(10e6);
        uint256 recipientBefore = vaultAsset.balanceOf(address(recipient));
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));
        uint128 activePrincipalBefore = inventory.activePrincipalOhm();
        uint256 capacityBefore = inventory.availableCapacity();
        uint256 inventoryOhmBefore = ohm.balanceOf(address(inventory));
        uint256 mintApprovalBefore = mintr.mintApproval(address(inventory));
        burnerLoans.claimYield();
        uint256 recipientIncrease = vaultAsset.balanceOf(address(recipient)) - recipientBefore;
        uint256 treasuryIncrease = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;
        uint256 claimed = recipientIncrease + treasuryIncrease;
        // A 100e6 deposit plus 10e6 yield loses two native units across the vault share
        // conversion and withdrawal round-downs, so the exact executable claim is 9_999_998.
        assertEq(claimed, 9_999_998, "claimed yield");
        assertEq(recipientIncrease, (claimed * 7_000) / 10_000, "recipient yield");
        assertEq(treasuryIncrease, claimed - recipientIncrease, "treasury yield");
        assertEq(recipientIncrease + treasuryIncrease, claimed, "yield conservation");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "claim asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "claim vault residual");
        assertEq(inventory.activePrincipalOhm(), activePrincipalBefore, "active principal");
        assertEq(inventory.availableCapacity(), capacityBefore, "available capacity");
        assertEq(ohm.balanceOf(address(inventory)), inventoryOhmBefore, "inventory OHM");
        assertEq(mintr.mintApproval(address(inventory)), mintApprovalBefore, "MINTR approval");

        vm.prank(alice);
        (, uint256 withdrawn, uint256 remaining, ) = burnerLoans.withdrawCollateral(
            address(vaultAsset),
            _COLLATERAL_AMOUNT,
            alice,
            alice
        );
        assertGt(withdrawn, 0, "withdrawn assets");
        assertEq(remaining, 0, "remaining collateral");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            0,
            "withdraw liabilities"
        );
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "withdraw asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "withdraw vault residual");
    }

    function test_timelockedRoutingConfiguration_thenClaimsEndToEnd() public {
        vm.startPrank(admin);
        MockYieldRecipient recipient = new MockYieldRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(address(vault), address(vaultAsset), true);
        vm.stopPrank();
        _setDefaultConfigOperator();
        _enableConfigTimelock();

        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setYieldRecipient.selector,
            payload: abi.encode(address(recipient))
        });
        vm.prank(burnerLoansAdmin);
        uint64 recipientActionId = configTimelock.queueBatch(actions);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(recipientActionId);

        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setYieldRecipientAssetBps.selector,
            payload: abi.encode(address(vaultAsset), uint16(6_000))
        });
        vm.prank(burnerLoansAdmin);
        uint64 bpsActionId = configTimelock.queueBatch(actions);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(bpsActionId);

        _depositCollateral();
        _addYield(10e6);
        uint256 recipientBefore = vaultAsset.balanceOf(address(recipient));
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));
        burnerLoans.claimYield();
        uint256 recipientAmount = vaultAsset.balanceOf(address(recipient)) - recipientBefore;
        uint256 treasuryAmount = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;
        uint256 claimed = recipientAmount + treasuryAmount;

        assertGt(claimed, 0, "claimed yield");
        assertEq(recipientAmount, (claimed * 6_000) / 10_000, "recipient yield");
        assertEq(treasuryAmount, claimed - recipientAmount, "treasury yield");
    }

    // integration
    // given deposit manager role failure
    //  when the integration flow is executed
    //   then it rolls back burner loans deposit
    function test_depositManagerRoleFailure_rollsBackBurnerLoansDeposit() public {
        vaultAsset.mint(alice, _COLLATERAL_AMOUNT);
        vm.prank(alice);
        vaultAsset.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        bytes32 depositOperatorRole = _depositOperatorRole();
        vm.prank(admin);
        rolesAdmin.revokeRole(depositOperatorRole, address(burnerLoans));

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, depositOperatorRole)
        );
        vm.prank(alice);
        burnerLoans.depositCollateral(address(vaultAsset), _COLLATERAL_AMOUNT, alice);

        assertEq(vaultAsset.balanceOf(alice), _COLLATERAL_AMOUNT, "caller collateral restored");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            0,
            "operator liabilities"
        );
    }
}
