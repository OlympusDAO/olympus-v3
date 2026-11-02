// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "../DepositManagerConfigTimelockTest.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {PolicyLifecycleTest} from "src/test/policies/utils/PolicyLifecycleTest.sol";

abstract contract DepositManagerConfigTimelockLifecycleTest is
    DepositManagerConfigTimelockTest,
    PolicyLifecycleTest
{
    bytes32[] private _queueSlots;
    uint256 private _receiptId;

    function setUp() public virtual override {
        super.setUp();
        _lifecycleTarget = address(_configTimelock);
        _lifecycleKernel = kernel;
        _lifecycleRoles = roles;
        _lifecycleRolesAdmin = rolesAdmin;
        _lifecycleAdmin = ADMIN;
        _lifecycleExecutor = ADMIN;
        _lifecycleEmergency = EMERGENCY;
        _lifecycleSecondary = DEPOSIT_MANAGER_ADMIN;
        _lifecycleSecondaryRole = DEPOSIT_MANAGER_ADMIN_ROLE;
        _approveSpendingAsset(DEPOSITOR, 2e18);
        _deposit(2e18, false);
        _receiptId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.record();
        _queueDepositCap(iAsset, 42e18);
        (, _queueSlots) = vm.accesses(address(_configTimelock));
    }

    function _freshSubject(bool activate_) internal {
        _configTimelock = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );
        _lifecycleTarget = address(_configTimelock);
        if (activate_) _setMembership(true);
    }

    function _preservedState() internal view override returns (bytes32) {
        bytes32[] memory values = new bytes32[](_queueSlots.length);
        for (uint256 i; i < values.length; ++i)
            values[i] = vm.load(address(_configTimelock), _queueSlots[i]);
        bytes32 config = keccak256(
            abi.encode(
                _configTimelock.kernel(),
                _configTimelock.ROLES(),
                _configTimelock.depositManager(),
                _configTimelock.gracePeriod()
            )
        );
        bytes32 custody = keccak256(
            abi.encode(
                asset.balanceOf(address(depositManager)),
                asset.balanceOf(DEPOSITOR),
                asset.balanceOf(address(vault)),
                vault.balanceOf(address(depositManager)),
                vault.totalSupply(),
                asset.allowance(DEPOSITOR, address(depositManager)),
                receiptTokenManager.balanceOf(DEPOSITOR, _receiptId)
            )
        );
        bytes32 accounting = keccak256(
            abi.encode(
                depositManager.getAssetConfiguration(iAsset),
                depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR)
            )
        );
        return keccak256(abi.encode(config, custody, accounting, values));
    }
}
