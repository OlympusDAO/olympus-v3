// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Independent donation/payout and pending-key model for two rescue tokens.
contract DepositManagerRescueQueueHandler {
    // The deterministic Foundry cheat-code address takes the low 160 bits of its documented hash.
    // forge-lint: disable-next-line(unsafe-typecast)
    Vm internal constant _VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    DepositManager internal immutable _MANAGER;
    DepositManagerConfigTimelock internal immutable _TIMELOCK;
    Kernel internal immutable _KERNEL;
    address internal immutable _ADMIN;
    address internal immutable _EMERGENCY;
    address internal immutable _PROPOSER;
    address internal immutable _UNAUTHORIZED;
    MockERC20[2] internal _tokens;

    uint256[2] public donated;
    uint256[2] public received;
    uint64[2] public pending;
    uint48[2] public expectedMaturity;
    uint48[2] public expectedExpiry;
    bool[2] public managed;
    uint256 public authorizationViolations;
    uint256 public noticeViolations;
    uint256 public queueViolations;
    uint256 public unexpectedFailures;
    uint256 public successfulExecutions;
    bool public managerActive = true;
    bool public managerEnabled = true;
    bool public timelockActive = true;
    bool public timelockEnabled = true;
    bool public selected = true;

    constructor(
        DepositManager manager_,
        DepositManagerConfigTimelock timelock_,
        Kernel kernel_,
        MockERC20 first_,
        MockERC20 second_,
        address admin_,
        address emergency_,
        address proposer_,
        address unauthorized_
    ) {
        _MANAGER = manager_;
        _TIMELOCK = timelock_;
        _KERNEL = kernel_;
        _tokens = [first_, second_];
        _ADMIN = admin_;
        _EMERGENCY = emergency_;
        _PROPOSER = proposer_;
        _UNAUTHORIZED = unauthorized_;
    }

    function donate(uint8 tokenSeed_, uint128 amount_) external {
        uint256 index = tokenSeed_ % 2;
        _tokens[index].mint(address(_MANAGER), amount_);
        donated[index] += amount_;
    }

    function queue(uint8 tokenSeed_, bool admin_) external {
        uint256 index = tokenSeed_ % 2;
        bool expectedSuccess = timelockActive &&
            timelockEnabled &&
            managerActive &&
            selected &&
            !managed[index] &&
            pending[index] == 0;
        uint256 now_ = _VM.getBlockTimestamp();
        _VM.prank(admin_ ? _ADMIN : _PROPOSER);
        (bool success, bytes memory result) = address(_TIMELOCK).call(
            abi.encodeCall(IDepositManagerConfigTimelock.queueRescue, (address(_tokens[index])))
        );
        if (success) {
            if (!expectedSuccess) ++queueViolations;
            uint64 id = abi.decode(result, (uint64));
            pending[index] = id;
            // Handler clock increments are bounded; this model uses the fixed default one-day delay.
            expectedMaturity[index] = uint48(now_ + 1 days);
            expectedExpiry[index] = uint48(now_ + 4 days);
            ITimelockBatchQueue.QueuedAction memory action = _TIMELOCK.getQueuedAction(id);
            if (
                action.executableAt != expectedMaturity[index] ||
                action.expiresAt != expectedExpiry[index]
            ) ++queueViolations;
        } else if (expectedSuccess) {
            ++unexpectedFailures;
        }
    }

    function queueUnauthorized(uint8 tokenSeed_) external {
        _VM.prank(_UNAUTHORIZED);
        (bool success, ) = address(_TIMELOCK).call(
            abi.encodeCall(
                IDepositManagerConfigTimelock.queueRescue,
                (address(_tokens[tokenSeed_ % 2]))
            )
        );
        if (success) ++authorizationViolations;
    }

    function elapse(uint32 elapsed_) external {
        _VM.warp(_VM.getBlockTimestamp() + uint256(elapsed_ % uint32(7 days)));
    }

    function execute(uint8 tokenSeed_) external {
        uint256 index = tokenSeed_ % 2;
        uint64 id = pending[index];
        if (id == 0) return;
        uint256 now_ = _VM.getBlockTimestamp();
        bool expectedSuccess = timelockActive &&
            timelockEnabled &&
            managerActive &&
            selected &&
            !managed[index] &&
            now_ >= expectedMaturity[index] &&
            now_ <= expectedExpiry[index];
        uint256 expectedAmount = donated[index] - received[index];
        _VM.prank(_UNAUTHORIZED);
        (bool success, ) = address(_TIMELOCK).call(
            abi.encodeCall(_TIMELOCK.executeQueuedAction, (id))
        );
        if (success) {
            if (!expectedSuccess) ++noticeViolations;
            received[index] += expectedAmount;
            pending[index] = 0;
            ++successfulExecutions;
            _checkTerminal(id, index, true);
        } else if (expectedSuccess) {
            ++unexpectedFailures;
        }
    }

    function cancel(uint8 tokenSeed_) external {
        uint256 index = tokenSeed_ % 2;
        uint64 id = pending[index];
        if (id == 0) return;
        _VM.prank(_EMERGENCY);
        (bool success, ) = address(_TIMELOCK).call(
            abi.encodeCall(_TIMELOCK.cancelQueuedAction, (id))
        );
        if (success) {
            if (!timelockActive) ++queueViolations;
            pending[index] = 0;
            _checkTerminal(id, index, false);
        } else if (timelockActive) {
            ++unexpectedFailures;
        }
    }

    function rescueAdmin(uint8 tokenSeed_) external {
        uint256 index = tokenSeed_ % 2;
        bool expectedSuccess = managerActive && !managed[index];
        uint256 expectedAmount = donated[index] - received[index];
        _VM.prank(_ADMIN);
        (bool success, ) = address(_MANAGER).call(
            abi.encodeCall(_MANAGER.rescue, (address(_tokens[index])))
        );
        if (success) {
            if (!expectedSuccess) ++authorizationViolations;
            received[index] += expectedAmount;
        } else if (expectedSuccess) {
            ++unexpectedFailures;
        }
    }

    function rescueManagerDirect(uint8 tokenSeed_) external {
        _VM.prank(_PROPOSER);
        (bool success, ) = address(_MANAGER).call(
            abi.encodeCall(_MANAGER.rescue, (address(_tokens[tokenSeed_ % 2])))
        );
        if (success) ++authorizationViolations;
    }

    function toggleKernelActivity(bool targetManager_) external {
        bool next = targetManager_ ? !managerActive : !timelockActive;
        address target = targetManager_ ? address(_MANAGER) : address(_TIMELOCK);
        _VM.prank(_ADMIN);
        _KERNEL.executeAction(next ? Actions.ActivatePolicy : Actions.DeactivatePolicy, target);
        if (targetManager_) managerActive = next;
        else timelockActive = next;
    }

    function toggleLocalEnabled(bool targetManager_) external {
        bool enabled = targetManager_ ? managerEnabled : timelockEnabled;
        address target = targetManager_ ? address(_MANAGER) : address(_TIMELOCK);
        _VM.prank(enabled ? _EMERGENCY : _ADMIN);
        bytes memory data = enabled
            ? abi.encodeCall(IEnabler.disable, (bytes("")))
            : abi.encodeCall(IEnabler.enable, (bytes("")));
        (bool success, ) = target.call(data);
        if (success) {
            if (targetManager_) managerEnabled = !enabled;
            else timelockEnabled = !enabled;
        }
    }

    function rotateController(bool restore_) external {
        _VM.prank(_ADMIN);
        (bool success, ) = address(_MANAGER).call(
            abi.encodeCall(_MANAGER.setConfigOperator, (restore_ ? address(_TIMELOCK) : address(0)))
        );
        if (success) selected = restore_;
    }

    function onboard(uint8 tokenSeed_) external {
        uint256 index = tokenSeed_ % 2;
        if (managed[index]) return;
        _VM.prank(_ADMIN);
        (bool success, ) = address(_MANAGER).call(
            abi.encodeWithSignature(
                "addAsset(address,address,uint256,uint256)",
                address(_tokens[index]),
                address(0),
                type(uint256).max,
                uint256(0)
            )
        );
        if (success) managed[index] = true;
    }

    function key(uint256 index_) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(_MANAGER),
                    keccak256(
                        abi.encode(keccak256("DEPOSIT_MANAGER_RESCUE"), address(_tokens[index_]))
                    )
                )
            );
    }

    function token(uint256 index_) external view returns (MockERC20) {
        return _tokens[index_];
    }

    function _checkTerminal(uint64 id_, uint256 index_, bool executed_) private {
        ITimelockBatchQueue.QueuedAction memory action = _TIMELOCK.getQueuedAction(id_);
        if (
            action.executed != executed_ ||
            action.cancelled == executed_ ||
            action.actions.length != 0 ||
            _TIMELOCK.pendingActionId(key(index_)) != 0 ||
            _TIMELOCK.getQueuedConfigStateCount(id_, 0) != 0 ||
            _TIMELOCK.getQueuedConfigDestination(id_, 0) != address(0)
        ) ++queueViolations;
    }
}
