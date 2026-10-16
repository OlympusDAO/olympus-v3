// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {Actions} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareToken, MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {BurnerLoansClaimYieldTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansClaimYieldTestBase.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop)

contract BurnerLoansClaimYieldTest is BurnerLoansClaimYieldTestBase {
    error TokenBlacklisted();

    // Scenarios: YLD-T02, YLD-T04
    function test_givenOutputTransferFailure_claimRollsBackEveryCustodyMode(
        uint8 outputMode_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupPositiveYieldMode(outputMode_);
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);
        IBurnerLoans.ClaimYieldPreview memory previewBefore = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        uint256 pendingBefore = burnerLoans.totalPendingForTest(outputToken);
        vm.mockCallRevert(
            outputToken,
            abi.encodeWithSelector(IERC20.transfer.selector, recipient),
            abi.encodeWithSelector(TokenBlacklisted.selector)
        );

        vm.prank(caller_);
        vm.expectRevert(TokenBlacklisted.selector);
        burnerLoans.claimYield(asset);

        IBurnerLoans.ClaimYieldPreview memory previewAfter = burnerLoans.previewClaimYield(asset);
        assertEq(previewAfter.tokenOut, previewBefore.tokenOut, "output token remains claimable");
        assertEq(
            previewAfter.requestedAssetAmount,
            previewBefore.requestedAssetAmount,
            "asset yield remains claimable"
        );
        assertEq(
            previewAfter.amountOut,
            previewBefore.amountOut,
            "output amount remains claimable"
        );
        assertEq(IERC20(outputToken).balanceOf(recipient), recipientBefore, "recipient unchanged");
        assertEq(
            burnerLoans.totalPendingForTest(outputToken),
            pendingBefore,
            "failed direct claim creates no pending payout"
        );
    }

    // Scenarios: YLD-C03, YLD-C04
    function test_givenOutputTokenCallback_claimHandlesEveryCustodyMode(
        uint8 outputMode_,
        bool bubbleFailure_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        (address asset, address outputToken, address callbackInvoker) = _setupCallbackYieldMode(
            outputMode_
        );
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        ReentrantFeeToken implementation = new ReentrantFeeToken();
        vm.etch(outputToken, address(implementation).code);
        ReentrantFeeToken liveToken = ReentrantFeeToken(outputToken);
        liveToken.setCallbackFrom(
            callbackInvoker,
            address(burnerLoans),
            abi.encodeCall(burnerLoans.claimYield, (asset))
        );
        liveToken.setCallbackPhases(true, false);
        liveToken.setCallbackTransferRecipient(recipient);
        liveToken.setBubbleCallbackFailure(bubbleFailure_);

        if (bubbleFailure_) {
            vm.prank(caller_);
            vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
            burnerLoans.claimYield(asset);
            assertEq(
                IERC20(outputToken).balanceOf(recipient),
                recipientBefore,
                "recipient balance rolls back"
            );
            assertEq(
                burnerLoans.previewClaimYield(asset).amountOut,
                preview.amountOut,
                "yield remains claimable"
            );
            assertEq(
                burnerLoans.totalPendingForTest(outputToken),
                0,
                "failed claim creates no pending payout"
            );
            return;
        }

        vm.prank(caller_);
        (, uint256 amountOut) = burnerLoans.claimYield(asset);
        assertFalse(liveToken.callbackSucceeded(), "nested claim is rejected");
        assertEq(
            liveToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "nested claim reaches shared guard"
        );
        assertEq(amountOut, preview.amountOut, "outer claim matches preview");
        assertEq(
            IERC20(outputToken).balanceOf(recipient) - recipientBefore,
            amountOut,
            "recipient paid once"
        );
        assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "no pending payout created");
    }

    // Scenarios: YLD-P02, YLD-L01
    function test_givenDistributorUnavailable_claimRoutesEveryCustodyMode(
        uint8 outputMode_,
        bool kernelInactive_,
        bool originationsDisabled_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupPositiveYieldMode(outputMode_);
        RevenueDistributor distributor = _installYieldDistributorForTest(outputToken);
        if (originationsDisabled_) _setAssetOriginationsEnabled(asset, false);
        if (kernelInactive_) {
            _deactivatePolicy(address(distributor));
        } else {
            vm.prank(admin);
            distributor.disable("");
        }
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(address(distributor));
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            asset,
            preview.requestedAssetAmount,
            outputToken,
            preview.amountOut,
            address(distributor)
        );

        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(asset);

        assertEq(tokenOut, outputToken, "exact output token returned");
        assertEq(amountOut, preview.amountOut, "execution matches preview");
        assertEq(
            IERC20(outputToken).balanceOf(address(distributor)) - recipientBefore,
            preview.amountOut,
            "unavailable distributor receives exact yield"
        );
        assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "no pending payout");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending index");
    }

    // Scenarios: YLD-L02
    function test_givenLocallyDisabled_claimAndPreviewRollbackEveryCustodyMode(
        uint8 outputMode_,
        bool sendYieldToDistributor_,
        bool originationsDisabled_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupPositiveYieldMode(outputMode_);
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);
        if (originationsDisabled_) _setAssetOriginationsEnabled(asset, false);
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 claimableBefore = depositManager.maxClaimYield(IERC20(asset), address(burnerLoans));
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        _disableBurnerLoans(emergency);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewClaimYield(asset);
        vm.prank(caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.claimYield(asset);

        assertGt(preview.amountOut, 0, "fixture has positive output");
        assertEq(
            depositManager.maxClaimYield(IERC20(asset), address(burnerLoans)),
            claimableBefore,
            "claimable yield unchanged"
        );
        assertEq(IERC20(outputToken).balanceOf(recipient), recipientBefore, "recipient unchanged");
        assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "no pending payout");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending index");
    }

    // given sendYieldToDistributor is true
    //   given the underlying token transfer to the distributor reverts
    //     when yield is claimed
    //       [X] the claim reverts and yield remains claimable in DepositManager custody
    // Scenarios: YLD-T04
    function test_givenSendYieldToDistributorIsTrue_whenTokenTransferReverts_revertsAndLeavesYieldClaimable()
        public
    {
        _depositCollateral();
        _addYield(10e6);
        RevenueDistributor distributor = _installYieldDistributorForTest(address(vaultAsset));
        vm.mockCallRevert(
            address(vaultAsset),
            abi.encodeWithSelector(vaultAsset.transfer.selector, address(distributor)),
            abi.encodeWithSelector(TokenBlacklisted.selector)
        );

        uint256 claimableBefore = burnerLoans.previewClaimYield(address(vaultAsset)).amountOut;
        uint256 custodySharesBefore = vault.balanceOf(address(depositManager));
        vm.expectRevert(TokenBlacklisted.selector);
        burnerLoans.claimYield(address(vaultAsset));

        assertEq(
            vault.balanceOf(address(depositManager)),
            custodySharesBefore,
            "custody shares unchanged"
        );
        assertEq(
            burnerLoans.previewClaimYield(address(vaultAsset)).amountOut,
            claimableBefore,
            "yield remains claimable"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "facility holds no yield");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "failed claim creates no payout");
        vm.clearMockedCalls();
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(vaultAsset));
        assertEq(tokenOut, address(vaultAsset), "underlying output token");
        assertEq(amountOut, claimableBefore, "retry claims original yield");
        assertEq(vaultAsset.balanceOf(address(distributor)), amountOut, "retry delivers yield");
    }

    // Vault supply = 100e6 shares and vault assets = 200e18 after the donation.
    // yield shares = 100e18 yield * 100e6 shares / 200e18 assets = 50e6 shares.
    uint256 internal constant _EXPECTED_EXTERNAL_SHARE_YIELD = 50e6;

    // given underlying yield is routed to a disabled distributor
    //   when anyone claims positive yield
    //     [X] it succeeds and deposits the underlying token at the same distributor
    // Scenarios: YLD-P02
    function test_givenDistributorDisabled_givenUnderlyingYield_paysDistributor() public {
        _assertYieldFlowsToUnavailableDistributor(false, false);
    }

    // given underlying yield is routed to a Kernel-inactive distributor
    //   when anyone claims positive yield
    //     [X] it succeeds and deposits the underlying token at the same distributor
    // Scenarios: YLD-L01
    function test_givenDistributorKernelInactive_givenUnderlyingYield_paysDistributor() public {
        _assertYieldFlowsToUnavailableDistributor(false, true);
    }

    // given share yield is routed to a disabled distributor
    //   when anyone claims positive yield
    //     [X] it succeeds and deposits the share token at the same distributor
    // Scenarios: YLD-P02
    function test_givenDistributorDisabled_givenShareYield_paysDistributor() public {
        _assertYieldFlowsToUnavailableDistributor(true, false);
    }

    // given share yield is routed to a Kernel-inactive distributor
    //   when anyone claims positive yield
    //     [X] it succeeds and deposits the share token at the same distributor
    // Scenarios: YLD-L01
    function test_givenDistributorKernelInactive_givenShareYield_paysDistributor() public {
        _assertYieldFlowsToUnavailableDistributor(true, true);
    }

    function _assertYieldFlowsToUnavailableDistributor(
        bool shares_,
        bool kernelInactive_
    ) internal {
        _depositCollateral();
        _addYield(10e6);
        if (shares_) {
            vm.prank(admin);
            burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
            _makeVaultAsynchronous(vault);
        }
        address outputToken = shares_ ? address(vault) : address(vaultAsset);
        RevenueDistributor distributor = _installYieldDistributorForTest(outputToken);
        if (kernelInactive_) {
            _deactivatePolicy(address(distributor));
        } else {
            vm.prank(admin);
            distributor.disable("");
        }

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = IERC20(outputToken).balanceOf(address(trsry));
        vm.prank(alice);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(vaultAsset));

        assertGt(amountOut, 0, "claim produces positive revenue");
        assertEq(tokenOut, outputToken, "claim returns exact output token");
        assertEq(amountOut, preview.amountOut, "claim agrees with previewed output");
        assertEq(
            IERC20(outputToken).balanceOf(address(distributor)),
            amountOut,
            "unavailable distributor receives all yield"
        );
        assertEq(
            IERC20(outputToken).balanceOf(address(trsry)),
            treasuryBefore,
            "Treasury receives no claimed yield"
        );
        assertEq(
            IERC20(outputToken).balanceOf(address(burnerLoans)),
            0,
            "Burner Loans retains no yield"
        );
    }

    // Scenarios: YLD-P03
    function test_givenShareYieldBelowOneShare_whenRepeatedClaims(
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        _depositCollateral();
        _addYield(1);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
        _makeVaultAsynchronous(vault);
        address recipient = _configureYieldRecipientForTest(
            sendYieldToDistributor_,
            address(vault)
        );

        // Raw asset/share units (both 6 decimals): supply = 100e6, assets = 100e6 + 1.
        // Surplus = 1; floor(1 * 100e6 / (100e6 + 1)) = 0 shares.
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        assertEq(preview.requestedAssetAmount, 1, "positive surplus request");
        assertEq(preview.amountOut, 0, "surplus below one share");
        for (uint256 i; i < 3; ++i) {
            vm.expectEmit(true, true, true, true, address(depositManager));
            emit IDepositManagerV1_1.AssetWithdrawn(
                address(vaultAsset),
                recipient,
                address(burnerLoans),
                1,
                address(vault),
                0
            );
            vm.expectEmit(true, true, true, true, address(depositManager));
            emit IDepositManagerV1_1.OperatorYieldClaimed(
                address(vaultAsset),
                recipient,
                address(burnerLoans),
                1,
                address(vault),
                0
            );
            vm.recordLogs();
            vm.prank(caller_);
            (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(vaultAsset));
            assertEq(vm.getRecordedLogs().length, 2, "dust claim event count");
            assertEq(tokenOut, address(vault), "dust output token");
            assertEq(amountOut, 0, "dust output amount");
        }
        assertEq(vault.balanceOf(address(depositManager)), 100e6, "custody shares unchanged");
        assertEq(vault.totalSupply(), 100e6, "no shares burned");
        assertEq(vaultAsset.balanceOf(address(vault)), 100e6 + 1, "vault assets unchanged");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            100e6,
            "liabilities unchanged"
        );
        (uint256 operatorShares, ) = depositManager.getOperatorAssets(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        assertEq(operatorShares, 100e6, "operator shares unchanged");

        // One additional asset unit makes surplus = 2: floor(2 * 100e6 / (100e6 + 2)) = 1 share.
        _addYield(1);
        vm.prank(caller_);
        (, uint256 claimedShares) = burnerLoans.claimYield(address(vaultAsset));
        assertEq(claimedShares, 1, "retained surplus becomes claimable");
        assertEq(vault.balanceOf(recipient), 1, "selected recipient receives retained yield");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "no policy share residual");
    }

    // given sendYieldToDistributor is false
    //   given direct custody contains claimable yield
    //     when yield is claimed
    //       [X] Treasury receives the previewed amount
    function test_givenSendYieldToDistributorIsFalse_givenDirectCustody_paysTreasury() public {
        _addDefaultUsdsAsset();
        _addDirectCustodyYield(101);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(usds)
        );
        (, uint256 actualClaimed) = burnerLoans.claimYield(address(usds));

        assertEq(preview.requestedAssetAmount, 101, "preview amount");
        assertTrue(preview.executable, "preview executable");
        assertEq(actualClaimed, 101, "actual claimed amount");
        assertEq(usds.balanceOf(address(trsry)), 101, "Treasury amount");
        assertEq(
            usds.balanceOf(address(depositManager)),
            2,
            "custody liability plus solvency buffer"
        );
    }

    // given sendYieldToDistributor is false
    //   given Treasury has been upgraded
    //     when yield is claimed
    //       [X] only the new Treasury receives it
    // Scenarios: YLD-S02
    function test_givenSendYieldToDistributorIsFalse_givenTreasuryUpgraded_paysNewTreasury()
        public
    {
        _addDefaultUsdsAsset();
        _addDirectCustodyYield(101);
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(usds)
        );
        (, uint256 amountOut) = burnerLoans.claimYield(address(usds));

        assertEq(preview.recipient, address(newTreasury), "preview selects new Treasury");
        assertEq(amountOut, 101, "claim returns full custody surplus");
        assertEq(usds.balanceOf(address(trsry)), 0, "former Treasury receives no yield");
        assertEq(usds.balanceOf(address(newTreasury)), amountOut, "new Treasury receives yield");
    }

    // given sendYieldToDistributor is true
    //   when yield is claimed
    //     [X] the distributor receives it and Treasury receives nothing
    function test_givenSendYieldToDistributorIsTrue_paysDistributor() public {
        _addDefaultUsdsAsset();
        _addDirectCustodyYield(101);
        RevenueDistributor distributor = _installYieldDistributorForTest(address(usds));
        (, uint256 amountOut) = burnerLoans.claimYield(address(usds));
        assertEq(usds.balanceOf(address(distributor)), amountOut, "distributor holds yield");

        assertEq(amountOut, 101, "claim produces full custody surplus");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury receives no yield");
        assertEq(usds.balanceOf(address(distributor)), amountOut, "distributor receives yield");
    }

    // given sendYieldToDistributor is true
    //   given the output token returns false on transfer to the distributor
    //     when yield is claimed and the distributor is then replaced
    //       [X] the failed claim leaves yield available
    //       [X] a later claim pays only the replacement distributor
    // Scenarios: YLD-S01, YLD-S02
    function test_givenFailedClaim_whenDestinationChanges_freshClaimUsesLiveRecipient(
        uint8 outputMode_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupPositiveYieldMode(outputMode_);
        address formerRecipient = _configureYieldRecipientForTest(
            sendYieldToDistributor_,
            outputToken
        );
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 formerBefore = IERC20(outputToken).balanceOf(formerRecipient);
        vm.mockCallRevert(
            outputToken,
            abi.encodeWithSelector(IERC20.transfer.selector, formerRecipient),
            abi.encodeWithSelector(TokenBlacklisted.selector)
        );

        vm.prank(caller_);
        vm.expectRevert(TokenBlacklisted.selector);
        burnerLoans.claimYield(asset);

        assertEq(
            burnerLoans.previewClaimYield(asset).amountOut,
            preview.amountOut,
            "failed claim leaves full yield claimable"
        );
        assertEq(
            IERC20(outputToken).balanceOf(formerRecipient),
            formerBefore,
            "former recipient receives nothing"
        );
        assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "failed claim creates no debt");
        vm.clearMockedCalls();

        address currentRecipient;
        if (sendYieldToDistributor_) {
            currentRecipient = address(_installRevenueDistributorForTest(outputToken));
        } else {
            vm.prank(admin);
            OlympusTreasury newTreasury = new OlympusTreasury(kernel);
            vm.prank(admin);
            kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
            currentRecipient = address(newTreasury);
        }
        uint256 currentBefore = IERC20(outputToken).balanceOf(currentRecipient);
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            asset,
            preview.requestedAssetAmount,
            outputToken,
            preview.amountOut,
            currentRecipient
        );
        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(asset);

        assertEq(tokenOut, outputToken, "exact output token returned");
        assertEq(amountOut, preview.amountOut, "fresh claim pays full amount");
        assertEq(
            IERC20(outputToken).balanceOf(currentRecipient) - currentBefore,
            amountOut,
            "live recipient receives exact yield"
        );
        assertEq(
            IERC20(outputToken).balanceOf(formerRecipient),
            formerBefore,
            "former recipient remains unpaid"
        );
        assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "no pending payout remains");
    }

    // given sendYieldToDistributor is true
    //   given the output token returns false on transfer to the distributor
    //     when yield is claimed and the distributor is then replaced
    //       [X] the failed claim leaves yield available
    //       [X] a later claim pays only the replacement distributor
    // Scenarios: YLD-S01
    function test_givenSendYieldToDistributorIsTrue_givenTokenTransferFails_whenDistributorChanges_thenClaimPaysNewDistributor()
        public
    {
        _useMockDepositManager();
        RevenueDistributor distributor = _installYieldDistributorForTest(address(usds));
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);
        vm.mockCall(
            address(usds),
            abi.encodeWithSelector(ERC20.transfer.selector, address(distributor), 100),
            abi.encode(false)
        );

        vm.expectRevert(MockDepositManager.MockDepositManager_TransferFailed.selector);
        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(address(distributor)), 0, "distributor receives nothing");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury amount");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility retains no yield");
        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim rolls back");
        assertEq(mockDepositManager.claimableYield(), 100, "yield remains claimable");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "failed claim creates no payout");
        vm.clearMockedCalls();
        RevenueDistributor newDistributor = _installRevenueDistributorForTest(address(usds));
        burnerLoans.claimYield(address(usds));
        assertEq(usds.balanceOf(address(distributor)), 0, "former distributor receives no yield");
        assertEq(usds.balanceOf(address(newDistributor)), 100, "new distributor receives yield");
    }

    // given sendYieldToDistributor is false
    //   given the output token returns false on transfer to Treasury
    //     when yield is claimed and Treasury is then upgraded
    //       [X] the failed claim leaves yield available
    //       [X] a later claim pays only the new Treasury
    // Scenarios: YLD-S02
    function test_givenSendYieldToDistributorIsFalse_givenTokenTransferFails_whenTreasuryUpgrades_thenClaimPaysNewTreasury()
        public
    {
        _useMockDepositManager();
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);
        vm.mockCall(
            address(usds),
            abi.encodeWithSelector(ERC20.transfer.selector, address(trsry), 100),
            abi.encode(false)
        );

        vm.expectRevert(MockDepositManager.MockDepositManager_TransferFailed.selector);
        burnerLoans.claimYield(address(usds));

        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim rolls back");
        assertEq(mockDepositManager.claimableYield(), 100, "yield remains claimable");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "failed claim creates no payout");
        assertEq(usds.balanceOf(address(mockDepositManager)), 100, "custody retains yield");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility retains no yield");
        vm.clearMockedCalls();
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        burnerLoans.claimYield(address(usds));
        assertEq(usds.balanceOf(address(trsry)), 0, "former Treasury receives no yield");
        assertEq(usds.balanceOf(address(newTreasury)), 100, "new Treasury receives yield");
    }

    function test_givenSurplus_transfersClaimToTreasury() public {
        _depositCollateral();
        _addYield(10e6);
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            address(vaultAsset),
            preview.requestedAssetAmount,
            preview.tokenOut,
            preview.amountOut,
            address(trsry)
        );
        burnerLoans.claimYield(address(vaultAsset));
        uint256 claimed = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
        assertLe(claimed, preview.requestedAssetAmount, "claim within theoretical maximum");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "policy residual");
    }

    function test_givenVaultYield_whenWithdrawAsShares_distributesShareToken() public {
        _depositCollateral();
        _addYield(10e6);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
        _makeVaultAsynchronous(vault);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasurySharesBefore = vault.balanceOf(address(trsry));

        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(vaultAsset));

        assertEq(preview.tokenOut, address(vault), "preview token");
        // deposited shares = 100e6; vault assets after yield = 110e6
        // expected shares = floor(10e6 asset units * 100e6 shares / 110e6 asset units) = 9,090,909
        assertEq(preview.amountOut, 9_090_909, "preview shares");
        assertEq(tokenOut, address(vault), "token out");
        assertEq(amountOut, preview.amountOut, "shares out");
        assertEq(
            vault.balanceOf(address(trsry)) - treasurySharesBefore,
            amountOut,
            "Treasury shares"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "underlying residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "share residual");
    }

    // Scenarios: YLD-P06, YLD-P08
    function test_givenExternalShareToken_distributesPositiveYield(
        bool sendYieldToDistributor_,
        bool originationsDisabled_,
        address caller_
    ) public {
        (
            MockERC20 asset,
            MockERC7540ExternalShareVault externalVault,
            MockERC7540ExternalShareToken shareToken
        ) = _addAsyncExternalShareAssetForTest();
        uint128 depositedAssets = 100e18;
        asset.mint(alice, depositedAssets);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), depositedAssets);
        burnerLoans.depositCollateral(address(asset), depositedAssets, alice);
        vm.stopPrank();
        asset.mint(address(externalVault), 100e18);

        address recipient = _configureYieldRecipientForTest(
            sendYieldToDistributor_,
            address(shareToken)
        );
        if (originationsDisabled_) _setAssetOriginationsEnabled(address(asset), false);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(asset)
        );
        uint256 recipientBefore = shareToken.balanceOf(recipient);
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            address(asset),
            preview.requestedAssetAmount,
            address(shareToken),
            preview.amountOut,
            recipient
        );
        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(asset));

        assertNotEq(address(shareToken), address(externalVault), "external token should differ");
        assertNotEq(asset.decimals(), shareToken.decimals(), "fixture covers external decimals");
        assertGt(preview.amountOut, 0, "external share yield is positive");
        assertEq(preview.tokenOut, address(shareToken), "preview external token");
        assertEq(tokenOut, address(shareToken), "external token out");
        assertEq(amountOut, preview.amountOut, "external shares out");
        assertEq(
            shareToken.balanceOf(recipient) - recipientBefore,
            amountOut,
            "selected recipient receives external shares"
        );
        assertEq(shareToken.balanceOf(address(burnerLoans)), 0, "policy share residual");
        assertEq(burnerLoans.totalPendingForTest(address(shareToken)), 0, "no pending payout");
    }

    function test_givenVaultYield_givenWithdrawAsShares_whenCallerIsArbitrary(
        uint128 yieldSeed_,
        address caller_
    ) public {
        uint256 yieldAmount = bound(yieldSeed_, 2, 100e6);
        _depositCollateral();
        _addYield(yieldAmount);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
        _makeVaultAsynchronous(vault);

        uint256 vaultSupplyBefore = vault.totalSupply();
        uint256 vaultAssetsBefore = vault.totalAssets();
        // yieldAmount (asset decimals) * vaultSupplyBefore (share decimals)
        // / vaultAssetsBefore (asset decimals) = expectedShares (share decimals), rounded down.
        uint256 expectedShares = (yieldAmount * vaultSupplyBefore) / vaultAssetsBefore;
        uint256 treasurySharesBefore = vault.balanceOf(address(trsry));
        uint256 treasuryAssetsBefore = vaultAsset.balanceOf(address(trsry));
        (uint256 operatorSharesBefore, ) = depositManager.getOperatorAssets(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        assertEq(preview.requestedAssetAmount, yieldAmount, "preview asset request");
        assertEq(preview.tokenOut, address(vault), "preview token");
        assertEq(preview.amountOut, expectedShares, "preview shares");
        assertTrue(preview.executable, "preview executable");

        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(vaultAsset));

        assertEq(tokenOut, address(vault), "token out");
        assertEq(amountOut, expectedShares, "shares out");
        assertEq(
            vault.balanceOf(address(trsry)) - treasurySharesBefore,
            expectedShares,
            "Treasury share delta"
        );
        assertEq(
            vaultAsset.balanceOf(address(trsry)),
            treasuryAssetsBefore,
            "Treasury underlying unchanged"
        );
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        assertEq(operatorSharesBefore - operatorSharesAfter, expectedShares, "custody share debit");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            _COLLATERAL_AMOUNT,
            "liabilities unchanged"
        );
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            _COLLATERAL_AMOUNT,
            "position collateral unchanged"
        );
        assertEq(vault.totalSupply(), vaultSupplyBefore, "vault supply unchanged");
        assertEq(vault.totalAssets(), vaultAssetsBefore, "vault assets unchanged");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "share residual");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "underlying residual");
    }

    function test_givenTwoAssetsHaveYield_whenClaimingAssetA_doesNotClaimAssetB() public {
        _depositCollateral();
        _addYield(10e6);
        (MockERC20 assetB, MockERC4626 vaultB) = _addVaultAssetForTest();
        assetB.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        assetB.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(assetB), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
        assetB.mint(address(vaultB), 10e6);

        uint256 assetBTreasuryBalanceBefore = assetB.balanceOf(address(trsry));
        uint256 assetBVaultBalanceBefore = assetB.balanceOf(address(vaultB));
        IBurnerLoans.ClaimYieldPreview memory assetBPreviewBefore = burnerLoans.previewClaimYield(
            address(assetB)
        );

        (, uint256 assetAClaimed) = burnerLoans.claimYield(address(vaultAsset));

        IBurnerLoans.ClaimYieldPreview memory assetBPreviewAfter = burnerLoans.previewClaimYield(
            address(assetB)
        );
        assertGt(assetAClaimed, 0, "asset A claimed yield");
        assertEq(
            assetB.balanceOf(address(trsry)),
            assetBTreasuryBalanceBefore,
            "asset B Treasury balance"
        );
        assertEq(
            assetB.balanceOf(address(vaultB)),
            assetBVaultBalanceBefore,
            "asset B vault balance"
        );
        assertEq(
            assetBPreviewAfter.requestedAssetAmount,
            assetBPreviewBefore.requestedAssetAmount,
            "asset B claimable yield"
        );
    }

    function test_givenNoSurplus_doesNotTransfer() public {
        _depositCollateral();

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));
        (, uint256 actualClaimed) = burnerLoans.claimYield(address(vaultAsset));

        assertEq(actualClaimed, 0, "actual claimed amount");
        assertEq(preview.requestedAssetAmount, 0, "preview claimable yield");
        assertTrue(preview.executable, "preview executable");
        assertEq(vaultAsset.balanceOf(address(trsry)), treasuryBefore, "treasury balance");
    }

    function test_givenNoSurplus_givenDepositManagerNowRequiresShares_reverts() public {
        _depositCollateral();
        address depositManagerConfigOperator = makeAddr("depositManagerConfigOperator");
        vm.prank(admin);
        IConfigOperator(address(depositManager)).setConfigOperator(depositManagerConfigOperator);
        vm.prank(depositManagerConfigOperator);
        IDepositManagerV1_1(address(depositManager)).setAssetShareWithdrawalRequired(
            IERC20(address(vaultAsset)),
            true
        );

        bytes memory expectedError = abi.encodeWithSelector(
            IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
            address(vaultAsset),
            address(vault)
        );
        vm.expectRevert(expectedError);
        burnerLoans.previewClaimYield(address(vaultAsset));

        vm.expectRevert(expectedError);
        burnerLoans.claimYield(address(vaultAsset));
    }

    function test_givenEmptyMarket_doesNotTransfer() public {
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        burnerLoans.claimYield(address(vaultAsset));

        assertEq(preview.requestedAssetAmount, 0, "preview claimable yield");
        assertTrue(preview.executable, "preview executable");
        assertEq(vaultAsset.balanceOf(address(trsry)), treasuryBefore, "treasury balance");
    }

    function test_givenAssetOriginationsDisabled_claimsYield() public {
        _depositCollateral();
        _addYield(10e6);
        _setAssetOriginationsEnabled(address(vaultAsset), false);
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        burnerLoans.claimYield(address(vaultAsset));
        uint256 claimed = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
    }

    // Scenarios: YLD-L02
    function test_givenDisabled_reverts() public {
        _disableBurnerLoans(emergency);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewClaimYield(address(vaultAsset));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.claimYield(address(vaultAsset));
    }

    // Scenarios: YLD-L04
    function test_givenPolicyInactive_whenYieldIsPreviewedOrClaimed_reverts(
        uint8 outputMode_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupPositiveYieldMode(outputMode_);
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        uint256 managerOutputBefore = IERC20(outputToken).balanceOf(address(depositManager));
        uint256 vaultAssetsBefore = vaultAsset.balanceOf(address(vault));
        uint256 totalPendingBefore = burnerLoans.totalPendingForTest(outputToken);

        _deactivatePolicy(address(burnerLoans));
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PolicyInactive.selector
        );

        vm.expectRevert(revertData);
        burnerLoans.previewClaimYield(asset);

        vm.prank(caller_);
        vm.expectRevert(revertData);
        burnerLoans.claimYield(asset);

        assertGt(preview.amountOut, 0, "fixture has positive yield");
        assertEq(IERC20(outputToken).balanceOf(recipient), recipientBefore, "recipient unchanged");
        assertEq(
            IERC20(outputToken).balanceOf(address(depositManager)),
            managerOutputBefore,
            "manager output balance unchanged"
        );
        assertEq(vaultAsset.balanceOf(address(vault)), vaultAssetsBefore, "vault assets unchanged");
        assertEq(
            burnerLoans.totalPendingForTest(outputToken),
            totalPendingBefore,
            "pending payout reserve unchanged"
        );
    }

    // Scenarios: YLD-L05
    function test_givenDisabledAndPolicyInactive_claimAndPreviewUseLocalGuard(
        uint8 outputMode_
    ) public {
        (address asset, ) = _setupPositiveYieldMode(outputMode_);
        _disableBurnerLoans(emergency);
        _deactivatePolicy(address(burnerLoans));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewClaimYield(asset);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.claimYield(asset);
    }

    // Scenarios: YLD-L03, YLD-P01, YLD-P04, YLD-P05, YLD-P06, YLD-P07, YLD-P08
    function test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput(
        uint8 outputMode_,
        bool sendYieldToDistributor_,
        bool originationsEnabled_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupPositiveYieldMode(outputMode_);
        _setAssetOriginationsEnabled(asset, originationsEnabled_);

        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        uint256 treasuryBefore = IERC20(outputToken).balanceOf(address(trsry));
        uint256 pendingBefore = burnerLoans.totalPendingForTest(outputToken);

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            asset,
            preview.requestedAssetAmount,
            outputToken,
            preview.amountOut,
            recipient
        );
        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(asset);

        assertGt(preview.amountOut, 0, "fixture has positive yield");
        assertTrue(preview.executable, "preview is executable");
        assertEq(preview.recipient, recipient, "preview selects live recipient");
        assertEq(preview.tokenOut, outputToken, "preview selects custody output token");
        assertEq(tokenOut, outputToken, "execution output token matches preview");
        assertEq(amountOut, preview.amountOut, "execution amount matches preview");
        assertEq(
            IERC20(outputToken).balanceOf(recipient) - recipientBefore,
            amountOut,
            "selected recipient receives exact yield"
        );
        if (sendYieldToDistributor_ && recipient != address(trsry)) {
            assertEq(
                IERC20(outputToken).balanceOf(address(trsry)),
                treasuryBefore,
                "Treasury receives no distributor-routed yield"
            );
        }
        assertEq(
            burnerLoans.totalPendingForTest(outputToken),
            pendingBefore,
            "yield bypasses the pending payout ledger"
        );
        assertEq(IERC20(outputToken).balanceOf(address(burnerLoans)), 0, "no output residual");
    }

    // Scenarios: YLD-I02
    function test_givenZeroYield_whenClaimed_returnsCustodyOutputWithoutPayout(
        uint8 outputMode_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        (address asset, address outputToken) = _setupZeroYieldMode(outputMode_);
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        uint256 custodyBefore = IERC20(outputToken).balanceOf(address(depositManager));

        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(asset);

        assertEq(preview.requestedAssetAmount, 0, "preview has no yield request");
        assertEq(preview.amountOut, 0, "preview has no output amount");
        assertEq(preview.tokenOut, outputToken, "preview still resolves output token");
        assertEq(preview.recipient, recipient, "preview still resolves recipient");
        assertEq(tokenOut, outputToken, "execution returns resolved output token");
        assertEq(amountOut, 0, "execution returns zero output");
        assertEq(IERC20(outputToken).balanceOf(recipient), recipientBefore, "recipient unchanged");
        assertEq(
            IERC20(outputToken).balanceOf(address(depositManager)),
            custodyBefore,
            "custody unchanged"
        );
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending payout created");
    }

    // Scenarios: YLD-I01, YLD-I05, YLD-I06
    function test_givenUnregisteredAssetClass_previewAndClaimRevert(
        uint8 assetClass_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        uint8 assetClass = uint8(bound(assetClass_, 0, 2));
        address asset = assetClass == 0 ? address(0) : assetClass == 1
            ? makeAddr("unregistered EOA")
            : address(new MockERC20("Unregistered", "UNREG", 18));
        if (sendYieldToDistributor_) {
            _installYieldDistributorForTest(address(usds));
        }
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            asset
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewClaimYield(asset);

        vm.prank(caller_);
        vm.expectRevert(expectedError);
        burnerLoans.claimYield(asset);

        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending payout created");
    }

    // Scenarios: YLD-N01
    function test_givenOneUnitDirectYield_routesExactUnit(
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        _addDefaultUsdsAsset();
        _addDirectCustodyYield(1);
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, address(usds));
        uint256 recipientBefore = usds.balanceOf(recipient);

        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(usds));

        assertEq(tokenOut, address(usds), "direct custody returns asset");
        assertEq(amountOut, 1, "one-unit yield remains claimable");
        assertEq(usds.balanceOf(recipient) - recipientBefore, 1, "recipient receives one unit");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no pending payout created");
    }

    function _setupPositiveYieldMode(
        uint8 outputMode_
    ) internal returns (address asset, address outputToken) {
        uint8 mode = uint8(bound(outputMode_, 0, 2));
        if (mode == 0) {
            _addDefaultUsdsAsset();
            _addDirectCustodyYield(101);
            return (address(usds), address(usds));
        }

        _depositCollateral();
        _addYield(10e6);
        if (mode == 2) {
            vm.prank(admin);
            burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
            _makeVaultAsynchronous(vault);
            outputToken = address(vault);
        } else {
            outputToken = address(vaultAsset);
        }
        return (address(vaultAsset), outputToken);
    }

    function _setupCallbackYieldMode(
        uint8 outputMode_
    ) internal returns (address asset, address outputToken, address callbackInvoker) {
        uint8 mode = uint8(bound(outputMode_, 0, 2));
        if (mode == 0) {
            _addDefaultUsdsAsset();
            _addDirectCustodyYield(101);
            return (address(usds), address(usds), address(depositManager));
        }
        if (mode == 1) {
            _depositCollateral();
            _addYield(10e6);
            return (address(vaultAsset), address(vaultAsset), address(vault));
        }

        (
            MockERC20 externalAsset,
            MockERC7540ExternalShareVault externalVault,
            MockERC7540ExternalShareToken shareToken
        ) = _addAsyncExternalShareAssetForTest();
        uint128 collateral = 100e18;
        externalAsset.mint(alice, collateral);
        vm.startPrank(alice);
        externalAsset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(externalAsset), collateral, alice);
        vm.stopPrank();
        externalAsset.mint(address(externalVault), 100e18);
        return (address(externalAsset), address(shareToken), address(depositManager));
    }

    function _setupMockDepositManagerYieldMode(
        uint8 outputMode_
    ) internal returns (address asset, address outputToken, uint256 yieldAmount) {
        uint8 mode = uint8(bound(outputMode_, 0, 2));
        _useMockDepositManager();
        yieldAmount = 1e6;
        if (mode == 0) {
            uint128 collateral = 100e6;
            usds.mint(alice, collateral);
            vm.startPrank(alice);
            usds.approve(address(burnerLoans), collateral);
            burnerLoans.depositCollateral(address(usds), collateral, alice);
            vm.stopPrank();
            usds.mint(address(mockDepositManager), yieldAmount);
            mockDepositManager.setClaimableYield(yieldAmount);
            return (address(usds), address(usds), yieldAmount);
        }

        mockDepositManager.addAsset(
            IERC20(address(vaultAsset)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        mockDepositManager.addAssetPeriod(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        mockDepositManager.enableAssetPeriod(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(vaultAsset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
        vaultAsset.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        vaultAsset.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(vaultAsset), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
        if (mode == 1) {
            vaultAsset.mint(address(mockDepositManager), yieldAmount);
            outputToken = address(vaultAsset);
        } else {
            vm.prank(admin);
            burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
            vaultAsset.mint(address(vault), yieldAmount);
            outputToken = address(vault);
        }
        mockDepositManager.setClaimableYield(yieldAmount);
        return (address(vaultAsset), outputToken, yieldAmount);
    }

    function _setupZeroYieldMode(
        uint8 outputMode_
    ) internal returns (address asset, address outputToken) {
        uint8 mode = uint8(bound(outputMode_, 0, 2));
        if (mode == 0) {
            _addDefaultUsdsAsset();
            return (address(usds), address(usds));
        }

        _depositCollateral();
        if (mode == 2) {
            vm.prank(admin);
            burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
            _makeVaultAsynchronous(vault);
            outputToken = address(vault);
        } else {
            outputToken = address(vaultAsset);
        }
        return (address(vaultAsset), outputToken);
    }

    function test_givenCustodyShortfall_reverts() public {
        _depositCollateral();
        _causeShortfall(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_CustodyShortfall.selector,
                address(vaultAsset),
                _COLLATERAL_AMOUNT,
                _COLLATERAL_AMOUNT - 1,
                0
            )
        );
        burnerLoans.claimYield(address(vaultAsset));
    }

    // Scenarios: YLD-C01, YLD-C02
    function test_givenDepositManagerCallback_claimHandlesEveryCustodyMode(
        uint8 outputMode_,
        bool bubbleFailure_,
        bool sendYieldToDistributor_,
        address caller_
    ) public {
        (
            address asset,
            address outputToken,
            uint256 yieldAmount
        ) = _setupMockDepositManagerYieldMode(outputMode_);
        address recipient = _configureYieldRecipientForTest(sendYieldToDistributor_, outputToken);
        mockDepositManager.setClaimYieldCallback(
            address(burnerLoans),
            abi.encodeCall(burnerLoans.claimYield, (asset))
        );
        mockDepositManager.setClaimYieldBubbleCallbackFailure(bubbleFailure_);
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(asset);
        uint256 recipientBefore = IERC20(outputToken).balanceOf(recipient);
        uint256 custodyBefore = IERC20(outputToken).balanceOf(address(mockDepositManager));

        if (bubbleFailure_) {
            vm.prank(caller_);
            vm.expectRevert(MockDepositManager.MockDepositManager_CallbackFailed.selector);
            burnerLoans.claimYield(asset);
            assertEq(mockDepositManager.claimYieldCalls(), 0, "claim count rolls back");
            assertEq(mockDepositManager.claimableYield(), yieldAmount, "yield remains claimable");
            assertEq(
                IERC20(outputToken).balanceOf(address(mockDepositManager)),
                custodyBefore,
                "custody rolls back"
            );
            assertEq(
                IERC20(outputToken).balanceOf(recipient),
                recipientBefore,
                "recipient unchanged"
            );
            assertEq(
                burnerLoans.previewClaimYield(asset).amountOut,
                preview.amountOut,
                "preview remains unchanged"
            );
            assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "no pending payout");
            return;
        }

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            asset,
            preview.requestedAssetAmount,
            outputToken,
            preview.amountOut,
            recipient
        );
        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(asset);

        assertFalse(mockDepositManager.claimYieldCallbackSucceeded(), "nested claim is rejected");
        assertEq(
            mockDepositManager.claimYieldCallbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "nested claim reaches shared guard"
        );
        assertEq(mockDepositManager.claimYieldCalls(), 1, "outer claim executes once");
        assertEq(tokenOut, outputToken, "exact output token returned");
        assertEq(amountOut, preview.amountOut, "execution matches preview");
        assertEq(
            IERC20(outputToken).balanceOf(recipient) - recipientBefore,
            amountOut,
            "recipient paid once"
        );
        assertEq(burnerLoans.totalPendingForTest(outputToken), 0, "no pending payout");
    }

    // Scenarios: YLD-C01
    function test_givenReentrantDepositManager_claimsOnlyOnce() public {
        _useMockDepositManager();
        uint128 collateral = 100e6;
        uint256 yield = 1e6;
        usds.mint(alice, collateral);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(usds), collateral, alice);
        vm.stopPrank();
        usds.mint(address(mockDepositManager), yield);
        mockDepositManager.setClaimableYield(yield);
        mockDepositManager.setClaimYieldCallback(
            address(burnerLoans),
            abi.encodeWithSelector(bytes4(keccak256("claimYield(address)")), address(usds))
        );

        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(address(trsry)), yield, "claimed yield");
        assertEq(mockDepositManager.claimYieldCalls(), 1, "claim calls");
        assertFalse(mockDepositManager.claimYieldCallbackSucceeded(), "callback succeeded");
    }

    // Scenarios: YLD-C02
    function test_givenDepositManagerPropagatesReentrantFailure_claimRollsBack() public {
        _useMockDepositManager();
        uint128 collateral = 100e6;
        uint256 yield = 1e6;
        usds.mint(alice, collateral);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(usds), collateral, alice);
        vm.stopPrank();
        usds.mint(address(mockDepositManager), yield);
        mockDepositManager.setClaimableYield(yield);
        mockDepositManager.setClaimYieldCallback(
            address(burnerLoans),
            abi.encodeCall(burnerLoans.claimYield, (address(usds)))
        );
        mockDepositManager.setClaimYieldBubbleCallbackFailure(true);
        IBurnerLoans.ClaimYieldPreview memory previewBefore = burnerLoans.previewClaimYield(
            address(usds)
        );
        uint256 custodyBefore = usds.balanceOf(address(mockDepositManager));

        vm.expectRevert(MockDepositManager.MockDepositManager_CallbackFailed.selector);
        burnerLoans.claimYield(address(usds));

        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim count rolls back");
        assertEq(mockDepositManager.claimableYield(), yield, "yield remains claimable");
        assertEq(
            usds.balanceOf(address(mockDepositManager)),
            custodyBefore,
            "custody remains unchanged"
        );
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury receives nothing");
        assertEq(
            burnerLoans.previewClaimYield(address(usds)).amountOut,
            previewBefore.amountOut,
            "preview remains unchanged"
        );
    }

    function test_givenAssetNotConfigured_reverts() public {
        address unconfiguredAsset = makeAddr("unconfiguredAsset");
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            unconfiguredAsset
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewClaimYield(unconfiguredAsset);

        vm.expectRevert(expectedError);
        burnerLoans.claimYield(unconfiguredAsset);
    }

    function test_givenDepositManagerDisabled_reverts() public {
        vm.prank(admin);
        _disableDepositManager();
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
            address(depositManager)
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewClaimYield(address(vaultAsset));

        vm.expectRevert(expectedError);
        burnerLoans.claimYield(address(vaultAsset));
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast,calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
