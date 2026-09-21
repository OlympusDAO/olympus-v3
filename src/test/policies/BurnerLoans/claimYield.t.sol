// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {BurnerLoansClaimYieldTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansClaimYieldTestBase.sol";
import {MockYieldRepurchaseRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRepurchaseRecipient.sol";
import {MockERC7540ExternalShareToken, MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault} from "src/test/policies/DepositManager/fixtures/MockERC7575Vault.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop)

contract BurnerLoansClaimYieldTest is BurnerLoansClaimYieldTestBase {
    // Vault supply = 100e6 shares and vault assets = 200e18 after the donation.
    // yield shares = 100e18 yield * 100e6 shares / 200e18 assets = 50e6 shares.
    uint256 internal constant _EXPECTED_EXTERNAL_SHARE_YIELD = 50e6;

    function test_givenShareYieldBelowOneShare_whenRepeatedClaims(address caller_) public {
        _depositCollateral();
        _addYield(1);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(vaultAsset), true);
        _makeVaultAsynchronous(vault);

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
                address(burnerLoans),
                address(burnerLoans),
                1,
                address(vault),
                0
            );
            vm.expectEmit(true, true, true, true, address(depositManager));
            emit IDepositManagerV1_1.OperatorYieldClaimed(
                address(vaultAsset),
                address(burnerLoans),
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
        assertEq(vault.balanceOf(address(trsry)), 1, "Treasury receives retained yield");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "no policy share residual");
    }

    function test_givenDirectCustodyTreasuryOnlyRouting_claimsYield() public {
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
        assertEq(usds.balanceOf(address(depositManager)), 1, "custody solvency buffer");
    }

    function test_givenDirectCustodyDirectRouting_distributesYield() public {
        _addDefaultUsdsAsset();
        address recipient = makeAddr("directCustodyRecipient");
        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 4_000;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        _addDirectCustodyYield(101);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(usds)
        );
        (, uint256 actualClaimed) = burnerLoans.claimYield(address(usds));

        // claimed = 101 (asset decimals), direct BPS = 4,000 (4 decimals).
        // Direct amount = floor(101 * 4,000 / 10,000) = 40; Treasury receives 61.
        assertEq(preview.requestedAssetAmount, 101, "preview amount");
        assertTrue(preview.executable, "preview executable");
        assertEq(actualClaimed, 101, "actual claimed amount");
        assertEq(usds.balanceOf(recipient), 40, "direct recipient amount");
        assertEq(usds.balanceOf(address(trsry)), 61, "Treasury remainder");
        assertEq(usds.balanceOf(address(depositManager)), 1, "custody solvency buffer");
    }

    function test_givenValidRouting_whenSingleAssetCallerIsArbitrary(
        uint128 claimed_,
        address caller_
    ) public {
        claimed_ = uint128(bound(claimed_, 1, type(uint96).max));
        _useMockDepositManager();
        _configureYieldRouting(address(usds), address(0), 0);
        usds.mint(address(mockDepositManager), claimed_);
        mockDepositManager.setClaimableYield(claimed_);

        vm.prank(caller_);
        (, uint256 actualClaimed) = burnerLoans.claimYield(address(usds));

        assertEq(actualClaimed, claimed_, "actual claimed amount");
        assertEq(usds.balanceOf(address(trsry)), claimed_, "Treasury amount");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenValidRepurchaseAllocation_whenCallerIsArbitrary(
        uint128 claimed_,
        uint16 bps_,
        address caller_
    ) public {
        claimed_ = uint128(bound(claimed_, 1, type(uint96).max));
        bps_ = uint16(bound(bps_, 0, 10_000));
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            bps_
        );
        usds.mint(address(mockDepositManager), claimed_);
        mockDepositManager.setClaimableYield(claimed_);

        vm.prank(caller_);
        burnerLoans.claimYield(address(usds));

        // claimed_ (asset decimals) * bps_ (4 decimals) / 10_000 (4 decimals)
        // = repurchaseAmount (asset decimals), rounded down in favor of Treasury.
        uint256 repurchaseAmount = (uint256(claimed_) * bps_) / 10_000;
        assertEq(usds.balanceOf(address(recipient)), repurchaseAmount, "repurchase amount");
        assertEq(
            usds.balanceOf(address(trsry)),
            uint256(claimed_) - repurchaseAmount,
            "Treasury remainder"
        );
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenMixedRouting_emitsOrderedClaimResult() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            3_000
        );
        address directRecipient1 = makeAddr("directRecipient1");
        address directRecipient2 = makeAddr("directRecipient2");
        address[] memory directRecipients = new address[](2);
        directRecipients[0] = directRecipient1;
        directRecipients[1] = directRecipient2;
        uint16[] memory directBps = new uint16[](2);
        directBps[0] = 2_000;
        directBps[1] = 1_000;
        IBurnerLoans.AssetYieldRouting memory routing = _directRouting(directRecipients, directBps);
        routing.repurchaseRecipientBps = 3_000;
        _setYieldAssetRouting(address(usds), routing);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        IBurnerLoans.YieldDistribution[]
            memory distributions = new IBurnerLoans.YieldDistribution[](4);
        distributions[0] = IBurnerLoans.YieldDistribution({
            recipient: address(recipient),
            amount: 30
        });
        distributions[1] = IBurnerLoans.YieldDistribution({
            recipient: directRecipient1,
            amount: 20
        });
        distributions[2] = IBurnerLoans.YieldDistribution({
            recipient: directRecipient2,
            amount: 10
        });
        distributions[3] = IBurnerLoans.YieldDistribution({recipient: address(trsry), amount: 41});
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit IBurnerLoans.YieldClaimed(address(usds), 101, address(usds), 101, distributions);
        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(address(recipient)), 30, "repurchase amount");
        assertEq(usds.balanceOf(directRecipient1), 20, "first direct amount");
        assertEq(usds.balanceOf(directRecipient2), 10, "second direct amount");
        assertEq(usds.balanceOf(address(trsry)), 41, "Treasury amount with residual");
    }

    function test_givenTreasuryOnlyRouting_doesNotConsultBrokenRepurchaseRecipient() public {
        _useMockDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(0),
            0
        );
        recipient.setRevertGetVaultConfig(true);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(address(recipient)), 0, "repurchase amount");
        assertEq(usds.balanceOf(address(trsry)), 101, "Treasury amount");
    }

    function test_givenRepurchaseOnlyRouting_distributesEntireClaimToRepurchaseRecipient() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            BurnerLoansConstants.MAX_BPS
        );
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(address(recipient)), 101, "repurchase amount");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury amount");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenDepositManagerReturnsLessThanRequested_distributesActualAmount() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            5_000
        );
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);
        mockDepositManager.setClaimActualAmountOverride(true, 40);

        IBurnerLoans.YieldDistribution[]
            memory distributions = new IBurnerLoans.YieldDistribution[](2);
        distributions[0] = IBurnerLoans.YieldDistribution({
            recipient: address(recipient),
            amount: 20
        });
        distributions[1] = IBurnerLoans.YieldDistribution({recipient: address(trsry), amount: 20});
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit IBurnerLoans.YieldClaimed(address(usds), 101, address(usds), 40, distributions);
        (, uint256 actualClaimed) = burnerLoans.claimYield(address(usds));

        assertEq(actualClaimed, 40, "actual claimed amount");
        assertEq(usds.balanceOf(address(recipient)), 20, "repurchase amount");
        assertEq(usds.balanceOf(address(trsry)), 20, "Treasury amount");
        assertEq(mockDepositManager.claimableYield(), 61, "remaining claimable yield");
    }

    function test_givenOneRecipientTransferFails_revertsEveryDistributionForAsset() public {
        _useMockDepositManager();
        address firstRecipient = makeAddr("firstRecipient");
        address failingRecipient = makeAddr("failingRecipient");
        address[] memory recipients = new address[](2);
        recipients[0] = firstRecipient;
        recipients[1] = failingRecipient;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 2_000;
        bps[1] = 2_000;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);
        vm.mockCall(
            address(usds),
            abi.encodeWithSelector(ERC20.transfer.selector, failingRecipient, 20),
            abi.encode(false)
        );

        vm.expectRevert(bytes("TRANSFER_FAILED"));
        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(firstRecipient), 0, "first direct amount");
        assertEq(usds.balanceOf(failingRecipient), 0, "failing direct amount");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury amount");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim calls");
        assertEq(mockDepositManager.claimableYield(), 100, "claimable yield");
    }

    function test_givenRuntimeRepurchaseRecipientDisabled_reverts() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            5_000
        );
        recipient.setEnabled(false);
        usds.mint(address(mockDepositManager), 101);
        mockDepositManager.setClaimableYield(101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(recipient)
            )
        );
        burnerLoans.previewClaimYield(address(usds));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(recipient)
            )
        );
        burnerLoans.claimYield(address(usds));

        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim calls");
        assertEq(mockDepositManager.claimableYield(), 101, "claimable yield");
    }

    function test_givenRuntimeRepurchaseRecipientReEnabled_previewAndClaimSucceed() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            5_000
        );
        recipient.setEnabled(false);
        recipient.setEnabled(true);
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(usds)
        );
        burnerLoans.claimYield(address(usds));

        assertEq(preview.requestedAssetAmount, 100, "preview amount");
        assertTrue(preview.executable, "preview executable");
        assertEq(usds.balanceOf(address(recipient)), 50, "repurchase amount");
        assertEq(usds.balanceOf(address(trsry)), 50, "Treasury amount");
    }

    function test_givenRecipientAssetLookupReverts_reverts() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            5_000
        );
        recipient.setRevertGetVaultConfig(true);

        vm.expectRevert(
            MockYieldRepurchaseRecipient.MockYieldRepurchaseRecipient_GetVaultConfigFailed.selector
        );
        burnerLoans.claimYield(address(usds));
    }

    function test_givenAllDirectRouting_distributesToEoaAndContractRecipients() public {
        _useMockDepositManager();
        address eoaRecipient = makeAddr("eoaRecipient");
        address contractRecipient = address(new MockERC4626(usds, "Recipient", "RECIPIENT"));
        address[] memory recipients = new address[](2);
        recipients[0] = eoaRecipient;
        recipients[1] = contractRecipient;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 6_000;
        bps[1] = 4_000;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);

        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(eoaRecipient), 60, "EOA direct amount");
        assertEq(usds.balanceOf(contractRecipient), 40, "contract direct amount");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury amount");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenFiveDirectAllocations_distributesEveryConfiguredLeg() public {
        _useMockDepositManager();
        address[] memory recipients = new address[](5);
        uint16[] memory bps = new uint16[](5);
        for (uint256 i; i < recipients.length; ++i) {
            recipients[i] = makeAddr(string.concat("directRecipient", vm.toString(i)));
            bps[i] = 1_000;
        }
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        usds.mint(address(mockDepositManager), 11);
        mockDepositManager.setClaimableYield(11);

        burnerLoans.claimYield(address(usds));

        for (uint256 i; i < recipients.length; ++i) {
            // claimed = 11 (asset decimals), BPS = 1_000 (4 decimals)
            // Expected: floor(11 * 1_000 / 10_000) = 1 (asset decimals).
            assertEq(usds.balanceOf(recipients[i]), 1, "direct allocation amount");
        }
        // Five direct floors consume 5. Treasury receives its 50% share plus the rounding residual.
        assertEq(usds.balanceOf(address(trsry)), 6, "Treasury amount with residual");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenTinyClaim_skipsZeroTransferLegAndReportsZeroDistribution() public {
        _useMockDepositManager();
        address directRecipient = makeAddr("directRecipient");
        address[] memory recipients = new address[](1);
        recipients[0] = directRecipient;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 1;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        usds.mint(address(mockDepositManager), 1);
        mockDepositManager.setClaimableYield(1);

        // If the implementation makes this zero-value token call, the mocked false return makes
        // TransferHelper revert. Success therefore proves that zero-value legs are skipped.
        vm.mockCall(
            address(usds),
            abi.encodeWithSelector(ERC20.transfer.selector, directRecipient, 0),
            abi.encode(false)
        );
        IBurnerLoans.YieldDistribution[]
            memory distributions = new IBurnerLoans.YieldDistribution[](2);
        distributions[0] = IBurnerLoans.YieldDistribution({recipient: directRecipient, amount: 0});
        distributions[1] = IBurnerLoans.YieldDistribution({recipient: address(trsry), amount: 1});
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit IBurnerLoans.YieldClaimed(address(usds), 1, address(usds), 1, distributions);

        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(directRecipient), 0, "rounded direct amount");
        assertEq(usds.balanceOf(address(trsry)), 1, "Treasury rounding remainder");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual");
    }

    function test_givenDirectTransferFails_revertsAndRollsBackClaim() public {
        _useMockDepositManager();
        address directRecipient = makeAddr("directRecipient");
        address[] memory recipients = new address[](1);
        recipients[0] = directRecipient;
        uint16[] memory bps = new uint16[](1);
        bps[0] = BurnerLoansConstants.MAX_BPS;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);
        vm.mockCall(
            address(usds),
            abi.encodeWithSelector(ERC20.transfer.selector, directRecipient, 100),
            abi.encode(false)
        );

        // TransferHelper exposes only a legacy Error(string), so no custom selector is available.
        vm.expectRevert();
        burnerLoans.claimYield(address(usds));

        assertEq(mockDepositManager.claimYieldCalls(), 0, "claim calls rolled back");
        assertEq(mockDepositManager.claimableYield(), 100, "claimable yield rolled back");
        assertEq(usds.balanceOf(address(mockDepositManager)), 100, "custody balance rolled back");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "facility residual rolled back");
    }

    function test_givenBrokenRepurchaseRoute_whenRepairedToTreasuryOnly_claimSucceeds() public {
        _useMockVaultDepositManager();
        MockYieldRepurchaseRecipient recipient = _configureYieldRouting(
            address(usds),
            address(mockYieldVault),
            5_000
        );
        recipient.setEnabled(false);
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(recipient)
            )
        );
        burnerLoans.claimYield(address(usds));

        _setYieldAssetRouting(address(usds), _repurchaseRouting(0));
        burnerLoans.claimYield(address(usds));

        assertEq(usds.balanceOf(address(recipient)), 0, "repurchase amount");
        assertEq(usds.balanceOf(address(trsry)), 100, "Treasury amount after repair");
        assertEq(mockDepositManager.claimableYield(), 0, "claimable yield after repair");
    }

    function test_givenSurplus_transfersClaimToTreasury() public {
        _depositCollateral();
        _addYield(10e6);
        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

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

    function test_givenExternalShareTokenWithSameDecimals_whenClaimingYield_distributesExternalToken()
        public
    {
        (
            MockERC20 asset,
            MockERC7575Vault externalVault,
            IERC20 shareToken
        ) = _addSameDecimalExternalShareAssetForTest();
        uint128 depositedAssets = 100e18;
        asset.mint(alice, depositedAssets + 10e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), depositedAssets);
        burnerLoans.depositCollateral(address(asset), depositedAssets, alice);
        asset.approve(address(depositManager), 10e18);
        vm.stopPrank();
        vm.prank(address(burnerLoans));
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: IERC20(address(asset)),
                payer: alice,
                amount: 10e18,
                maxAmount: 0
            })
        );

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(asset)
        );
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(asset));

        assertNotEq(address(shareToken), address(externalVault), "external token should differ");
        assertEq(asset.decimals(), shareToken.decimals(), "token decimals should match");
        assertEq(preview.tokenOut, address(shareToken), "preview external token");
        assertEq(tokenOut, address(shareToken), "external token out");
        assertEq(amountOut, preview.amountOut, "external shares out");
        assertEq(shareToken.balanceOf(address(trsry)), amountOut, "Treasury external shares");
        assertEq(shareToken.balanceOf(address(burnerLoans)), 0, "policy share residual");
    }

    function test_givenExternalShareTokenWithDifferentDecimals_whenClaimingYield_distributesExternalToken()
        public
    {
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

        // Donated underlying moves one share from 1e12 to 2e12 asset units, creating 100e18 yield.
        asset.mint(address(externalVault), 100e18);
        address directRecipient = makeAddr("externalShareDirectRecipient");
        address[] memory directRecipients = new address[](1);
        directRecipients[0] = directRecipient;
        uint16[] memory directBps = new uint16[](1);
        directBps[0] = 3_000;
        MockYieldRepurchaseRecipient repurchaseRecipient = _configureYieldRouting(
            address(asset),
            address(externalVault),
            2_000
        );
        IBurnerLoans.AssetYieldRouting memory routing = _directRouting(directRecipients, directBps);
        routing.repurchaseRecipientBps = 2_000;
        _setYieldAssetRouting(address(asset), routing);

        IBurnerLoans.ClaimYieldPreview memory preview = burnerLoans.previewClaimYield(
            address(asset)
        );
        (address tokenOut, uint256 amountOut) = burnerLoans.claimYield(address(asset));

        assertNotEq(address(shareToken), address(externalVault), "external token should differ");
        assertEq(asset.decimals(), 18, "underlying decimals");
        assertEq(shareToken.decimals(), 6, "share decimals");
        assertEq(preview.requestedAssetAmount, 100e18, "underlying yield request");
        assertEq(preview.tokenOut, address(shareToken), "preview external token");
        assertEq(preview.amountOut, _EXPECTED_EXTERNAL_SHARE_YIELD, "preview raw shares");
        assertEq(tokenOut, address(shareToken), "external token out");
        assertEq(amountOut, _EXPECTED_EXTERNAL_SHARE_YIELD, "raw shares out");
        assertEq(shareToken.balanceOf(address(repurchaseRecipient)), 10e6, "repurchase shares");
        assertEq(shareToken.balanceOf(directRecipient), 15e6, "direct recipient shares");
        assertEq(shareToken.balanceOf(address(trsry)), 25e6, "Treasury shares");
        assertEq(shareToken.balanceOf(address(burnerLoans)), 0, "policy share residual");
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
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(vaultAsset), false);
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        burnerLoans.claimYield(address(vaultAsset));
        uint256 claimed = vaultAsset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
    }

    function test_givenDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewClaimYield(address(vaultAsset));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.claimYield(address(vaultAsset));
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

    function test_givenRouteChangeCallback_rejectsReentrantConfiguration() public {
        _useMockDepositManager();
        address directRecipient = makeAddr("directRecipient");
        address[] memory recipients = new address[](1);
        recipients[0] = directRecipient;
        uint16[] memory bps = new uint16[](1);
        bps[0] = BurnerLoansConstants.MAX_BPS;
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));

        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(mockDepositManager));
        mockDepositManager.setClaimYieldCallback(
            address(burnerLoansConfig),
            abi.encodeCall(
                burnerLoansConfig.setYieldAssetRouting,
                (address(usds), _repurchaseRouting(0))
            )
        );
        usds.mint(address(mockDepositManager), 100);
        mockDepositManager.setClaimableYield(100);

        burnerLoans.claimYield(address(usds));

        assertFalse(mockDepositManager.claimYieldCallbackSucceeded(), "route callback succeeded");
        assertEq(usds.balanceOf(directRecipient), 100, "direct amount");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury amount");
        IBurnerLoans.AssetYieldRouting memory stored = burnerLoans.getYieldAssetRouting(
            address(usds)
        );
        assertEq(stored.directAllocations.length, 1, "reentrant replacement direct count");
        assertEq(
            stored.directAllocations[0].recipient,
            directRecipient,
            "reentrant replacement recipient"
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
