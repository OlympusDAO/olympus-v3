// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Independent token amounts in callback proofs.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";

contract BurnerLoansPayoutSetGracePeriodCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-GRACE-C01.
    function test_givenOutgoingCallback_whenGraceSet_thenGuardRejects() public {
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_callbackToken));
        _callbackToken.mint(address(_payout), 5);
        _callbackToken.armOutgoing(
            address(_payout),
            _treasury(),
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(1))),
            false
        );
        uint32 grace = _payout.gracePeriod();
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 5, address(0), 0);
        _assertCallbackRejected();
        assertEq(_payout.gracePeriod(), grace, "Callback cannot change grace");
        assertEq(_callbackToken.balanceOf(_treasury()), 5, "Optional payment delivered once");
        (, , , , uint256 total) = _payout.pendingAmounts(address(_callbackToken));
        assertEq(total, 0, "Successful delivery leaves no liability");
    }

    // Scenarios: BLCU-GRACE-C02.
    function test_givenIncomingCallback_whenGraceSet_thenCoreGuardRejects() public {
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_callbackToken));
        _prepareIncoming(abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(1))), false);
        uint32 grace = _payout.gracePeriod();
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        _assertCallbackRejected();
        assertEq(_payout.gracePeriod(), grace, "Core callback cannot change grace");
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            100e18,
            "Outer receipt credited once"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
