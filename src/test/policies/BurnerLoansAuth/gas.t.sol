// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansAuthTest} from "src/test/policies/BurnerLoansAuth/BurnerLoansAuthTest.sol";
import {Auth1271Wallet} from "src/test/policies/BurnerLoansAuth/fixtures/Auth1271Wallet.sol";

contract BurnerLoansAuthGasTest is BurnerLoansAuthTest {
    // Scenarios: BLAUTH-APPROVE-P03.
    function test_whenFirstTemporaryGrantAccepted_reportsGas() public {
        IOperatorAuth.Grant memory grant = _grant(15, false);
        vm.prank(_account);
        _auth.approveGrant(grant);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("Canonical320 temporary direct execution gas", used);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Measured acceptance consumed one pair epoch"
        );
    }

    // Scenarios: BLAUTH-APPROVE-P03.
    function test_whenFirstReusableGrantAccepted_reportsGas() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        vm.prank(_account);
        _auth.approveGrant(grant);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("Canonical320 reusable direct execution gas", used);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Measured acceptance consumed one pair epoch"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-P03.
    function test_whenEoaSignatureAccepted_reportsGas() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("Canonical320 EOA reusable signed execution gas", used);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Measured signature acceptance consumed one pair epoch"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-P03.
    function test_whenContractSignatureAccepted_reportsGas() public {
        Auth1271Wallet wallet = new Auth1271Wallet(_auth, _operator);
        IOperatorAuth.Grant memory grant = _grant(15, true);
        grant.account = address(wallet);
        grant.context = _auth.authorizationContext(address(wallet), _operator);
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", hex"1234");
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("Canonical320 malicious ERC1271 reusable signed execution gas", used);
        assertEq(
            _auth.pairEpochs(address(wallet), _operator),
            1,
            "Measured contract acceptance consumed one pair epoch"
        );
    }
}
