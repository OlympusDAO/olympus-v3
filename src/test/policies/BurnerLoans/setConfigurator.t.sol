// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {Vm} from "forge-std/Vm.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {Actions, Module} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetConfiguratorTest is BurnerLoansTest {
    using SafeCast for uint256;

    struct MigrationSnapshot {
        bytes32 marketHash;
        bytes32 marketConfigHash;
        bytes32 positionHash;
        uint256 marketCollateral;
        uint128 marketPrincipalDue;
        uint256 marketInterestDue;
        uint256 marketPrincipalDefaulted;
        uint256 facilityPrincipalDue;
        bytes32 assetRegistryHash;
        bytes32 yieldRoutingHash;
        address inventoryConfigurator;
        bytes32 tokenBalancesHash;
    }

    function test_givenZeroAddress_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(0)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(0));
    }

    function test_givenNoCurrentConfigurator_whenCompatibleConfigurator() public {
        BurnerLoansHarness initialFacility = new BurnerLoansHarness(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            backingOracle
        );
        BurnerLoansConfig initialConfigurator = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(initialFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(initialConfigurator));
        initialConfigurator.setFacility(address(initialFacility));
        vm.expectEmit(true, false, false, true, address(initialFacility));
        emit IBurnerLoans.ConfiguratorSet(address(initialConfigurator));
        vm.recordLogs();
        initialFacility.setConfigurator(address(initialConfigurator));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        assertEq(
            initialFacility.configurator(),
            address(initialConfigurator),
            "initial configurator"
        );
        assertEq(logs.length, 1, "configurator-only event count");
    }

    function test_givenCurrentConfigurator_whenSameAddress() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.ConfiguratorSet(address(burnerLoansConfig));
        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator");
        assertEq(floan.getMarket(marketId).manager, address(burnerLoansConfig), "market manager");
        assertEq(logs.length, 1, "configurator-only event count");
    }

    function test_givenNoRegisteredAssets_whenCompatibleReplacement() public {
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _setConfigurator(replacement);

        assertEq(burnerLoans.configurator(), address(replacement), "replacement configurator");
    }

    function test_givenOneRegisteredAsset_whenCompatibleReplacement() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _setConfigurator(replacement);

        assertEq(burnerLoans.configurator(), address(replacement), "replacement configurator");
        assertEq(floan.getMarket(marketId).manager, address(replacement), "market manager");
    }

    function test_givenTwoRegisteredAssets_whenCompatibleReplacement() public {
        _addDefaultUsdsAsset();
        address secondAsset = address(_addDirectAssetForTest());
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = burnerLoansConfig.marketId(secondAsset);
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketManagerSet(
            firstMarketId,
            address(burnerLoansConfig),
            address(replacement)
        );
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketManagerSet(
            secondMarketId,
            address(burnerLoansConfig),
            address(replacement)
        );
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.ConfiguratorSet(address(replacement));
        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3, "migration event count");
        assertEq(burnerLoans.configurator(), address(replacement), "replacement configurator");
        assertEq(floan.getMarket(firstMarketId).manager, address(replacement), "first manager");
        assertEq(floan.getMarket(secondMarketId).manager, address(replacement), "second manager");
    }

    function test_givenRegisteredAssetWithoutMarket_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        _setMarketFacilityForTest(marketId, makeAddr("differentFacility"));
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator rollback");
    }

    function test_givenRegisteredAssetWithMultipleMarkets_whenCompatibleReplacement() public {
        _addDefaultUsdsAsset();
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _setConfigurator(replacement);

        assertEq(burnerLoans.configurator(), address(replacement), "replacement configurator");
        assertEq(floan.getMarket(firstMarketId).manager, address(replacement), "first manager");
        assertEq(floan.getMarket(secondMarketId).manager, address(replacement), "second manager");
    }

    function test_givenRegisteredAssetWithMultipleMarkets_givenLaterManagerDrift_reverts() public {
        _addDefaultUsdsAsset();
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();
        address unexpectedManager = makeAddr("unexpectedManager");
        _setMarketManagerForTest(secondMarketId, unexpectedManager);
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MarketManagerMismatch.selector,
                secondMarketId,
                address(burnerLoansConfig),
                unexpectedManager
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(
            floan.getMarket(firstMarketId).manager,
            address(burnerLoansConfig),
            "first manager rollback"
        );
        assertEq(floan.getMarket(secondMarketId).manager, unexpectedManager, "second manager");
        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator rollback");
    }

    function test_givenMarketManagerDrift_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        address unexpectedManager = makeAddr("unexpectedManager");
        _setMarketManagerForTest(marketId, unexpectedManager);
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MarketManagerMismatch.selector,
                marketId,
                address(burnerLoansConfig),
                unexpectedManager
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(floan.getMarket(marketId).manager, unexpectedManager, "drifted manager rollback");
        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator rollback");
    }

    function test_givenMarketAlreadyManagedByReplacement_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        BurnerLoansConfig replacement = _activateReplacementConfigurator();
        _setMarketManagerForTest(marketId, address(replacement));

        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MarketManagerMismatch.selector,
                marketId,
                address(burnerLoansConfig),
                address(replacement)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(floan.getMarket(marketId).manager, address(replacement), "existing manager");
        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator rollback");
    }

    function test_givenLaterMarketManagerDrift_reverts() public {
        _addDefaultUsdsAsset();
        address secondAsset = address(_addDirectAssetForTest());
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = burnerLoansConfig.marketId(secondAsset);
        address unexpectedManager = makeAddr("unexpectedManager");
        _setMarketManagerForTest(secondMarketId, unexpectedManager);
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MarketManagerMismatch.selector,
                secondMarketId,
                address(burnerLoansConfig),
                unexpectedManager
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(
            floan.getMarket(firstMarketId).manager,
            address(burnerLoansConfig),
            "first manager rollback"
        );
        assertEq(floan.getMarket(secondMarketId).manager, unexpectedManager, "second manager");
        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator rollback");
    }

    function test_givenFacilityLacksKernelPermission_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        BurnerLoansConfig replacement = _activateReplacementConfigurator();
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(burnerLoans))
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(
            floan.getMarket(marketId).manager,
            address(burnerLoansConfig),
            "market manager rollback"
        );
        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator rollback");
    }

    function test_givenPositionAndRouting_whenCompatibleReplacement_preservesState() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](1);
        routing.directAllocations[0] = IBurnerLoans.DirectYieldAllocation({
            recipient: makeAddr("directRecipient"),
            bps: 1_000
        });
        vm.prank(admin);
        burnerLoansConfig.setYieldAssetRouting(address(usds), routing);

        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 500e6,
                debtOhm: 100e9,
                maturity: (block.timestamp + 30 days).toUint48(),
                lastBorrowBlock: 0
            })
        );
        usds.mint(alice, 11e6);
        usds.mint(address(depositManager), 22e6);
        usds.mint(address(trsry), 33e6);
        uint64 positionId = floan.getPositionIdsForMarketAndBorrower(marketId, alice)[0].toUint64();
        MigrationSnapshot memory beforeMigration = _snapshotMigrationState(marketId, positionId);
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _setConfigurator(replacement);

        MigrationSnapshot memory afterMigration = _snapshotMigrationState(marketId, positionId);
        assertEq(floan.getMarket(marketId).manager, address(replacement), "market manager");
        _assertMigrationStatePreserved(beforeMigration, afterMigration);
    }

    function test_givenCompatibleConfiguratorInactive_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        BurnerLoansConfig replacement = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setFacility(address(burnerLoans));
        kernel.executeAction(Actions.DeactivatePolicy, address(replacement));
        burnerLoans.disable("");
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(replacement)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));

        assertEq(
            floan.getMarket(marketId).manager,
            address(burnerLoansConfig),
            "manager unchanged before replacement validation"
        );
    }

    function test_givenCurrentConfiguratorInactive_whenSameAddress_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));

        assertEq(
            floan.getMarket(marketId).manager,
            address(burnerLoansConfig),
            "same-address manager"
        );
        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "same-address pointer");
    }

    function test_givenActiveConfiguratorReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.mockCall(
            address(burnerLoansConfig),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenActiveConfiguratorKernelCallReverts_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.mockCallRevert(
            address(burnerLoansConfig),
            abi.encodeWithSignature("kernel()"),
            bytes("failure")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenConfiguratorAgreementMismatch_enableReverts() public {
        BurnerLoansConfig replacement = _activateReplacementConfigurator();
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.setConfigurator(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(inventory)
            )
        );
        burnerLoans.enable("");

        inventory.disable("");
        inventory.setConfigurator(address(replacement));
        inventory.enable("");
        burnerLoans.enable("");
        assertTrue(burnerLoans.isEnabled(), "Burner Loans enabled after Inventory migration");
        vm.stopPrank();
    }

    function _setConfigurator(BurnerLoansConfig replacement_) internal {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement_));
    }

    function _setMarketManagerForTest(uint32 marketId_, address manager_) internal {
        vm.prank(address(burnerLoans));
        floan.setMarketManager(marketId_, manager_);
    }

    function _snapshotMigrationState(
        uint32 marketId_,
        uint64 positionId_
    ) internal view returns (MigrationSnapshot memory snapshot) {
        IFLOANv1.Market memory market = floan.getMarket(marketId_);
        market.manager = address(0);
        snapshot.marketHash = keccak256(abi.encode(market));
        snapshot.marketConfigHash = keccak256(floan.getMarketConfigData(marketId_));
        snapshot.positionHash = keccak256(abi.encode(floan.getPosition(positionId_)));
        snapshot.marketCollateral = floan.getMarketCollateral(marketId_);
        snapshot.marketPrincipalDue = floan.getMarketPrincipalDue(marketId_);
        snapshot.marketInterestDue = floan.getMarketInterestDue(marketId_);
        snapshot.marketPrincipalDefaulted = floan.getMarketPrincipalDefaulted(marketId_);
        snapshot.facilityPrincipalDue = floan.getFacilityPrincipalDue(
            address(burnerLoans),
            address(ohm)
        );
        snapshot.assetRegistryHash = keccak256(
            abi.encode(burnerLoans.getAssetCount(), burnerLoans.getAssetAt(0))
        );
        snapshot.yieldRoutingHash = keccak256(
            abi.encode(burnerLoans.getYieldAssetRouting(address(usds)))
        );
        snapshot.inventoryConfigurator = inventory.configurator();
        snapshot.tokenBalancesHash = keccak256(
            abi.encode(
                usds.balanceOf(alice),
                usds.balanceOf(address(burnerLoans)),
                usds.balanceOf(address(depositManager)),
                usds.balanceOf(address(trsry)),
                ohm.balanceOf(alice),
                ohm.balanceOf(address(burnerLoans)),
                ohm.balanceOf(address(inventory))
            )
        );
    }

    function _assertMigrationStatePreserved(
        MigrationSnapshot memory before_,
        MigrationSnapshot memory after_
    ) internal pure {
        assertEq(after_.marketHash, before_.marketHash, "non-manager market fields");
        assertEq(after_.marketConfigHash, before_.marketConfigHash, "market config data");
        assertEq(after_.positionHash, before_.positionHash, "position");
        assertEq(after_.marketCollateral, before_.marketCollateral, "market collateral");
        assertEq(after_.marketPrincipalDue, before_.marketPrincipalDue, "market principal");
        assertEq(after_.marketInterestDue, before_.marketInterestDue, "market interest");
        assertEq(
            after_.marketPrincipalDefaulted,
            before_.marketPrincipalDefaulted,
            "market defaulted principal"
        );
        assertEq(after_.facilityPrincipalDue, before_.facilityPrincipalDue, "facility principal");
        assertEq(after_.assetRegistryHash, before_.assetRegistryHash, "asset registry");
        assertEq(after_.yieldRoutingHash, before_.yieldRoutingHash, "yield routing");
        assertEq(
            after_.inventoryConfigurator,
            before_.inventoryConfigurator,
            "Inventory configurator"
        );
        assertEq(after_.tokenBalancesHash, before_.tokenBalancesHash, "token balances");
    }
}
