// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreAdmissionHandler} from "./fixtures/CoreAdmissionHandler.sol";

contract BurnerLoansCoreSetAuthorizationTest is BurnerLoansCoreTest {
    CoreAdmissionHandler internal _admissionHandler;
    bytes32 internal _admissionLedger;

    function setUp() public override {
        super.setUp();
        _deposit(2000e6);
        _borrow(100e9);
        _admissionLedger = _ledger();
        _admissionHandler = new CoreAdmissionHandler(_core, _kernel);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_admissionHandler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _admissionHandler.transition.selector;
        selectors[1] = _admissionHandler.grant.selector;
        selectors[2] = _admissionHandler.cancel.selector;
        selectors[3] = _admissionHandler.unauthorizedSettlement.selector;
        targetSelector(FuzzSelector(address(_admissionHandler), selectors));
        targetContract(address(_admissionHandler));
    }

    // Scenarios: BLCORE-AUTHORIZATION-I03, BLCORE-AUTHORIZATION-P01, BLCORE-AUTHORIZATION-P05.
    function test_givenValidDeadline_whenGranted(
        address account_,
        address operator_,
        uint48 now_,
        uint48 deadline_,
        uint256 nonce_
    ) public {
        vm.assume(account_ != operator_);
        nonce_ = bound(nonce_, 0, type(uint256).max - 1);
        vm.warp(now_);
        deadline_ = _bounds48(deadline_, now_, type(uint48).max);
        _setNonce(account_, nonce_);
        vm.expectEmit(true, true, true, true, address(_core));
        emit IOperatorAuth.AuthorizationSet(account_, account_, operator_, deadline_);
        vm.prank(account_);
        _core.setAuthorization(operator_, deadline_);
        assertEq(
            _core.authorizationDeadlines(account_, operator_),
            deadline_,
            "Exact inclusive deadline stored"
        );
        assertEq(_core.authorizationNonces(account_), nonce_ + 1, "One nonce consumed");
        assertTrue(_core.isSenderAuthorized(account_, account_), "Owner always authorized");
        assertTrue(_core.isSenderAuthorized(operator_, account_), "Grant effective immediately");
        vm.warp(deadline_);
        assertTrue(_core.isSenderAuthorized(operator_, account_), "Equality is authorized");
        vm.warp(uint256(deadline_) + 1);
        assertFalse(
            _core.isSenderAuthorized(operator_, account_),
            "One second after expiry is unauthorized"
        );
    }

    // Scenarios: BLCORE-AUTHORIZATION-I03, BLCORE-AUTHORIZATION-P05.
    function test_whenDeadlineBoundarySeeds() public {
        test_givenValidDeadline_whenGranted(address(0), _recipient, 0, 0, 0);
        test_givenValidDeadline_whenGranted(_borrower, address(0), 1, 1, type(uint256).max - 1);
        test_givenValidDeadline_whenGranted(
            _borrower,
            _recipient,
            type(uint48).max,
            type(uint48).max,
            17
        );
    }

    // Scenarios: BLCORE-AUTHORIZATION-I03.
    function test_givenExistingGrant_whenSameGrantRepeated() public {
        vm.startPrank(_borrower);
        _core.setAuthorization(_recipient, type(uint48).max);
        vm.expectEmit(true, true, true, true, address(_core));
        emit IOperatorAuth.AuthorizationSet(_borrower, _borrower, _recipient, type(uint48).max);
        _core.setAuthorization(_recipient, type(uint48).max);
        vm.stopPrank();
        assertEq(
            _core.authorizationNonces(_borrower),
            2,
            "Repeated grant invalidates previous signatures"
        );
    }

    // Scenarios: BLCORE-AUTHORIZATION-I02.
    function test_givenExpiredDeadline_whenGranted_reverts(
        address account_,
        address operator_,
        uint48 now_,
        uint48 deadline_
    ) public {
        vm.assume(account_ != operator_);
        now_ = _bounds48(now_, 1, type(uint48).max);
        deadline_ = _bounds48(deadline_, 0, now_ - 1);
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredAuthorization.selector,
                deadline_
            )
        );
        vm.prank(account_);
        _core.setAuthorization(operator_, deadline_);
        assertEq(_core.authorizationNonces(account_), 0, "Expired grant consumes no nonce");
    }

    // Scenarios: BLCORE-AUTHORIZATION-I02.
    function test_whenExpiredDeadlineBoundarySeeds_reverts() public {
        test_givenExpiredDeadline_whenGranted_reverts(_borrower, _recipient, 1, 0);
        test_givenExpiredDeadline_whenGranted_reverts(
            _borrower,
            _recipient,
            type(uint48).max,
            type(uint48).max - 1
        );
    }

    // Scenarios: BLCORE-AUTHORIZATION-I01.
    function test_givenSelfAndExpiredDeadline_whenGranted_reverts(address account_) public {
        vm.warp(1);
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfAuthorization.selector);
        vm.prank(account_);
        _core.setAuthorization(account_, 0);
        assertEq(
            _core.authorizationNonces(account_),
            0,
            "Self grant rejected before consuming nonce"
        );
    }

    // Scenarios: BLCORE-AUTHORIZATION-A01.
    function test_givenExhaustedNonce_whenGranted_reverts(address account_) public {
        vm.assume(account_ != _recipient);
        _setNonce(account_, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_NonceExhausted.selector, account_)
        );
        vm.prank(account_);
        _core.setAuthorization(_recipient, type(uint48).max);
        assertEq(
            _core.authorizationNonces(account_),
            type(uint256).max,
            "Exhausted nonce preserved"
        );
    }

    // Scenarios: BLCORE-AUTHORIZATION-L01, BLCORE-AUTHORIZATION-L02, BLCORE-AUTHORIZATION-L03.
    function test_givenUnavailableCore_whenGranted_reverts(
        address account_,
        bool active_,
        bool enabled_,
        bool invalid_
    ) public {
        vm.assume(account_ != _recipient);
        vm.assume(!active_ || !enabled_);
        vm.prank(account_);
        _core.setAuthorization(_recipient, type(uint48).max);
        _setCoreLifecycle(active_, enabled_);
        vm.recordLogs();
        vm.expectRevert(
            active_
                ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                : abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_core)
                )
        );
        vm.prank(account_);
        _core.setAuthorization(invalid_ ? account_ : _recipient, invalid_ ? 0 : type(uint48).max);
        assertEq(_core.authorizationNonces(account_), 1, "Rejected grant preserves nonce");
        assertEq(
            _core.authorizationDeadlines(account_, _recipient),
            type(uint48).max,
            "Existing grant preserved"
        );
        assertEq(vm.getRecordedLogs().length, 0, "No authorization log on rejection");
    }

    // Scenarios: BLCORE-AUTHORIZATION-L01, BLCORE-AUTHORIZATION-L02, BLCORE-AUTHORIZATION-L03, BLCORE-CANCEL-AUTH-P03, BLCORE-CANCEL-AUTH-P04, BLCORE-CANCEL-AUTH-P05, BLCORE-CANCEL-AUTH-P06, BLCORE-SETTLE-BORROW-A02.
    function invariant_lifecycleAuthorizationAndCustodyStayIndependent() public view {
        assertEq(
            _core.isActive(),
            _admissionHandler.expectedActive(),
            "Kernel activity matches transition model"
        );
        assertEq(
            _core.isEnabled(),
            _admissionHandler.expectedEnabled(),
            "Local flag matches independent transition model"
        );
        assertEq(
            _core.authorizationNonces(address(_admissionHandler)),
            _admissionHandler.expectedNonce(),
            "Only successful grant and cancellation consume nonce"
        );
        assertEq(
            _core.authorizationDeadlines(address(_admissionHandler), _admissionHandler.OPERATOR()),
            _admissionHandler.expectedDeadline(),
            "Only owner's grant/cancellation controls operator"
        );
        assertEq(
            _ledger(),
            _admissionLedger,
            "Governance admission and authorization sequences move no custody or principal"
        );
    }
}
