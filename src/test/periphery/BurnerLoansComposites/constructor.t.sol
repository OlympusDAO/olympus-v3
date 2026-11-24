// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";
import {MockCompositesMigrator} from "./fixtures/MockCompositesMigrator.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCompositesConstructorTest is BurnerLoansCompositesTest {
    // Scenarios: BLRECT-I11.
    function test_whenMigratorHasNoCode_reverts() public {
        _expectDependencyRejection(_borrower);
        IExecutor.Integrations memory integrations = _integrationConfig;
        integrations.migrator = _borrower;
        _constructWithIntegrations(integrations);
    }

    // Scenarios: BLRECT-I11.
    function test_whenMigratorGetterIsMalformed_reverts(bool dai_) public {
        address migrator = address(new MockCompositesMigrator(_asset, _ohm));
        bytes4 selector = dai_ ? IDaiUsdsMigrator.dai.selector : IDaiUsdsMigrator.usds.selector;
        vm.mockCall(migrator, abi.encodeWithSelector(selector), hex"01");
        _expectDependencyRejection(migrator);
        _constructWithMigrator(migrator);
    }

    // Scenarios: BLRECT-I12.
    function test_whenMigratorAssetsAreIdentical_reverts() public {
        address migrator = address(new MockCompositesMigrator(_asset, _asset));
        _expectDependencyRejection(migrator);
        _constructWithMigrator(migrator);
    }

    // Scenarios: BLRECT-I12.
    function test_whenMigratorAssetHasNoCode_reverts(bool dai_, bool zero_) public {
        MockERC20 invalid = MockERC20(zero_ ? address(0) : _borrower);
        address migrator = address(
            new MockCompositesMigrator(dai_ ? invalid : _asset, dai_ ? _ohm : invalid)
        );
        _expectDependencyRejection(migrator);
        _constructWithMigrator(migrator);
    }

    // Scenarios: BLRECT-I13.
    function test_whenAdapterHasNoCode_reverts() public {
        _expectDependencyRejection(_borrower);
        IExecutor.Integrations memory integrations = _integrationConfig;
        integrations.swapAdapter = _borrower;
        _constructWithIntegrations(integrations);
    }

    // Scenarios: BLRECT-I15.
    function test_whenAdapterDoesNotSupportSwapInterface_reverts() public {
        _expectDependencyRejection(address(_collateral));
        IExecutor.Integrations memory integrations = _integrationConfig;
        integrations.swapAdapter = address(_collateral);
        _constructWithIntegrations(integrations);
    }

    // Scenarios: BLRECT-I13.
    function test_whenLenderHasNoCode_reverts() public {
        _expectDependencyRejection(_borrower);
        IExecutor.Integrations memory integrations = _integrationConfig;
        integrations.flashLender = _borrower;
        _constructWithIntegrations(integrations);
    }

    // Scenarios: BLRECT-I14.
    function test_whenAnyIntegrationIsZero_reverts() public {
        IExecutor.Integrations memory integrations = _integrationConfig;
        _expectDependencyRejection(address(0));
        _constructWithIntegrations(
            IExecutor.Integrations(address(0), integrations.swapAdapter, integrations.flashLender)
        );
        _expectDependencyRejection(address(0));
        _constructWithIntegrations(
            IExecutor.Integrations(integrations.migrator, address(0), integrations.flashLender)
        );
        _expectDependencyRejection(address(0));
        _constructWithIntegrations(
            IExecutor.Integrations(integrations.migrator, integrations.swapAdapter, address(0))
        );
    }

    function _constructWithMigrator(address migrator_) private {
        IExecutor.Integrations memory integrations = _integrationConfig;
        integrations.migrator = migrator_;
        _constructWithIntegrations(integrations);
    }

    function _constructWithIntegrations(IExecutor.Integrations memory integrations_) private {
        new BurnerLoansComposites(
            address(_core),
            address(_collateral),
            address(_debt),
            address(this),
            integrations_
        );
    }

    // Scenarios: BLRECT-I06.
    function test_whenCoreDoesNotAdvertiseItsInterface_reverts() public {
        vm.mockCall(
            address(_core),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansCore).interfaceId)),
            abi.encode(false)
        );
        _expectDependencyRejection(address(_core));
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-I06.
    function test_whenCoreOhmGetterIsMalformed_reverts() public {
        vm.mockCall(address(_core), abi.encodeCall(IBurnerLoansCore.ohm, ()), hex"01");
        _expectDependencyRejection(address(_core));
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-I06.
    function test_whenCoreOhmHasNoCode_reverts(bool zero_) public {
        vm.mockCall(
            address(_core),
            abi.encodeCall(IBurnerLoansCore.ohm, ()),
            abi.encode(zero_ ? address(0) : _borrower)
        );
        _expectDependencyRejection(address(_core));
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-I01.
    function test_whenCoreHasNoCode_reverts(bool zero_) public {
        address candidate = zero_ ? address(0) : _borrower;
        _expectDependencyRejection(candidate);
        _construct(candidate, address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-I02.
    function test_whenCollateralHasNoCode_reverts(bool zero_) public {
        address candidate = zero_ ? address(0) : _borrower;
        _expectDependencyRejection(candidate);
        _construct(address(_core), candidate, address(_debt));
    }

    // Scenarios: BLRECT-I16.
    function test_whenDebtHasNoCode_reverts(bool zero_) public {
        address candidate = zero_ ? address(0) : _borrower;
        _expectDependencyRejection(candidate);
        _construct(address(_core), address(_collateral), candidate);
    }

    // Scenarios: BLRECT-I03, BLRECT-I07, BLRECT-I17.
    function test_whenActionDoesNotAdvertiseRequiredInterface_reverts(
        bool collateral_,
        bool missingCoreBound_
    ) public {
        address collateral = address(_collateral);
        address debt = address(_debt);
        address candidate;
        if (missingCoreBound_) {
            candidate = collateral_ ? collateral : debt;
            vm.mockCall(
                candidate,
                abi.encodeCall(
                    IERC165.supportsInterface,
                    (type(IBurnerLoansCoreBound).interfaceId)
                ),
                abi.encode(false)
            );
        } else if (collateral_) {
            candidate = debt;
            collateral = candidate;
        } else {
            candidate = collateral;
            debt = candidate;
        }
        _expectDependencyRejection(candidate);
        _construct(address(_core), collateral, debt);
    }

    // Scenarios: BLRECT-I07, BLRECT-I17.
    function test_whenActionCoreBindingGetterFails_reverts(bool collateral_) public {
        address candidate = collateral_ ? address(_collateral) : address(_debt);
        vm.mockCallRevert(candidate, abi.encodeCall(IBurnerLoansCoreBound.core, ()), hex"deadbeef");
        _expectDependencyRejection(candidate);
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-I05, BLRECT-I07, BLRECT-I09, BLRECT-I17.
    function test_whenActionCoreBindingIsMalformed_reverts(
        bool collateral_,
        bool noncanonical_
    ) public {
        address candidate = collateral_ ? address(_collateral) : address(_debt);
        bytes memory response = noncanonical_
            ? abi.encode(uint256(uint160(address(_core))) | (uint256(1) << 160))
            : abi.encodePacked(uint8(1));
        vm.mockCall(candidate, abi.encodeCall(IBurnerLoansCoreBound.core, ()), response);
        _expectDependencyRejection(candidate);
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-P02.
    function test_whenDependencyIsUnavailable(
        uint8 dependency_,
        bool paused_,
        address deployer_
    ) public {
        uint256 selector = dependency_ % 3;
        address dependency = selector == 0
            ? address(_core)
            : (selector == 1 ? address(_collateral) : address(_debt));
        if (paused_) IEnabler(dependency).disable("");
        else _kernel.executeAction(Actions.DeactivatePolicy, dependency);
        vm.prank(deployer_);
        BurnerLoansComposites created = _construct(
            address(_core),
            address(_collateral),
            address(_debt)
        );
        assertEq(created.owner(), address(this), "Caller can deploy with explicit owner");
        assertFalse(created.isEnabled(), "Construction leaves executor disabled");
    }

    function _construct(
        address core_,
        address collateral_,
        address debt_
    ) private returns (BurnerLoansComposites) {
        return
            new BurnerLoansComposites(core_, collateral_, debt_, address(this), _integrationConfig);
    }

    function _expectDependencyRejection(address dependency_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidDependency.selector,
                dependency_
            )
        );
    }

    // Scenarios: BLRECT-I04.
    function test_whenCollateralHasWrongCore_reverts() public {
        vm.mockCall(
            address(_collateral),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(_borrower)
        );
        _expectDependencyRejection(address(_collateral));
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-P01.
    function test_whenConstructed() public view {
        assertTrue(
            IERC165(address(_executor)).supportsInterface(type(IExecutor).interfaceId),
            "Executor advertises its API"
        );
        assertTrue(
            IERC165(address(_executor)).supportsInterface(type(IERC165).interfaceId),
            "Executor supports ERC165"
        );
        assertTrue(
            IERC165(address(_executor)).supportsInterface(type(IVersioned).interfaceId),
            "Executor advertises version discovery"
        );
        assertFalse(
            IERC165(address(_executor)).supportsInterface(0xffffffff),
            "Invalid interface is unsupported"
        );
        (uint8 major, uint8 minor) = IVersioned(address(_executor)).VERSION();
        assertEq(major, 1, "Initial API major version");
        assertEq(minor, 0, "Initial API minor version");
    }

    // Scenarios: BLRECT-I08.
    function test_whenDebtCoreGetterIsOversized_reverts() public {
        // A canonical first word with trailing bytes must not be accepted after bounded copying.
        vm.mockCall(
            address(_debt),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encodePacked(abi.encode(address(_core)), new bytes(4096))
        );
        _expectDependencyRejection(address(_debt));
        _construct(address(_core), address(_collateral), address(_debt));
    }

    // Scenarios: BLRECT-I10.
    function test_whenCoreOhmGetterFails_reverts() public {
        vm.mockCallRevert(address(_core), abi.encodeCall(IBurnerLoansCore.ohm, ()), hex"deadbeef");
        _expectDependencyRejection(address(_core));
        _construct(address(_core), address(_collateral), address(_debt));
    }
}
