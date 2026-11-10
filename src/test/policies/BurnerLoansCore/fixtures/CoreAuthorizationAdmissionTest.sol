// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "../BurnerLoansCoreTest.sol";
import {CoreAdmissionHandler} from "./CoreAdmissionHandler.sol";

abstract contract CoreAuthorizationAdmissionTest is BurnerLoansCoreTest {
    CoreAdmissionHandler internal _admissionHandler;
    bytes32 internal _admissionLedger;

    function setUp() public override {
        super.setUp();
        _deposit(2000e6);
        _borrow(100e9);
        _admissionLedger = _ledger();
        _admissionHandler = new CoreAdmissionHandler(_core, _kernel, _auth, address(_asset));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_admissionHandler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _admissionHandler.transition.selector;
        selectors[1] = _admissionHandler.grant.selector;
        selectors[2] = _admissionHandler.cancel.selector;
        selectors[3] = _admissionHandler.unauthorizedSettlement.selector;
        targetSelector(FuzzSelector(address(_admissionHandler), selectors));
        targetContract(address(_admissionHandler));
    }
}
