// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {DepositManagerConfigTimelockRescueTest} from "./fixtures/DepositManagerConfigTimelockRescueTest.sol";
import {DepositManagerRescueQueueHandler} from "./fixtures/DepositManagerRescueQueueHandler.sol";
import {StdInvariant} from "@forge-std-1.16.2/StdInvariant.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract DepositManagerConfigTimelockQueueRescueInvariantTest is
    StdInvariant,
    DepositManagerConfigTimelockRescueTest
{
    DepositManagerRescueQueueHandler internal _handler;
    bytes32 internal _initialCustody;

    function setUp() public override {
        super.setUp();
        _handler = new DepositManagerRescueQueueHandler(
            depositManager,
            _configTimelock,
            kernel,
            _rescueToken,
            _otherToken,
            ADMIN,
            EMERGENCY,
            DEPOSIT_MANAGER_ADMIN,
            makeAddr("unauthorized rescue handler actor")
        );
        _initialCustody = _targetState();
        // Guarantee a successful delayed payout before the arbitrary campaign, avoiding a vacuous model.
        _handler.donate(0, 1);
        _handler.queue(0, false);
        _handler.elapse(1 days);
        _handler.execute(0);
        targetContract(address(_handler));
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = _handler.donate.selector;
        selectors[1] = _handler.queue.selector;
        selectors[2] = _handler.queueUnauthorized.selector;
        selectors[3] = _handler.elapse.selector;
        selectors[4] = _handler.execute.selector;
        selectors[5] = _handler.cancel.selector;
        selectors[6] = _handler.rescueAdmin.selector;
        selectors[7] = _handler.rescueManagerDirect.selector;
        selectors[8] = _handler.toggleKernelActivity.selector;
        selectors[9] = _handler.toggleLocalEnabled.selector;
        selectors[10] = _handler.rotateController.selector;
        selectors[11] = _handler.onboard.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
    }

    // Scenarios: DMCT-RESCUE-P16.
    function invariant_rescueConservesCustodyAndPaysOnlyTreasury() public view {
        for (uint256 i; i < 2; ++i) {
            MockERC20 token_ = _handler.token(i);
            uint256 expectedReceived = _handler.received(i);
            assertEq(
                token_.balanceOf(address(trsry)),
                expectedReceived,
                "Treasury receipts equal independent payout model"
            );
            assertEq(
                token_.balanceOf(address(depositManager)),
                _handler.donated(i) - expectedReceived,
                "remaining custody equals donations less modeled payouts"
            );
            assertEq(
                token_.balanceOf(address(_configTimelock)),
                0,
                "timelock never holds rescued tokens"
            );
            assertEq(
                token_.totalSupply(),
                _handler.donated(i),
                "rescue never mints or burns tokens"
            );
        }
        assertEq(
            _targetState(),
            _initialCustody,
            "rescue sequences preserve managed positions and custody"
        );
    }

    // Scenarios: DMCT-RESCUE-P16.
    function invariant_pendingKeysFollowModeledOwnershipAndTerminalCleanup() public view {
        for (uint256 i; i < 2; ++i) {
            assertEq(
                _configTimelock.pendingActionId(_handler.key(i)),
                _handler.pending(i),
                "each token key has exactly its modeled pending owner"
            );
        }
        assertEq(
            _handler.queueViolations(),
            0,
            "queue admission and terminal cleanup remain valid"
        );
    }

    // Scenarios: DMCT-RESCUE-P16.
    function invariant_delegatedRecoveryRespectsAuthorityAndNotice() public view {
        assertEq(
            _handler.authorizationViolations(),
            0,
            "manager-only and unauthorized actors never rescue directly"
        );
        assertEq(
            _handler.noticeViolations(),
            0,
            "every delegated payout obeys maturity, expiry and current authority"
        );
        assertEq(_handler.unexpectedFailures(), 0, "otherwise valid rescue paths remain live");
        assertGt(
            _handler.successfulExecutions(),
            0,
            "campaign includes a successful delayed rescue"
        );
    }
}
