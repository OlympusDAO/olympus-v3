// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerTest} from "../DepositManagerTest.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {PolicyLifecycleTest} from "src/test/policies/utils/PolicyLifecycleTest.sol";

abstract contract DepositManagerLifecycleTest is DepositManagerTest, PolicyLifecycleTest {
    bytes32[] private _dataSlots;
    uint256 private _receiptId;

    modifier givenReEnableCaller(
        address caller_,
        bool admin_,
        bool secondary_
    ) {
        vm.assume(admin_ || secondary_);
        if (admin_) _grantLifecycleRole(ADMIN_ROLE, caller_);
        if (secondary_) _grantLifecycleRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _;
    }

    function setUp() public virtual override {
        super.setUp();
        _lifecycleTarget = address(depositManager);
        _lifecycleKernel = kernel;
        _lifecycleRoles = roles;
        _lifecycleRolesAdmin = rolesAdmin;
        _lifecycleAdmin = ADMIN;
        _lifecycleExecutor = ADMIN;
        _lifecycleEmergency = EMERGENCY;
        _lifecycleSecondary = DEPOSIT_MANAGER_ADMIN;
        _lifecycleSecondaryRole = DEPOSIT_MANAGER_ADMIN_ROLE;
        vm.prank(ADMIN);
        depositManager.enable("");
        vm.record();
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "lc1");
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _approveSpendingAsset(DEPOSITOR, 2e18);
        _deposit(2e18, false);
        (, _dataSlots) = vm.accesses(address(depositManager));
        _receiptId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function _freshSubject(bool activate_) internal {
        depositManager = new DepositManager(address(kernel), address(receiptTokenManager));
        _lifecycleTarget = address(depositManager);
        if (activate_) _setMembership(true);
    }

    function _preservedState() internal view override returns (bytes32) {
        bytes32[] memory values = new bytes32[](_dataSlots.length);
        for (uint256 i; i < values.length; ++i)
            values[i] = vm.load(address(depositManager), _dataSlots[i]);
        bytes32 config = keccak256(
            abi.encode(
                depositManager.kernel(),
                depositManager.ROLES(),
                depositManager.getReceiptTokenManager(),
                depositManager.configOperator(),
                depositManager.gracePeriod()
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
        return keccak256(abi.encode(config, custody, values));
    }
}
