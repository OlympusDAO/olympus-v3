// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

/// @dev Selected-service boundary double. Ledger preparation is explicit test setup, not a migrator.
contract CoreService is Policy, IERC165, IEnabler, IVersioned {
    address internal _boundCore;
    address public ohm;
    address public configOperator;
    bool public override isEnabled = true;
    bytes4 public unsupportedInterface;
    bool public writeIdentity;
    uint256 public identityWrites;
    uint128 public activePrincipalOhm;
    uint128 public suppliedOhm;
    uint128 public suppliedIdleOhm;
    mapping(address => uint128) public providerClaims;

    constructor(Kernel kernel_, address core_, address ohm_, address operator_) Policy(kernel_) {
        _boundCore = core_;
        ohm = ohm_;
        configOperator = operator_;
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    function enable(bytes calldata) external override {
        isEnabled = true;
        emit Enabled();
    }

    function disable(bytes calldata) external override {
        isEnabled = false;
        emit Disabled();
    }

    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    function core() external returns (address) {
        if (writeIdentity) ++identityWrites;
        return _boundCore;
    }

    // Kept only to let tests reach current Core's legacy Inventory read and expose its removal gap.
    function facility() external view returns (address) {
        return _boundCore;
    }

    function setCore(address value_) external {
        _boundCore = value_;
    }

    function setOhm(address value_) external {
        ohm = value_;
    }

    function setConfigOperator(address value_) external {
        configOperator = value_;
    }

    function setUnsupportedInterface(bytes4 value_) external {
        unsupportedInterface = value_;
    }

    function setWriteIdentity(bool value_) external {
        writeIdentity = value_;
    }

    function setLedger(uint128 principal_, uint128 supplied_, uint128 idle_) external {
        activePrincipalOhm = principal_;
        suppliedOhm = supplied_;
        suppliedIdleOhm = idle_;
    }

    function setProviderClaim(address provider_, uint128 amount_) external {
        providerClaims[provider_] = amount_;
    }

    /// @dev Routes token callbacks through a genuinely activated and role-authorized policy.
    function forward(address target_, bytes calldata data_) external returns (bytes memory result) {
        (bool success, bytes memory returned) = target_.call(data_);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returned, 32), mload(returned))
            }
        }
        return returned;
    }

    function supportsInterface(bytes4 id_) external view override returns (bool) {
        if (id_ == unsupportedInterface) return false;
        return
            id_ == type(IERC165).interfaceId ||
            id_ == type(IEnabler).interfaceId ||
            id_ == type(IVersioned).interfaceId ||
            id_ == type(IBurnerLoansCoreBound).interfaceId ||
            id_ == type(IBurnerLoansRisk).interfaceId ||
            id_ == type(IBurnerLoansInventory).interfaceId ||
            id_ == type(IBurnerLoansPayout).interfaceId;
    }
}
