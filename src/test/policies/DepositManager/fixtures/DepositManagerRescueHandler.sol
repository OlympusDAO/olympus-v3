// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Drives rescue alongside real deposits, withdrawals, borrowing and queue transitions.
/// @dev Both assets have fixed one-to-one custody conversion and no yield in this fixture.
contract DepositManagerRescueHandler is Test {
    DepositManager internal immutable _MANAGER;
    DepositManagerConfigTimelock internal immutable _TIMELOCK;
    Kernel internal immutable _KERNEL;
    address internal immutable _ADMIN;
    address internal immutable _EMERGENCY;
    address internal immutable _MANAGER_ADMIN;
    address internal immutable _TREASURY;
    address[2] internal _operators;
    MockERC20[2] internal _assets;
    MockERC20[2] internal _strayTokens;
    IERC20 internal immutable _SHARE_TOKEN;
    uint256[2][2] internal _principal;
    uint256[2][2] internal _borrowed;

    uint256 public violations;
    uint256 public successfulDirectRescues;
    uint256 public successfulQueuedRescues;
    uint64 public pendingAction;
    address public pendingToken;

    constructor(
        DepositManager manager_,
        DepositManagerConfigTimelock timelock_,
        Kernel kernel_,
        address admin_,
        address emergency_,
        address managerAdmin_,
        address treasury_,
        address[2] memory operators_,
        MockERC20[2] memory assets_,
        MockERC20[2] memory strayTokens_,
        IERC20 shareToken_
    ) {
        _MANAGER = manager_;
        _TIMELOCK = timelock_;
        _KERNEL = kernel_;
        _ADMIN = admin_;
        _EMERGENCY = emergency_;
        _MANAGER_ADMIN = managerAdmin_;
        _TREASURY = treasury_;
        _operators = operators_;
        _assets = assets_;
        _strayTokens = strayTokens_;
        _SHARE_TOKEN = shareToken_;
    }

    function deposit(uint8 assetSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 assetIndex = assetSeed_ % 2;
        uint256 operatorIndex = operatorSeed_ % 2;
        uint256 amount = bound(uint256(amountSeed_), 1, 1e18);
        MockERC20 token = _assets[assetIndex];
        address operator = _operators[operatorIndex];
        token.mint(operator, amount);
        vm.prank(operator);
        token.approve(address(_MANAGER), amount);
        vm.prank(operator);
        try
            _MANAGER.deposit(
                IDepositManager.DepositParams({
                    asset: IERC20(address(token)),
                    depositPeriod: 1,
                    depositor: operator,
                    amount: amount,
                    shouldWrap: false
                })
            )
        returns (uint256, uint256 credited) {
            if (credited != amount) ++violations;
            _principal[assetIndex][operatorIndex] += amount;
        } catch {}
    }

    function withdraw(uint8 assetSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 assetIndex = assetSeed_ % 2;
        uint256 operatorIndex = operatorSeed_ % 2;
        uint256 positionPrincipal = _principal[assetIndex][operatorIndex];
        if (positionPrincipal == 0 || _borrowed[assetIndex][operatorIndex] != 0) return;
        uint256 amount = bound(uint256(amountSeed_), 1, positionPrincipal);
        IERC20 token = IERC20(address(_assets[assetIndex]));
        address operator = _operators[operatorIndex];
        uint256 receiptId = _MANAGER.getReceiptTokenId(token, 1, operator);
        vm.prank(operator);
        _MANAGER.getReceiptTokenManager().approve(address(_MANAGER), receiptId, amount);
        vm.prank(operator);
        try
            _MANAGER.withdraw(
                IDepositManager.WithdrawParams({
                    asset: token,
                    depositPeriod: 1,
                    depositor: operator,
                    recipient: operator,
                    amount: amount,
                    isWrapped: false
                })
            )
        returns (uint256 actual) {
            if (actual != amount) ++violations;
            _principal[assetIndex][operatorIndex] -= amount;
        } catch {}
    }

    function borrow(uint8 assetSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 assetIndex = assetSeed_ % 2;
        uint256 operatorIndex = operatorSeed_ % 2;
        uint256 available = _principal[assetIndex][operatorIndex] -
            _borrowed[assetIndex][operatorIndex];
        if (available == 0) return;
        uint256 amount = bound(uint256(amountSeed_), 1, available);
        address operator = _operators[operatorIndex];
        vm.prank(operator);
        try
            _MANAGER.borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: IERC20(address(_assets[assetIndex])),
                    recipient: operator,
                    amount: amount
                })
            )
        returns (uint256 actual) {
            if (actual != amount) ++violations;
            _borrowed[assetIndex][operatorIndex] += amount;
        } catch {}
    }

    function repay(uint8 assetSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 assetIndex = assetSeed_ % 2;
        uint256 operatorIndex = operatorSeed_ % 2;
        uint256 debt = _borrowed[assetIndex][operatorIndex];
        if (debt == 0) return;
        uint256 amount = bound(uint256(amountSeed_), 1, debt);
        MockERC20 token = _assets[assetIndex];
        address operator = _operators[operatorIndex];
        token.mint(operator, amount);
        vm.prank(operator);
        token.approve(address(_MANAGER), amount);
        vm.prank(operator);
        try
            _MANAGER.borrowingRepay(
                IDepositManager.BorrowingRepayParams({
                    asset: IERC20(address(token)),
                    payer: operator,
                    amount: amount,
                    maxAmount: amount
                })
            )
        returns (uint256 actual) {
            if (actual != amount) ++violations;
            _borrowed[assetIndex][operatorIndex] -= amount;
        } catch {}
    }

    function donate(uint8 tokenSeed_, uint96 amountSeed_) external {
        _strayTokens[tokenSeed_ % 2].mint(address(_MANAGER), uint256(amountSeed_));
    }

    function rescue(uint8 callerSeed_, uint8 tokenSeed_, address viewer_) external {
        address token = _token(tokenSeed_);
        address selected = _MANAGER.configOperator();
        address delegatedActor = selected == address(_TIMELOCK) ? address(this) : selected;
        address caller = callerSeed_ % 3 == 0 ? _ADMIN : callerSeed_ % 3 == 1
            ? delegatedActor
            : _MANAGER_ADMIN;
        bool active = _KERNEL.isPolicyActive(Policy(address(_MANAGER)));
        bool eligible = tokenSeed_ % 4 < 2;
        bool authorized = caller == _ADMIN || (caller != address(0) && caller == selected);
        uint256 balance = IERC20(token).balanceOf(address(_MANAGER));
        uint256 treasuryBefore = IERC20(token).balanceOf(_TREASURY);
        bytes32 stateBefore = protectedState();
        vm.prank(viewer_);
        (bool quoted, bytes memory quote) = address(_MANAGER).staticcall(
            abi.encodeWithSignature("previewRescue(address)", token)
        );
        if (quoted != (active && eligible)) ++violations;
        if (quoted && abi.decode(quote, (uint256)) != balance) ++violations;
        if (protectedState() != stateBefore) ++violations;
        vm.prank(caller);
        (bool succeeded, ) = address(_MANAGER).call(
            abi.encodeWithSignature("rescue(address)", token)
        );
        if (succeeded != (active && eligible && authorized)) ++violations;
        if (succeeded) {
            if (IERC20(token).balanceOf(address(_MANAGER)) != 0) ++violations;
            if (IERC20(token).balanceOf(_TREASURY) - treasuryBefore != balance) ++violations;
            ++successfulDirectRescues;
        }
        if (protectedState() != stateBefore) ++violations;
    }

    function queueRescue(uint8 tokenSeed_) external {
        address token = address(_strayTokens[tokenSeed_ % 2]);
        bytes32 beforeState = protectedState();
        vm.prank(_MANAGER_ADMIN);
        (bool succeeded, bytes memory result) = address(_TIMELOCK).call(
            abi.encodeWithSignature("queueRescue(address)", token)
        );
        if (succeeded) {
            pendingAction = abi.decode(result, (uint64));
            pendingToken = token;
        }
        if (protectedState() != beforeState) ++violations;
    }

    function executeRescue() external {
        if (pendingAction == 0) return;
        uint256 balance = IERC20(pendingToken).balanceOf(address(_MANAGER));
        uint256 treasuryBefore = IERC20(pendingToken).balanceOf(_TREASURY);
        bytes32 beforeState = protectedState();
        uint256 ready = uint256(_TIMELOCK.getQueuedAction(pendingAction).executableAt);
        if (vm.getBlockTimestamp() < ready) vm.warp(ready);
        try _TIMELOCK.executeQueuedAction(pendingAction) {
            if (IERC20(pendingToken).balanceOf(address(_MANAGER)) != 0) ++violations;
            if (IERC20(pendingToken).balanceOf(_TREASURY) - treasuryBefore != balance) ++violations;
            ++successfulQueuedRescues;
            pendingAction = 0;
        } catch {}
        if (protectedState() != beforeState) ++violations;
    }

    function cancelRescue() external {
        if (pendingAction == 0) return;
        bytes32 beforeState = protectedState();
        vm.prank(_EMERGENCY);
        try _TIMELOCK.cancelQueuedAction(pendingAction) {
            pendingAction = 0;
        } catch {}
        if (protectedState() != beforeState) ++violations;
    }

    function setPolicyActive(bool active_) external {
        bool current = _KERNEL.isPolicyActive(Policy(address(_MANAGER)));
        if (current == active_) return;
        vm.prank(_ADMIN);
        _KERNEL.executeAction(
            active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
            address(_MANAGER)
        );
    }

    function setEnabled(bool enabled_) external {
        if (_MANAGER.isEnabled() == enabled_) return;
        vm.prank(enabled_ ? _ADMIN : _EMERGENCY);
        (bool success, ) = address(_MANAGER).call(
            enabled_
                ? abi.encodeCall(IEnabler.enable, (bytes("")))
                : abi.encodeCall(IEnabler.disable, (bytes("")))
        );
        if (success && _MANAGER.isEnabled() != enabled_) ++violations;
    }

    function setController(bool timelockSelected_) external {
        address selected = timelockSelected_ ? address(_TIMELOCK) : address(this);
        if (_MANAGER.configOperator() == selected) return;
        vm.prank(_ADMIN);
        try _MANAGER.setConfigOperator(selected) {} catch {}
    }

    function toggleRoute(uint8 assetSeed_, uint8 operatorSeed_) external {
        IERC20 token = IERC20(address(_assets[assetSeed_ % 2]));
        address operator = _operators[operatorSeed_ % 2];
        bool enabled = _MANAGER.isAssetPeriod(token, 1, operator).isEnabled;
        vm.prank(_ADMIN);
        (bool success, ) = address(_MANAGER).call(
            enabled
                ? abi.encodeCall(IDepositManager.disableAssetPeriod, (token, uint8(1), operator))
                : abi.encodeCall(IDepositManager.enableAssetPeriod, (token, uint8(1), operator))
        );
        if (success && _MANAGER.isAssetPeriod(token, 1, operator).isEnabled == enabled)
            ++violations;
    }

    function principal(
        uint256 assetIndex_,
        uint256 operatorIndex_
    ) external view returns (uint256) {
        return _principal[assetIndex_][operatorIndex_];
    }

    function borrowed(uint256 assetIndex_, uint256 operatorIndex_) external view returns (uint256) {
        return _borrowed[assetIndex_][operatorIndex_];
    }

    function protectedState() public view returns (bytes32 state) {
        for (uint256 a; a < 2; ++a) {
            IERC20 token = IERC20(address(_assets[a]));
            state = keccak256(
                abi.encode(
                    state,
                    token.balanceOf(address(_MANAGER)),
                    _MANAGER.getAssetDepositCapStatus(token)
                )
            );
            for (uint256 o; o < 2; ++o) {
                (uint256 shares, uint256 assets) = _MANAGER.getOperatorAssets(token, _operators[o]);
                uint256 id = _MANAGER.getReceiptTokenId(token, 1, _operators[o]);
                state = keccak256(
                    abi.encode(
                        state,
                        shares,
                        assets,
                        _MANAGER.getOperatorLiabilities(token, _operators[o]),
                        _MANAGER.getBorrowedAmount(token, _operators[o]),
                        _MANAGER.getReceiptTokenManager().balanceOf(_operators[o], id)
                    )
                );
            }
        }
        return keccak256(abi.encode(state, _SHARE_TOKEN.balanceOf(address(_MANAGER))));
    }

    function _token(uint8 seed_) private view returns (address) {
        uint256 index = seed_ % 4;
        if (index < 2) return address(_strayTokens[index]);
        return index == 2 ? address(_assets[0]) : address(_SHARE_TOKEN);
    }
}
