// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Contracts
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansClaimYieldTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansClaimYieldTestBase.sol";
import {MockYieldRepurchaseRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRepurchaseRecipient.sol";

contract BurnerLoansYieldClaimerExecuteIntegrationTest is BurnerLoansClaimYieldTestBase {
    uint32 internal constant _ROUTE_EXECUTION_GAS_LIMIT = 700_000;

    address internal _heart;
    BurnerLoansYieldClaimer internal _claimer;
    MockYieldRepurchaseRecipient internal _repurchaseRecipient;

    function setUp() public override {
        super.setUp();

        _heart = makeAddr("yieldClaimerHeart");
        vm.startPrank(admin);
        _claimer = new BurnerLoansYieldClaimer(
            kernel,
            address(burnerLoans),
            _ROUTE_EXECUTION_GAS_LIMIT
        );
        kernel.executeAction(Actions.ActivatePolicy, address(_claimer));
        rolesAdmin.grantRole(HEART_ROLE, _heart);
        _claimer.enable("");
        vm.stopPrank();

        _repurchaseRecipient = _configureYieldRouting(address(vaultAsset), address(vault), 1_000);
        _depositCollateral();
    }

    function test_givenBurnerLoansDisabled_reportsFailureForEveryAsset() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);

        uint256 firstVaultBalanceBefore = vaultAsset.balanceOf(address(vault));
        uint256 firstTreasuryBalanceBefore = vaultAsset.balanceOf(address(trsry));
        uint256 firstRepurchaseBalanceBefore = vaultAsset.balanceOf(address(_repurchaseRecipient));
        uint256 laterVaultBalanceBefore = laterAsset.balanceOf(address(laterVault));
        uint256 laterTreasuryBalanceBefore = laterAsset.balanceOf(address(trsry));
        uint256 laterRepurchaseBalanceBefore = laterAsset.balanceOf(address(_repurchaseRecipient));

        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            address(vaultAsset),
            IEnabler.NotEnabled.selector
        );
        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            address(laterAsset),
            IEnabler.NotEnabled.selector
        );
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            vaultAsset.balanceOf(address(vault)),
            firstVaultBalanceBefore,
            "first vault balance"
        );
        assertEq(
            vaultAsset.balanceOf(address(trsry)),
            firstTreasuryBalanceBefore,
            "first Treasury balance"
        );
        assertEq(
            vaultAsset.balanceOf(address(_repurchaseRecipient)),
            firstRepurchaseBalanceBefore,
            "first repurchase recipient balance"
        );
        assertEq(
            laterAsset.balanceOf(address(laterVault)),
            laterVaultBalanceBefore,
            "later vault balance"
        );
        assertEq(
            laterAsset.balanceOf(address(trsry)),
            laterTreasuryBalanceBefore,
            "later Treasury balance"
        );
        assertEq(
            laterAsset.balanceOf(address(_repurchaseRecipient)),
            laterRepurchaseBalanceBefore,
            "later repurchase recipient balance"
        );
    }

    function test_givenRouteExceedsExecutionGasLimit_emitsFailureWithoutReverting() public {
        IBurnerLoans.AssetYieldRouting memory smallRouting = _routingWithDirectRecipients(1);
        _setYieldAssetRouting(address(vaultAsset), smallRouting);
        _addYield(10e6);
        uint256 smallClaimableBefore = burnerLoans.previewClaimYield(address(vaultAsset)).amount;

        vm.prank(_heart);
        _claimer.execute();

        assertGt(
            vaultAsset.balanceOf(smallRouting.directAllocations[0].recipient),
            0,
            "small route direct recipient amount"
        );
        assertLt(
            burnerLoans.previewClaimYield(address(vaultAsset)).amount,
            smallClaimableBefore,
            "small route reduces claimable yield"
        );

        IBurnerLoans.AssetYieldRouting memory largeRouting = _routingWithDirectRecipients(25);
        _setYieldAssetRouting(address(vaultAsset), largeRouting);
        _addYield(10e6);

        uint256 claimableBefore = burnerLoans.previewClaimYield(address(vaultAsset)).amount;
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));
        uint256 repurchaseBefore = vaultAsset.balanceOf(address(_repurchaseRecipient));
        uint256[] memory directBalancesBefore = new uint256[](
            largeRouting.directAllocations.length
        );
        for (uint256 i; i < largeRouting.directAllocations.length; ++i) {
            directBalancesBefore[i] = vaultAsset.balanceOf(
                largeRouting.directAllocations[i].recipient
            );
        }

        // Nested gas exhaustion can surface with empty revert data or a token revert selector,
        // depending on the compilation profile. The asset failure and atomic rollback are invariant.
        vm.expectEmit(true, false, false, false, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(address(vaultAsset), bytes4(0));
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            burnerLoans.previewClaimYield(address(vaultAsset)).amount,
            claimableBefore,
            "failed claim preserves claimable yield"
        );
        assertEq(vaultAsset.balanceOf(address(trsry)), treasuryBefore, "Treasury balance");
        assertEq(
            vaultAsset.balanceOf(address(_repurchaseRecipient)),
            repurchaseBefore,
            "repurchase recipient balance"
        );
        for (uint256 i; i < largeRouting.directAllocations.length; ++i) {
            assertEq(
                vaultAsset.balanceOf(largeRouting.directAllocations[i].recipient),
                directBalancesBefore[i],
                "direct recipient balance"
            );
        }
    }

    function test_givenActiveRepurchaseRecipientDisabled_skipsAssetAndClaimsLaterAsset() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);
        uint256 laterClaimable = burnerLoans.previewClaimYield(address(laterAsset)).amount;
        uint256 failedVaultBalanceBefore = vaultAsset.balanceOf(address(vault));
        _repurchaseRecipient.setEnabled(false);

        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            address(vaultAsset),
            IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector
        );
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            vaultAsset.balanceOf(address(vault)),
            failedVaultBalanceBefore,
            "failed asset vault balance"
        );
        assertEq(vaultAsset.balanceOf(address(trsry)), 0, "failed asset Treasury balance");
        assertGt(laterAsset.balanceOf(address(trsry)), 0, "later asset Treasury balance");
        assertLt(
            burnerLoans.previewClaimYield(address(laterAsset)).amount,
            laterClaimable,
            "later asset claimable yield"
        );
    }

    function test_givenRecipientTransferFails_skipsAssetAndClaimsLaterAsset() public {
        address failingRecipient = makeAddr("failingRecipient");
        address[] memory recipients = new address[](1);
        recipients[0] = failingRecipient;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 2_000;
        _setYieldAssetRouting(address(vaultAsset), _directRouting(recipients, bps));
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);
        uint256 failedClaimable = burnerLoans.previewClaimYield(address(vaultAsset)).amount;
        uint256 failingAmount = (failedClaimable * 2_000) / 10_000;
        uint256 laterClaimable = burnerLoans.previewClaimYield(address(laterAsset)).amount;
        uint256 failedVaultBalanceBefore = vaultAsset.balanceOf(address(vault));
        vm.mockCall(
            address(vaultAsset),
            abi.encodeWithSelector(ERC20.transfer.selector, failingRecipient, failingAmount),
            abi.encode(false)
        );

        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            address(vaultAsset),
            bytes4(keccak256("Error(string)"))
        );
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            vaultAsset.balanceOf(address(vault)),
            failedVaultBalanceBefore,
            "failed asset vault balance"
        );
        assertEq(vaultAsset.balanceOf(failingRecipient), 0, "failed recipient balance");
        assertEq(vaultAsset.balanceOf(address(trsry)), 0, "failed asset Treasury balance");
        assertGt(laterAsset.balanceOf(address(trsry)), 0, "later asset Treasury balance");
        assertLt(
            burnerLoans.previewClaimYield(address(laterAsset)).amount,
            laterClaimable,
            "later asset claimable yield"
        );
    }

    function test_givenPeriodicTaskExceedsGasLimit_directClaimRemainsAvailable() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        laterAsset.mint(address(laterVault), 10e6);
        uint256 claimableBefore = burnerLoans.previewClaimYield(address(laterAsset)).amount;

        vm.prank(admin);
        _claimer.setExecutionGasLimit(1);

        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            burnerLoans.previewClaimYield(address(laterAsset)).amount,
            claimableBefore,
            "periodic skip preserves claimable yield"
        );

        burnerLoans.claimYield(address(laterAsset));

        assertLt(
            burnerLoans.previewClaimYield(address(laterAsset)).amount,
            claimableBefore,
            "manual claim reduces claimable yield"
        );
    }

    function _routingWithDirectRecipients(
        uint16 directCount_
    ) internal returns (IBurnerLoans.AssetYieldRouting memory routing) {
        routing.repurchaseRecipientBps = 1_000;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](directCount_);
        for (uint256 i; i < directCount_; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: makeAddr(string.concat("yieldClaimerDirectRecipient", vm.toString(i))),
                bps: 1
            });
        }
    }

    function _depositCollateral(MockERC20 asset_) internal {
        asset_.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        asset_.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(asset_), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
    }
}
