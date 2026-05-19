// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {ILayerZeroEndpointV2, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZEndpointDelegate} from "src/policies/interfaces/ILZEndpointDelegate.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {ERC165} from "@openzeppelin-5.3.0/utils/introspection/ERC165.sol";
import {Kernel, Keycode, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title LZEndpointDelegate
/// @notice Thin policy that proxies LayerZero V2 OApp-authorized endpoint calls on behalf of a single
///         LZBridgeGateway. It is designed to act as the LayerZero V2 endpoint delegate
///         for an LZBridgeGateway.
/// @dev This contract holds no protocol state. Role checks gate every external function.
contract LZEndpointDelegate is
    ILZEndpointDelegate,
    ILZEndpointV2Authorized,
    IVersioned,
    ERC165,
    Policy,
    PolicyAdmin
{
    // ========= CONSTANTS ========= //

    /// @notice Pre-computed keycode for the ROLES module dependency.
    /// @dev Avoids the runtime cost of `toKeycode("ROLES")` at the call site.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524F4C4553); // toKeycode("ROLES")

    // ========= IMMUTABLES ========= //

    /// @inheritdoc ILZEndpointDelegate
    address public immutable override LZ_ENDPOINT;

    /// @inheritdoc ILZEndpointDelegate
    address public immutable override GATEWAY;

    // ========= MODIFIERS ========= //

    /// @notice Reverts if the caller does not hold the `bridge_configurator` role.
    /// @dev Gated solely by the role; the role is expected to be granted exclusively to
    ///      `LZBridgeAndDelegateConfig` (the timelock policy), in which case calls are
    ///      dispatched through that policy's timelock queue. Any holder that does not
    ///      itself enforce a timelock on these mutators should only be granted the role
    ///      temporarily for bootstrap.
    modifier onlyBridgeConfigurator() {
        _requireBridgeConfigurator();
        _;
    }

    /// @notice Reverts with `ROLESv1.ROLES_RequireRole(BRIDGE_CONFIGURATOR_ROLE)` if
    ///         `msg.sender` does not hold the `bridge_configurator` role.
    function _requireBridgeConfigurator() private view {
        if (!ROLES.hasRole(msg.sender, BRIDGE_CONFIGURATOR_ROLE))
            revert ROLESv1.ROLES_RequireRole(BRIDGE_CONFIGURATOR_ROLE);
    }

    /// @notice Reverts if the caller has neither the `bridge_admin` nor the `admin` role.
    /// @dev Gates the inbound-channel management primitives (`skip`, `nilify`, `burn`,
    ///      `clear`). These are intentionally NOT routed through the timelock policy so an
    ///      operator can react promptly to an undeliverable or malicious inbound message.
    modifier onlyBridgeAdminOrAdmin() {
        _requireBridgeAdminOrAdmin();
        _;
    }

    /// @notice Reverts with `PolicyAdmin.NotAuthorised` if `msg.sender` has neither the
    ///         `bridge_admin` nor the `admin` role.
    function _requireBridgeAdminOrAdmin() private view {
        if (!ROLES.hasRole(msg.sender, BRIDGE_ADMIN_ROLE) && !_isAdmin(msg.sender))
            revert PolicyAdmin.NotAuthorised();
    }

    // ========= INITIALIZATION & POLICY SETUP ========= //

    /// @dev Reverts if:
    ///      - The kernel address is the zero address.
    ///      - The gateway address is the zero address.
    ///      - The LZ endpoint reported by the specified gateway is the zero address.
    constructor(Kernel kernel_, address gateway_) Policy(kernel_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(gateway_, "gateway");

        address endpoint = ILZBridgeGateway(gateway_).LZ_ENDPOINT();
        _requireNonzeroAddress(endpoint, "lzEndpoint");

        GATEWAY = gateway_;
        LZ_ENDPOINT = endpoint;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = _KEYCODE_ROLES;

        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[0]));

        // Ensure the ROLES module is using the expected major version
        (uint8 major, ) = roles.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1, 1]));

        ROLES = roles;

        return dependencies;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========= LZ ENDPOINT CONFIG ========= //

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `setSendLibrary` function reverts.
    function setSendLibrary(uint32 eid_, address lib_) external override onlyBridgeConfigurator {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setSendLibrary(GATEWAY, eid_, lib_);
    }

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `setReceiveLibrary` function reverts.
    function setReceiveLibrary(
        uint32 eid_,
        address lib_,
        uint256 gracePeriod_
    ) external override onlyBridgeConfigurator {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setReceiveLibrary(GATEWAY, eid_, lib_, gracePeriod_);
    }

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `setReceiveLibraryTimeout` function reverts.
    function setReceiveLibraryTimeout(
        uint32 eid_,
        address lib_,
        uint256 expiry_
    ) external override onlyBridgeConfigurator {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setReceiveLibraryTimeout(GATEWAY, eid_, lib_, expiry_);
    }

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `setConfig` function reverts.
    function setEndpointConfig(
        address lib_,
        SetConfigParam[] calldata params_
    ) external override onlyBridgeConfigurator {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setConfig(GATEWAY, lib_, params_);
    }

    // ========= LZ MESSAGE MANAGEMENT ========= //

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev On the canonical chain, permanently discarding an inbound OHM mint message via skip
    ///      does NOT update the gateway's `bridgedSupply` or its MINTR mint approval. The caller
    ///      MUST follow up with a corresponding `LZBridgeGateway.decreaseBridgedSupply` call to
    ///      keep the bookkeeping consistent. Depending on the cause of the skip, a separate
    ///      governance proposal may also be required to restore the OHM owed to the affected user.
    ///
    ///      Reverts if:
    ///      - The caller has neither the `bridge_admin` nor the `admin` role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `skip` function reverts.
    function skip(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).skip(GATEWAY, srcEid_, sender_, nonce_);
    }

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev Reverts if:
    ///      - The caller has neither the `bridge_admin` nor the `admin` role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `nilify` function reverts.
    function nilify(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).nilify(GATEWAY, srcEid_, sender_, nonce_, payloadHash_);
    }

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev On the canonical chain, permanently discarding an inbound OHM mint message via burn
    ///      does NOT update the gateway's `bridgedSupply` or its MINTR mint approval. The caller
    ///      MUST follow up with a corresponding `LZBridgeGateway.decreaseBridgedSupply` call to
    ///      keep the bookkeeping consistent. Depending on the cause of the burn, a separate
    ///      governance proposal may also be required to restore the OHM owed to the affected user.
    ///
    ///      Reverts if:
    ///      - The caller has neither the `bridge_admin` nor the `admin` role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `burn` function reverts.
    function burn(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).burn(GATEWAY, srcEid_, sender_, nonce_, payloadHash_);
    }

    /// @inheritdoc ILZEndpointV2Authorized
    /// @dev On the canonical chain, clearing an inbound OHM mint message bypasses the gateway's
    ///      `lzReceive` handler, so `bridgedSupply` is not decremented and the MINTR mint approval
    ///      is not consumed. The caller MUST follow up with a corresponding
    ///      `LZBridgeGateway.decreaseBridgedSupply` call to keep the bookkeeping consistent.
    ///      Depending on the cause of the clear, a separate governance proposal may also be
    ///      required to restore the OHM owed to the affected user.
    ///
    ///      Reverts if:
    ///      - The caller has neither the `bridge_admin` nor the `admin` role.
    ///      - The gateway has not set this contract as its endpoint delegate.
    ///      - The LZ endpoint's `clear` function reverts.
    function clear(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).clear(GATEWAY, origin_, guid_, message_);
    }

    // ========= ERC165 ========= //

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId_ == type(ILZEndpointDelegate).interfaceId ||
            interfaceId_ == type(ILZEndpointV2Authorized).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ========= PRIVATE FUNCTIONS ========= //

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert Errors.BadInput(parameter_);
    }
}
