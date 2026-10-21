// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Contracts
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
    error IntegrationClaimReverted();

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
    function test_givenBurnerLoansDisabled_skipsEveryAsset() public {
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

        vm.recordLogs();
        vm.prank(_heart);
        _claimer.execute();

        assertEq(vm.getRecordedLogs().length, 0, "disabled Burner Loans emits no task event");
        assertEq(_claimer.nextAssetIndex(), 0, "disabled Burner Loans preserves cursor");
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

    // Scenarios: EXEC-I03.
    function test_givenMultipleYieldAssets_boundedBeatsPayTreasuryAndResume() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);

        uint256 firstYield = burnerLoans.previewClaimYield(address(vaultAsset)).amountOut;
        uint256 laterYield = burnerLoans.previewClaimYield(address(laterAsset)).amountOut;
        uint256 firstTreasury = vaultAsset.balanceOf(address(trsry));
        uint256 laterTreasury = laterAsset.balanceOf(address(trsry));
        uint256 firstVault = vaultAsset.balanceOf(address(vault));
        uint256 laterVaultBalance = laterAsset.balanceOf(address(laterVault));
        uint256 count = burnerLoans.getAssetCount();
        assertGt(firstYield, 0, "first asset has accrued yield");
        assertGt(laterYield, 0, "later asset has accrued yield");

        // Each beat is capped at 1m outer gas and 700k task gas.
        // All amounts are in the collateral token's six-decimal scale.
        // Treasury gains exactly previewed yield; vault assets fall by the same amount.
        for (uint256 beat; beat < count; ++beat) {
            vm.prank(_heart);
            _claimer.execute{gas: 1_000_000}();
            assertLt(_claimer.nextAssetIndex(), count, "cursor remains in live registry");
        }

        assertEq(
            vaultAsset.balanceOf(address(trsry)) - firstTreasury,
            firstYield,
            "first Treasury receives previewed yield"
        );
        assertEq(
            laterAsset.balanceOf(address(trsry)) - laterTreasury,
            laterYield,
            "later Treasury receives previewed yield"
        );
        assertEq(
            firstVault - vaultAsset.balanceOf(address(vault)),
            firstYield,
            "first vault funds Treasury payout"
        );
        assertEq(
            laterVaultBalance - laterAsset.balanceOf(address(laterVault)),
            laterYield,
            "later vault funds Treasury payout"
        );
    }

    // Scenarios: EXEC-I04, EXEC-F01.
    function test_givenFirstClaimReverts_laterClaimPaysTreasuryInSameBeat() public {
        (MockERC20 laterAsset, MockERC4626 laterVault) = _addVaultAssetForTest();
        _depositCollateral(laterAsset);
        _addYield(10e6);
        laterAsset.mint(address(laterVault), 10e6);
        uint256 firstYield = burnerLoans.previewClaimYield(address(vaultAsset)).amountOut;
        uint256 laterYield = burnerLoans.previewClaimYield(address(laterAsset)).amountOut;
        uint256 firstTreasury = vaultAsset.balanceOf(address(trsry));
        uint256 laterTreasury = laterAsset.balanceOf(address(trsry));
        uint256 firstVault = vaultAsset.balanceOf(address(vault));
        uint256 laterVaultBalance = laterAsset.balanceOf(address(laterVault));

        vm.mockCallRevert(
            address(burnerLoans),
            abi.encodeCall(burnerLoans.claimYield, (address(vaultAsset))),
            abi.encodeWithSelector(IntegrationClaimReverted.selector)
        );
        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            address(vaultAsset),
            IntegrationClaimReverted.selector
        );
        vm.prank(_heart);
        _claimer.execute{gas: 1_000_000}();
        vm.clearMockedCalls();

        assertEq(
            vaultAsset.balanceOf(address(trsry)),
            firstTreasury,
            "failed claim leaves Treasury unchanged"
        );
        assertEq(
            vaultAsset.balanceOf(address(vault)),
            firstVault,
            "failed claim leaves vault unchanged"
        );
        assertEq(
            burnerLoans.previewClaimYield(address(vaultAsset)).amountOut,
            firstYield,
            "failed claim remains available"
        );
        // Six-decimal collateral: the later payout equals its pre-execution preview.
        assertEq(
            laterAsset.balanceOf(address(trsry)) - laterTreasury,
            laterYield,
            "later yield paid in same beat"
        );
        assertEq(
            laterVaultBalance - laterAsset.balanceOf(address(laterVault)),
            laterYield,
            "later vault funds exact payout"
        );
        assertEq(_claimer.nextAssetIndex(), 0, "complete traversal wraps cursor");
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
