// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {BurnerLoansClaimYieldTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansClaimYieldTestBase.sol";
import {MockYieldRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRecipient.sol";

contract BurnerLoansClaimYieldTest is BurnerLoansClaimYieldTestBase {
    function test_givenValidAllocation_distributesFloorAndExactRemainder_fuzz(
        uint128 claimed_,
        uint16 bps_,
        address caller_
    ) public {
        claimed_ = uint128(bound(claimed_, 1, type(uint96).max));
        bps_ = uint16(bound(bps_, 0, 10_000));
        vm.assume(caller_ != address(0));
        _useMockDepositManager();
        MockYieldRecipient recipient = _configureYieldRouting(address(usds), address(0), bps_);
        usds.mint(address(mockDepositManager), claimed_);
        mockDepositManager.setClaimableYield(claimed_);

        vm.prank(caller_);
        burnerLoans.claimYield();

        // claimed_ (asset decimals) * bps_ (4 decimals) / 10_000 (4 decimals)
        // = recipientAmount (asset decimals), rounded down in favor of treasury.
        uint256 recipientAmount = (uint256(claimed_) * bps_) / 10_000;
        assertEq(usds.balanceOf(address(recipient)), recipientAmount, "recipient amount");
        assertEq(
            usds.balanceOf(address(trsry)),
            uint256(claimed_) - recipientAmount,
            "treasury remainder"
        );
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenSplitAllocation_emitsSingleClaimEvent() public {
        _useMockDepositManager();
        MockYieldRecipient recipient = _configureYieldRouting(address(usds), address(0), 7_000);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit IBurnerLoans.YieldClaimed(address(usds), address(recipient), 101, 70, 31);
        burnerLoans.claimYield();
    }

    function test_givenZeroBps_doesNotConsultBrokenYieldRecipient() public {
        _useMockDepositManager();
        MockYieldRecipient recipient = _configureYieldRouting(address(usds), address(0), 0);
        recipient.setRevertGetVaultConfig(true);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        burnerLoans.claimYield();

        assertEq(usds.balanceOf(address(recipient)), 0, "recipient amount");
        assertEq(usds.balanceOf(address(trsry)), 101, "treasury amount");
    }

    function test_givenDepositManagerReturnsLessThanRequested_distributesActualAmount() public {
        _useMockDepositManager();
        MockYieldRecipient recipient = _configureYieldRouting(address(usds), address(0), 5_000);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);
        mockDepositManager.setClaimActualAmountOverride(true, 40);

        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit IBurnerLoans.YieldClaimed(address(usds), address(recipient), 40, 20, 20);
        burnerLoans.claimYield();

        assertEq(usds.balanceOf(address(recipient)), 20, "recipient amount");
        assertEq(usds.balanceOf(address(trsry)), 20, "treasury amount");
        assertEq(mockDepositManager.claimableYield(), 61, "remaining claimable yield");
    }

    function test_givenRuntimeRecipientDisabled_reverts() public {
        _useMockDepositManager();
        MockYieldRecipient recipient = _configureYieldRouting(address(usds), address(0), 5_000);
        recipient.setEnabled(false);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRecipientNotEnabled.selector,
                address(recipient)
            )
        );
        burnerLoans.claimYield();

        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim calls");
        assertEq(mockDepositManager.claimableYield(), 101, "claimable yield");
    }

    function test_givenRecipientAssetLookupReverts_reverts() public {
        _useMockDepositManager();
        MockYieldRecipient recipient = _configureYieldRouting(address(usds), address(0), 5_000);
        recipient.setRevertGetVaultConfig(true);

        vm.expectRevert(MockYieldRecipient.MockYieldRecipient_GetVaultConfigFailed.selector);
        burnerLoans.claimYield();
    }

    function test_givenSurplus_transfersClaimToTreasury() public {
        _depositCollateral();
        _addYield(10e6);
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        burnerLoans.claimYield();
        uint256 claimed = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
        assertLe(claimed, preview.amount, "claim within theoretical maximum");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "policy residual");
    }

    function test_givenNoSurplus_doesNotTransfer() public {
        _depositCollateral();

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));
        burnerLoans.claimYield();

        assertEq(preview.amount, 0, "preview claimable yield");
        assertTrue(preview.executable, "preview executable");
        assertEq(vaultAsset.balanceOf(address(trsry)), treasuryBefore, "treasury balance");
    }

    function test_givenEmptyMarket_doesNotTransfer() public {
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        burnerLoans.claimYield();

        assertEq(preview.amount, 0, "preview claimable yield");
        assertTrue(preview.executable, "preview executable");
        assertEq(vaultAsset.balanceOf(address(trsry)), treasuryBefore, "treasury balance");
    }

    function test_givenAssetOriginationsDisabled_claimsYield() public {
        _depositCollateral();
        _addYield(10e6);
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(vaultAsset), false);
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        burnerLoans.claimYield();
        uint256 claimed = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
    }

    function test_givenDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewClaimYield(address(vaultAsset));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.claimYield();
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
        burnerLoans.claimYield();
    }

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
            abi.encodeCall(burnerLoans.claimYield, ())
        );

        burnerLoans.claimYield();

        assertEq(usds.balanceOf(address(trsry)), yield, "claimed yield");
        assertEq(mockDepositManager.claimYieldCalls(), 1, "claim calls");
        assertFalse(mockDepositManager.claimYieldCallbackSucceeded(), "callback succeeded");
    }

    function test_givenAssetNotConfigured_reverts() public {
        address unconfiguredAsset = makeAddr("unconfiguredAsset");
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            unconfiguredAsset
        );

        vm.expectRevert(error);
        burnerLoans.previewClaimYield(unconfiguredAsset);
    }

    function test_givenDepositManagerDisabled_reverts() public {
        vm.prank(admin);
        _disableDepositManager();
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
            address(depositManager)
        );

        vm.expectRevert(error);
        burnerLoans.previewClaimYield(address(vaultAsset));

        vm.expectRevert(error);
        burnerLoans.claimYield();
    }

    function test_givenMultipleRegisteredAssets_claimsYieldForAll() public {
        _depositCollateral();
        _addYield(10e6);

        (MockERC20 secondAsset, MockERC4626 secondVault) = _addVaultAssetForTest();
        secondAsset.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        secondAsset.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(secondAsset), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
        secondAsset.mint(address(secondVault), 20e6);

        uint256 firstTreasuryBefore = vaultAsset.balanceOf(address(trsry));
        uint256 secondTreasuryBefore = secondAsset.balanceOf(address(trsry));
        burnerLoans.claimYield();
        uint256 firstClaimed = vaultAsset.balanceOf(address(trsry)) - firstTreasuryBefore;
        uint256 secondClaimed = secondAsset.balanceOf(address(trsry)) - secondTreasuryBefore;

        assertGt(firstClaimed, 0, "first asset claimed");
        assertGt(secondClaimed, 0, "second asset claimed");
    }
}
