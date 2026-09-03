// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYieldRecipient} from "src/policies/interfaces/IYieldRecipient.sol";

contract MockYieldRecipient is Policy, IYieldRecipient, IEnabler {
    using EnumerableSet for EnumerableSet.AddressSet;

    error MockYieldRecipient_GetVaultConfigFailed();

    bool internal _enabled = true;
    bool internal _supportsEnablerInterface = true;
    bool internal _supportsYieldInterface = true;
    bool internal _revertGetVaultConfig;

    EnumerableSet.AddressSet internal _vaults;
    mapping(address vault => IYieldRecipient.VaultConfig) internal _vaultConfigs;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    function setEnabled(bool enabled_) external {
        _enabled = enabled_;
    }

    function setSupportsYieldInterface(bool supportsYieldInterface_) external {
        _supportsYieldInterface = supportsYieldInterface_;
    }

    function setSupportsEnablerInterface(bool supportsEnablerInterface_) external {
        _supportsEnablerInterface = supportsEnablerInterface_;
    }

    function setVaultConfig(address vault_, address asset_, bool enabled_) external {
        _vaults.add(vault_);
        _vaultConfigs[vault_] = IYieldRecipient.VaultConfig({
            vault: vault_,
            asset: asset_,
            enabled: enabled_
        });
    }

    function setReturnedVault(address lookupVault_, address returnedVault_) external {
        _vaultConfigs[lookupVault_].vault = returnedVault_;
    }

    function setRevertGetVaultConfig(bool shouldRevert_) external {
        _revertGetVaultConfig = shouldRevert_;
    }

    function isEnabled() external view override returns (bool) {
        return _enabled;
    }

    function enable(bytes calldata) external override {
        _enabled = true;
    }

    function disable(bytes calldata) external override {
        _enabled = false;
    }

    function supportsInterface(bytes4 interfaceId_) external view returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            (_supportsEnablerInterface && interfaceId_ == type(IEnabler).interfaceId) ||
            (_supportsYieldInterface && interfaceId_ == type(IYieldRecipient).interfaceId);
    }

    function getVaults() external view override returns (address[] memory vaults) {
        return _vaults.values();
    }

    function getVaultConfig(
        address vault_
    ) external view override returns (IYieldRecipient.VaultConfig memory config) {
        if (_revertGetVaultConfig) revert MockYieldRecipient_GetVaultConfigFailed();
        if (!_vaults.contains(vault_)) revert YieldRecipient_VaultNotRegistered(vault_);
        return _vaultConfigs[vault_];
    }
}
