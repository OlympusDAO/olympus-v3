// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Contracts
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansClaimYieldTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansClaimYieldTestBase.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop)

contract BurnerLoansYieldClaimerExecuteIntegrationTest is BurnerLoansClaimYieldTestBase {
    uint32 internal constant _ROUTE_EXECUTION_GAS_LIMIT = 700_000;

    address internal _heart;
    BurnerLoansYieldClaimer internal _claimer;

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

        _depositCollateral();
    }

    // Scenarios: EXEC-L03, EXEC-I01.
    function test_givenBurnerLoansDisabled_reportsFailureForEveryAsset() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);

        uint256 firstVaultBalanceBefore = vaultAsset.balanceOf(address(vault));
        uint256 firstTreasuryBalanceBefore = vaultAsset.balanceOf(address(trsry));
        uint256 laterVaultBalanceBefore = laterAsset.balanceOf(address(laterVault));
        uint256 laterTreasuryBalanceBefore = laterAsset.balanceOf(address(trsry));

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
            laterAsset.balanceOf(address(laterVault)),
            laterVaultBalanceBefore,
            "later vault balance"
        );
        assertEq(
            laterAsset.balanceOf(address(trsry)),
            laterTreasuryBalanceBefore,
            "later Treasury balance"
        );
    }

    function test_givenRecipientTransferFails_skipsAssetAndClaimsLaterAsset() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);

        uint256 failedClaimable = burnerLoans.previewClaimYield(address(vaultAsset)).amountOut;
        uint256 laterClaimable = burnerLoans.previewClaimYield(address(laterAsset)).amountOut;
        uint256 failedVaultBalanceBefore = vaultAsset.balanceOf(address(vault));
        uint256 failedCustodySharesBefore = vault.balanceOf(address(depositManager));
        uint256 firstTreasuryBefore = vaultAsset.balanceOf(address(trsry));
        uint256 laterTreasuryBefore = laterAsset.balanceOf(address(trsry));
        assertGt(failedClaimable, 0, "first asset has positive yield");
        assertGt(laterClaimable, 0, "later asset has positive yield");

        vm.mockCall(
            address(vaultAsset),
            abi.encodeWithSelector(vaultAsset.transfer.selector, address(trsry)),
            abi.encode(false)
        );
        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            address(vaultAsset),
            SafeERC20.SafeERC20FailedOperation.selector
        );
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            vaultAsset.balanceOf(address(vault)),
            failedVaultBalanceBefore,
            "failed vault assets roll back"
        );
        assertEq(
            vault.balanceOf(address(depositManager)),
            failedCustodySharesBefore,
            "failed custody shares roll back"
        );
        assertEq(
            vaultAsset.balanceOf(address(trsry)),
            firstTreasuryBefore,
            "failed recipient receives nothing"
        );
        assertEq(
            burnerLoans.previewClaimYield(address(vaultAsset)).amountOut,
            failedClaimable,
            "failed yield remains claimable"
        );
        assertEq(
            laterAsset.balanceOf(address(trsry)) - laterTreasuryBefore,
            laterClaimable,
            "later recipient receives exact previewed yield"
        );
        assertLt(
            burnerLoans.previewClaimYield(address(laterAsset)).amountOut,
            laterClaimable,
            "later yield is claimed"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(vaultAsset)),
            0,
            "failed yield creates no payout debt"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(laterAsset)),
            0,
            "successful yield creates no payout debt"
        );
        assertEq(
            vaultAsset.balanceOf(address(_claimer)),
            0,
            "claimer retains no first-asset custody"
        );
        assertEq(
            laterAsset.balanceOf(address(_claimer)),
            0,
            "claimer retains no later-asset custody"
        );
    }

    // Scenarios: EXEC-I02.
    function test_givenPeriodicTaskExceedsGasLimit_directClaimRemainsAvailable() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        laterAsset.mint(address(laterVault), 10e6);
        uint256 claimableBefore = burnerLoans
            .previewClaimYield(address(laterAsset))
            .requestedAssetAmount;

        vm.prank(admin);
        _claimer.setExecutionGasLimit(1);

        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        vm.prank(_heart);
        _claimer.execute();

        assertEq(
            burnerLoans.previewClaimYield(address(laterAsset)).requestedAssetAmount,
            claimableBefore,
            "periodic skip preserves claimable yield"
        );

        burnerLoans.claimYield(address(laterAsset));

        assertLt(
            burnerLoans.previewClaimYield(address(laterAsset)).requestedAssetAmount,
            claimableBefore,
            "manual claim reduces claimable yield"
        );
    }

    function _depositCollateral(MockERC20 asset_) internal {
        asset_.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        asset_.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(asset_), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast,calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
