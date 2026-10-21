// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test selectors and malformed ABI fixtures intentionally use bounded casts and literals.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

contract BurnerLoansConfigSetFacilityTest is BurnerLoansTest {
    bytes4 internal constant KERNEL_SELECTOR = bytes4(keccak256("kernel()"));

    BurnerLoansConfig internal unlinkedConfig;

    struct FacilitySnapshot {
        address facility;
        uint256 configBalance;
        uint256 facilityBalance;
        uint256 activeDebt;
        uint256 marketCount;
    }

    function setUp() public override {
        super.setUp();

        unlinkedConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(unlinkedConfig));
    }

    // Scenarios: LINK-P01
    function test_givenCompatibleEnabledFacility_whenAdminSetsFacility() public {
        _assertRequiredInterfaces(address(burnerLoans));
        FacilitySnapshot memory before_ = _snapshot(unlinkedConfig);

        vm.expectEmit(true, false, false, true, address(unlinkedConfig));
        emit IBurnerLoansConfig.FacilitySet(address(burnerLoans));
        vm.recordLogs();
        vm.prank(admin);
        unlinkedConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 1, "facility event count");
        assertEq(unlinkedConfig.facility(), address(burnerLoans), "facility pointer");
        _assertAccountingPreserved(before_, unlinkedConfig);
    }

    // Scenarios: LINK-P02
    function test_givenCompatibleDisabledFacility_whenAdminSetsFacility() public {
        vm.prank(admin);
        burnerLoans.disable("");
        FacilitySnapshot memory before_ = _snapshot(unlinkedConfig);

        vm.expectEmit(true, false, false, true, address(unlinkedConfig));
        emit IBurnerLoansConfig.FacilitySet(address(burnerLoans));
        vm.prank(admin);
        unlinkedConfig.setFacility(address(burnerLoans));

        assertEq(unlinkedConfig.facility(), address(burnerLoans), "disabled facility pointer");
        assertFalse(burnerLoans.isEnabled(), "candidate remains disabled");
        _assertAccountingPreserved(before_, unlinkedConfig);
    }

    // Scenarios: LINK-L01
    function test_givenConfigPolicyInactive_whenAdminSetsFacility_reverts() public {
        _deactivateConfig(address(unlinkedConfig));
        FacilitySnapshot memory before_ = _snapshot(unlinkedConfig);

        vm.recordLogs();
        vm.expectRevert(IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector);
        vm.prank(admin);
        unlinkedConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 0, "inactive config event count");
        _assertUnchanged(before_, unlinkedConfig);
    }

    // Scenarios: LINK-L02
    function test_givenConfigEnabled_whenAdminSetsFacility_reverts() public {
        FacilitySnapshot memory before_ = _snapshot(burnerLoansConfig);

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        burnerLoansConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 0, "enabled config event count");
        _assertUnchanged(before_, burnerLoansConfig);
    }

    // Scenarios: LINK-A01
    function test_givenConfigActiveAndDisabled_whenCallerIsNotAdmin_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != admin);
        FacilitySnapshot memory before_ = _snapshot(unlinkedConfig);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        unlinkedConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 0, "unauthorized event count");
        _assertUnchanged(before_, unlinkedConfig);
    }

    // Scenarios: LINK-A02
    function test_givenConfigInactiveAndDisabled_whenCallerIsNotAdmin_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != admin);
        _deactivateConfig(address(unlinkedConfig));
        FacilitySnapshot memory before_ = _snapshot(unlinkedConfig);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        unlinkedConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 0, "unauthorized inactive event count");
        _assertUnchanged(before_, unlinkedConfig);
    }

    // Scenarios: LINK-A03, LINK-A04
    function test_givenConfigEnabled_whenCallerIsNotAdmin_reverts(
        address caller_,
        bool policyActive_
    ) public {
        vm.assume(caller_ != admin);
        if (!policyActive_) _deactivateConfig(address(burnerLoansConfig));
        FacilitySnapshot memory before_ = _snapshot(burnerLoansConfig);

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        burnerLoansConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 0, "enabled unauthorized event count");
        _assertUnchanged(before_, burnerLoansConfig);
    }

    // Scenarios: LINK-I01
    function test_givenCandidateMissingLifecycleInterface_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        _mockInterface(address(candidate), type(IBurnerLoansLifecycle).interfaceId, false);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I02
    function test_givenCandidateMissingViewInterface_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        _mockInterface(address(candidate), type(IBurnerLoansView).interfaceId, false);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I03
    function test_givenCandidateMissingRescueInterface_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        _mockInterface(address(candidate), type(IBurnerLoansRescue).interfaceId, false);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I04
    function test_givenCompatibleCandidateKernelInactive_reverts() public {
        MockBurnerLoansPolicy candidate = new MockBurnerLoansPolicy(kernel, address(ohm));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I05
    function test_givenActiveCandidateReportsDifferentKernel_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        vm.mockCall(
            address(candidate),
            abi.encodeWithSelector(KERNEL_SELECTOR),
            abi.encode(makeAddr("otherKernel"))
        );
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I06
    function test_givenActiveCandidateKernelReadReverts_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        vm.mockCallRevert(
            address(candidate),
            abi.encodeWithSelector(KERNEL_SELECTOR),
            abi.encodeWithSignature("Error(string)", "kernel read failed")
        );
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I07
    function test_givenCandidateReportsDifferentOhm_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(makeAddr("otherOhm"));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I08
    function test_whenFacilityIsZero_reverts() public {
        _checkInvalidCandidate(address(0));
    }

    // Scenarios: LINK-I10
    function test_whenFacilityIsNonzeroEoa_reverts(address candidate_) public {
        vm.assume(candidate_ != address(0));
        vm.assume(candidate_.code.length == 0);
        _checkInvalidCandidate(candidate_);
    }

    // Scenarios: LINK-I09
    function test_givenFacilitySet_whenAdminSetsSameFacility_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        FacilitySnapshot memory before_ = _snapshot(burnerLoansConfig);

        vm.recordLogs();
        vm.expectRevert(IBurnerLoansConfig.BurnerLoansConfig_FacilityAlreadySet.selector);
        vm.prank(admin);
        burnerLoansConfig.setFacility(address(burnerLoans));

        assertEq(vm.getRecordedLogs().length, 0, "same facility event count");
        _assertUnchanged(before_, burnerLoansConfig);
    }

    // Scenarios: LINK-I11
    function test_givenFacilitySet_whenAdminSetsDifferentFacility_reverts() public {
        _addDefaultUsdsAsset();
        MockBurnerLoansPolicy replacement = _activeMockFacility(address(ohm));
        vm.prank(admin);
        burnerLoansConfig.disable("");
        FacilitySnapshot memory before_ = _snapshot(burnerLoansConfig);

        vm.recordLogs();
        vm.expectRevert(IBurnerLoansConfig.BurnerLoansConfig_FacilityAlreadySet.selector);
        vm.prank(admin);
        burnerLoansConfig.setFacility(address(replacement));

        assertEq(vm.getRecordedLogs().length, 0, "replacement facility event count");
        _assertUnchanged(before_, burnerLoansConfig);
    }

    // Scenarios: LINK-I12
    function test_givenCandidateSupportsInterfaceReverts_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        vm.mockCallRevert(
            address(candidate),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            abi.encodeWithSignature("Error(string)", "interface read failed")
        );
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I15
    function test_givenCandidateSupportsInterfaceMalformed_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        vm.mockCall(
            address(candidate),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            hex"01"
        );
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I13
    function test_givenCandidateOhmReadReverts_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        vm.mockCallRevert(
            address(candidate),
            abi.encodeWithSelector(IBurnerLoansView.ohm.selector),
            abi.encodeWithSignature("Error(string)", "OHM read failed")
        );
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: LINK-I14
    function test_givenCandidateOhmReadMalformed_reverts() public {
        MockBurnerLoansPolicy candidate = _activeMockFacility(address(ohm));
        vm.mockCall(
            address(candidate),
            abi.encodeWithSelector(IBurnerLoansView.ohm.selector),
            hex"01"
        );
        _checkInvalidCandidate(address(candidate));
    }

    function _activeMockFacility(address ohm_) internal returns (MockBurnerLoansPolicy candidate) {
        candidate = new MockBurnerLoansPolicy(kernel, ohm_);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(candidate));
    }

    function _mockInterface(address candidate_, bytes4 interfaceId_, bool supported_) internal {
        vm.mockCall(
            candidate_,
            abi.encodeCall(IERC165.supportsInterface, (interfaceId_)),
            abi.encode(supported_)
        );
    }

    function _checkInvalidCandidate(address candidate_) internal {
        FacilitySnapshot memory before_ = _snapshot(unlinkedConfig);
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                candidate_
            )
        );
        vm.prank(admin);
        unlinkedConfig.setFacility(candidate_);
        assertEq(vm.getRecordedLogs().length, 0, "invalid facility event count");
        _assertUnchanged(before_, unlinkedConfig);
        vm.clearMockedCalls();
    }

    function _deactivateConfig(address config_) internal {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, config_);
    }

    function _snapshot(
        BurnerLoansConfig config_
    ) internal view returns (FacilitySnapshot memory snapshot) {
        snapshot = FacilitySnapshot({
            facility: config_.facility(),
            configBalance: usds.balanceOf(address(config_)),
            facilityBalance: usds.balanceOf(address(burnerLoans)),
            activeDebt: burnerLoans.totalActiveDebtOhm(),
            marketCount: floan
                .getMarketIds(address(burnerLoans), address(usds), address(ohm))
                .length
        });
    }

    function _assertUnchanged(
        FacilitySnapshot memory before_,
        BurnerLoansConfig config_
    ) internal view {
        assertEq(config_.facility(), before_.facility, "facility pointer unchanged");
        _assertAccountingPreserved(before_, config_);
    }

    function _assertAccountingPreserved(
        FacilitySnapshot memory before_,
        BurnerLoansConfig config_
    ) internal view {
        assertEq(
            usds.balanceOf(address(config_)),
            before_.configBalance,
            "config balance unchanged"
        );
        assertEq(
            usds.balanceOf(address(burnerLoans)),
            before_.facilityBalance,
            "facility balance unchanged"
        );
        assertEq(burnerLoans.totalActiveDebtOhm(), before_.activeDebt, "active debt unchanged");
        assertEq(
            floan.getMarketIds(address(burnerLoans), address(usds), address(ohm)).length,
            before_.marketCount,
            "market count unchanged"
        );
    }

    function _assertRequiredInterfaces(address candidate_) internal view {
        assertTrue(
            IERC165(candidate_).supportsInterface(type(IBurnerLoansLifecycle).interfaceId),
            "lifecycle interface"
        );
        assertTrue(
            IERC165(candidate_).supportsInterface(type(IBurnerLoansView).interfaceId),
            "view interface"
        );
        assertTrue(
            IERC165(candidate_).supportsInterface(type(IBurnerLoansRescue).interfaceId),
            "rescue interface"
        );
    }
}
