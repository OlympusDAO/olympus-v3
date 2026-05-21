// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

/// Peer management, endpoint send/receive, and enforced-option logic ported from
/// `@layerzerolabs/oapp-evm` v0.4.1 (OAppCore, OAppSender, OAppReceiver, OAppOptionsType3).
/// Reimplemented inline rather than inherited because those contracts assume OZ Ownable,
/// which is incompatible with the Bophades Kernel RBAC model.
/// Bidirectional rate limiting is provided by the in-repo `OffsettingRateLimiter`
/// (src/bases/) which tracks independent outbound and inbound limits per EID and
/// offsets activity in one direction against the in-flight amount of the other. Limits
/// are mandatory: every configured peer must have both directions configured before
/// traffic is allowed.
///
/// Ported logic (~ = identical, -> = differs):
///
///   OAppCore:         peers, setPeer(), _getPeerOrRevert(), setDelegate() ~
///                     -> Endpoint stored as `address`, cast at each call site.
///   OAppReceiver:     lzReceive(), allowInitializePath(), nextNonce() ~
///                     -> Routes via _decodeAndRoute() instead of virtual _lzReceive().
///   OAppSender:       estimateSendFee() <- _quote(); burnAndSend() <- _lzSend()
///                     -> msg.value forwarded directly; no _payNative()/_payLzToken().
///   OAppOptionsType3: enforcedOptions, setEnforcedOptions(), _combineOptions() ~
///                     -> _assertOptionsType3 accepts calldata only (memory variant unused).
///
/// Not ported: oAppVersion() (-> IVersioned), isComposeMsgSender(), _payNative()/_payLzToken().
/// Access control: onlyOwner -> the ROLES module.

// Interfaces
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroReceiver.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {OffsettingRateLimiter} from "src/bases/OffsettingRateLimiter.sol";
import {ReEnabler} from "src/bases/ReEnabler.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyReEnabler} from "src/policies/utils/PolicyReEnabler.sol";
import {Rescueable} from "src/bases/Rescueable.sol";
import {BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE, BRIDGE_FACILITATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title LZBridgeGateway
/// @notice Infrastructure policy handling LayerZero V2 endpoint communication for cross-chain
///         OHM transfers.
///         Performs OHM mint/burn via MINTR, manages peers, enforces options and rate limits,
///         tracks bridged supply on canonical chains, and bounds inflow minting to previously burned OHM via mint approval.
///         OApp-authorized endpoint operations (libraries, ULN/Executor config, messaging channel control)
///         live on the LZEndpointDelegate policy, which is assigned via `setDelegate`.
contract LZBridgeGateway is
    ILayerZeroReceiver,
    IVersioned,
    ILZBridgeGateway,
    Policy,
    PolicyReEnabler,
    ReEnablerGracePeriod,
    OffsettingRateLimiter,
    Rescueable
{
    // ========= CONSTANTS ========= //

    /// @inheritdoc ILZBridgeGateway
    uint8 public constant override MSG_BRIDGE_OHM = 1;

    /// @notice Expected byte length of an ABI-encoded (address, uint256) bridge payload.
    uint256 internal constant _BRIDGE_OHM_DATA_LENGTH = 64;

    /// @notice Minimum ABI-encoded length for (uint8, bytes): 32 + 32 offset + 32 length.
    uint256 internal constant _MIN_PAYLOAD_LENGTH = 96;

    /// @notice Type 3 option type identifier.
    uint16 internal constant _OPTION_TYPE_3 = 3;

    /// @notice Keycode for the MINTR module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("MINTR")`.
    Keycode internal constant _KEYCODE_MINTR = Keycode.wrap(0x4D494E5452); // toKeycode("MINTR")

    /// @notice Keycode for the ROLES module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("ROLES")`.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524F4C4553); // toKeycode("ROLES")

    // ========= MODIFIERS ========= //

    /// @notice Modifier that reverts if the caller does not have the `bridge_admin` or `admin` role.
    /// @dev Used only by the one-shot `initializeBridgedSupply`; the other privileged mutators
    ///      are gated by `onlyBridgeConfigurator`.
    modifier onlyBridgeAdminOrAdmin() {
        _requireBridgeAdminOrAdmin();
        _;
    }

    /// @notice Reverts with `IPolicyAdmin.NotAuthorised` if `msg.sender` has neither the
    ///         `bridge_admin` nor the `admin` role.
    function _requireBridgeAdminOrAdmin() private view {
        _requireAuthorized(!_hasRole(msg.sender, BRIDGE_ADMIN_ROLE) && !_isAdmin(msg.sender));
    }

    /// @notice Modifier that reverts if the caller does not have the `bridge_configurator` role.
    /// @dev Gated solely by the role; the role is expected to be granted exclusively to
    ///      `LZBridgeAndDelegateConfig` (the timelock policy), in which case calls are
    ///      dispatched through that policy's timelock queue. Any holder that does not
    ///      itself enforce a timelock on these mutators should only be granted the role
    ///      temporarily for bootstrap. This contract does not enforce a timelock itself;
    ///      it is enforced only by the `LZBridgeAndDelegateConfig` role holder. Granting
    ///      `bridge_configurator` to any other address bypasses the timelock for these
    ///      mutators.
    modifier onlyBridgeConfigurator() {
        _requireBridgeConfigurator();
        _;
    }

    /// @notice Reverts with `ROLESv1.ROLES_RequireRole(BRIDGE_CONFIGURATOR_ROLE)` if
    ///         `msg.sender` does not hold the `bridge_configurator` role.
    function _requireBridgeConfigurator() private view {
        _requireRole(msg.sender, BRIDGE_CONFIGURATOR_ROLE);
    }

    // ========= IMMUTABLES ========= //

    /// @inheritdoc ILZBridgeGateway
    address public immutable override LZ_ENDPOINT;

    /// @inheritdoc ILZBridgeGateway
    bool public immutable override IS_CANONICAL;

    // ========= STATE ========= //

    /// @notice Bophades module for minting and burning OHM.
    MINTRv1 public MINTR;

    /// @inheritdoc ILZBridgeGateway
    address public override ohm;

    /// @inheritdoc ILZBridgeGateway
    uint256 public override bridgedSupply;

    /// @inheritdoc ILZBridgeGateway
    bool public override bridgedSupplyInitialized;

    /// @inheritdoc ILZBridgeGateway
    bool public override isReceiveEnabled;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint32 eid_ => bytes32) public override peers;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint32 eid_ => mapping(uint16 msgType_ => bytes)) public override enforcedOptions;

    // ========= INITIALIZATION & POLICY SETUP ========= //

    /// @dev Reverts if:
    ///      - The kernel address is the zero address.
    ///      - The LZ endpoint address is the zero address.
    ///      - The grace window length is zero.
    constructor(
        Kernel kernel_,
        address lzEndpoint_,
        bool isCanonical_,
        uint32 grace_
    ) Policy(kernel_) ReEnablerGracePeriod(grace_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(lzEndpoint_, "lzEndpoint");

        LZ_ENDPOINT = lzEndpoint_;
        IS_CANONICAL = isCanonical_;

        // EnablerV2 starts disabled; the gateway must be explicitly enabled after
        // configuration.
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = _KEYCODE_MINTR;
        dependencies[1] = _KEYCODE_ROLES;

        MINTRv1 mintr = MINTRv1(getModuleAddress(dependencies[0]));
        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[1]));

        // Ensure modules are using the expected major version
        (uint8 major, ) = mintr.VERSION();
        _requireMajorV1(major);
        (major, ) = roles.VERSION();
        _requireMajorV1(major);

        MINTR = mintr;
        ROLES = roles;

        // Set OHM from MINTR
        ohm = address(mintr.ohm());

        return dependencies;
    }

    /// @notice Reverts with `Policy_WrongModuleVersion` if the given module major version is
    ///         not 1.
    /// @param  major_ The major version reported by the module's `VERSION()`.
    function _requireMajorV1(uint8 major_) private pure {
        if (major_ != 1) revert Policy_WrongModuleVersion(abi.encode([1, 1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](4);
        Keycode kc = MINTR.KEYCODE();
        permissions[0] = Permissions({keycode: kc, funcSelector: MINTRv1.mintOhm.selector});
        permissions[1] = Permissions({keycode: kc, funcSelector: MINTRv1.burnOhm.selector});
        permissions[2] = Permissions({
            keycode: kc,
            funcSelector: MINTRv1.increaseMintApproval.selector
        });
        permissions[3] = Permissions({
            keycode: kc,
            funcSelector: MINTRv1.decreaseMintApproval.selector
        });
        return permissions;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========= POLICY ENABLER ========= //

    /// @dev Sets isReceiveEnabled to true when the gateway is enabled.
    function _beforeEnable(bytes calldata) internal override {
        _enableReceive();
    }

    /// @dev Resets isReceiveEnabled to false if it is not already when the gateway is disabled.
    function _beforeDisable(bytes calldata) internal override {
        if (isReceiveEnabled) _setIsReceiveEnabled(false);
    }

    /// @dev Restores isReceiveEnabled when the manager re-enables the gateway. The grace
    ///      check is inherited from `ReEnablerGracePeriod` via `super`.
    function _beforeReEnable() internal override(ReEnabler, ReEnablerGracePeriod) {
        super._beforeReEnable();
        _enableReceive();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Restricts `setGracePeriod` to the `bridge_configurator` role; that role is
    ///      expected to be granted exclusively to `LZBridgeAndDelegateConfig` (the
    ///      timelock policy).
    function _authorizeSetGracePeriod() internal view override {
        _requireBridgeConfigurator();
    }

    /// @notice Sets isReceiveEnabled to true if it is not already.
    /// @dev Shared between `_beforeEnable` and `_beforeReEnable` because both
    ///      transitions move the gateway into the enabled state with receiving allowed.
    function _enableReceive() private {
        if (!isReceiveEnabled) _setIsReceiveEnabled(true);
    }

    // ========= OHM BRIDGING ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the `bridge_facilitator` role.
    ///      - The gateway is not enabled.
    ///      - The recipient address is the zero address.
    ///      - No peer exists for the destination endpoint ID.
    ///      - The rate limit would be exceeded.
    function burnAndSend(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata extraOptions_
    )
        external
        payable
        override
        givenEnabled
        onlyRole(BRIDGE_FACILITATOR_ROLE)
        returns (MessagingReceipt memory receipt)
    {
        // Note: zero-amount validation is the facilitator's responsibility
        _requireNonzeroRecipient(to_);

        bytes32 peer = _getPeerOrRevert(dstEid_);

        _outflow(dstEid_, amount_); // Rate limit outflow

        // Track bridged supply on canonical chain
        if (IS_CANONICAL) {
            // Pre-fund mint approval so future inflow can mint without JIT self approval.
            // Bounds the canonical inflow mint to the amount of OHM actually burned via outflow.
            _increaseSupplyAndMintApproval(amount_);
            emit BridgedSupplyIncreased(amount_);
        }

        // Burn OHM held by the gateway (transferred here by the facilitator)
        // solhint-disable-next-line no-unused-vars
        IERC20(ohm).approve(address(MINTR), amount_);
        MINTR.burnOhm(address(this), amount_);

        // Encode and send the bridge message
        (bytes memory payload, bytes memory options) = _encodeBridgeOhmMessage(
            dstEid_,
            to_,
            amount_,
            extraOptions_
        );

        receipt = ILayerZeroEndpointV2(LZ_ENDPOINT).send{value: msg.value}(
            MessagingParams({
                dstEid: dstEid_,
                receiver: peer,
                message: payload,
                options: options,
                payInLzToken: false
            }),
            refundAddress_
        );
        emit Sent(msg.sender, amount_, dstEid_, receipt.guid);
    }

    // ========= FEE ESTIMATION ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The recipient address is zero.
    ///      - No peer exists for the destination endpoint ID.
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata extraOptions_
    ) external view override returns (MessagingFee memory fee) {
        _requireNonzeroRecipient(to_);
        bytes32 peer = _getPeerOrRevert(dstEid_);
        (bytes memory payload, bytes memory options) = _encodeBridgeOhmMessage(
            dstEid_,
            to_,
            amount_,
            extraOptions_
        );

        return
            ILayerZeroEndpointV2(LZ_ENDPOINT).quote(
                MessagingParams({
                    dstEid: dstEid_,
                    receiver: peer,
                    message: payload,
                    options: options,
                    payInLzToken: false
                }),
                address(this)
            );
    }

    // ========= LZ RECEIVE FUNCTIONS (ILayerZeroReceiver) ========= //

    /// @inheritdoc ILayerZeroReceiver
    /// @dev Reverts if:
    ///      - Receiving is not enabled (isReceiveEnabled is false).
    ///      - The caller is not the LayerZero endpoint.
    ///      - The origin sender is not the configured peer for the source endpoint ID.
    ///      - No peer is configured for the source endpoint ID.
    ///      - The message payload is shorter than the minimum encoded length.
    ///      - The message type is not MSG_BRIDGE_OHM.
    ///      - The bridge data payload has an unexpected length.
    ///      - (Canonical) The bridged supply would underflow.
    ///      - The OHM recipient address is the zero address when the message type is MSG_BRIDGE_OHM.
    function lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address,
        bytes calldata
    ) external payable override {
        if (!isReceiveEnabled) revert LZBridgeGateway_ReceiveNotEnabled();
        if (msg.sender != LZ_ENDPOINT) revert LZBridgeGateway_OnlyEndpoint();
        if (_getPeerOrRevert(origin_.srcEid) != origin_.sender)
            revert LZBridgeGateway_OnlyPeer(origin_.srcEid, origin_.sender);

        _decodeAndRoute(origin_.srcEid, guid_, message_);
    }

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin_) external view override returns (bool) {
        bytes32 peer = peers[origin_.srcEid];
        return peer != bytes32(0) && peer == origin_.sender;
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32, bytes32) external pure override returns (uint64) {
        return 0; // Unordered delivery
    }

    // ========= ADMIN FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///
    ///      WARNING: Updating or clearing the peer for an EID strands any in-flight inbound
    ///      messages from the previous peer that have already been verified on the LayerZero
    ///      endpoint but not yet executed. Such messages will revert in `lzReceive` on the
    ///      peer check and become permanently undeliverable.
    ///
    ///      Recovery requires the admin to handle each stranded message individually via the
    ///      LayerZero endpoint recovery functions (`skip`, `nilify`, `burn`, or `clear`).
    ///      A separate governance proposal may also be required to restore the OHM owed to
    ///      the affected users, and a corresponding `decreaseBridgedSupply` call is required
    ///      to keep the bookkeeping consistent.
    function setPeer(uint32 eid_, bytes32 peer_) external override onlyAdminRole {
        peers[eid_] = peer_;
        emit PeerSet(eid_, peer_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the emergency or admin role.
    ///      - The gateway is currently enabled.
    ///      - The value is already in the desired state.
    ///
    ///      The flag `isReceiveEnabled` is managed automatically by the policy lifecycle:
    ///      `enable()` and the re-enable path set it to `true`, and `disable()` resets it to
    ///      `false`. This function provides a manual override for the disabled state, so that
    ///      a disabled gateway can keep delivering in-flight inbound LayerZero messages after
    ///      sending stops.
    ///
    ///      The intended use case is a gateway replacement on a given chain.
    ///      The admin calls `disable` followed by `setIsReceiveEnabled(true)`. The old gateway
    ///      is disabled (which stops outbound sends), but any inbound LayerZero messages already
    ///      in flight to the old gateway can still settle on it. Once the migration is complete,
    ///      the old gateway is deactivated in the Kernel.
    ///
    ///      If `disable` is triggered by the emergency role without a proposal, it automatically
    ///      sets `isReceiveEnabled` to `false`. If it is confirmed that re-enabling is safe, the
    ///      manager can call `reEnable` within the grace window, which automatically sets
    ///      `isReceiveEnabled` to `true`.
    function setIsReceiveEnabled(
        bool isReceiveEnabled_
    ) external override givenDisabled onlyEmergencyOrAdminRole {
        if (isReceiveEnabled == isReceiveEnabled_)
            revert LZBridgeGateway_ReceiveAlreadyInDesiredState();
        _setIsReceiveEnabled(isReceiveEnabled_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - `delegate_` is the zero address.
    function setDelegate(address delegate_) external override onlyBridgeConfigurator {
        // Checks: delegate_ != address(0)
        validateSetDelegate(delegate_);
        ILayerZeroEndpointV2(LZ_ENDPOINT).setDelegate(delegate_);
        emit DelegateSet(delegate_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Intended for use immediately after the OCG proposal so the DAO MS can write
    ///      the computed initial bridged supply without going through the
    ///      `bridge_configurator` role (and therefore, in the intended deployment,
    ///      without waiting for the `LZBridgeAndDelegateConfig` timelock). After this
    ///      call further mutations must go through `increaseBridgedSupply` /
    ///      `decreaseBridgedSupply`.
    ///
    ///      Reverts if:
    ///      - The caller does not have the `bridge_admin` or `admin` role.
    ///      - The chain is not canonical.
    ///      - The bridged supply has already been initialized.
    ///      - The current bridged supply is non-zero.
    ///      - `amount_` is zero.
    function initializeBridgedSupply(uint256 amount_) external override onlyBridgeAdminOrAdmin {
        _requireCanonical();
        if (bridgedSupplyInitialized) revert LZBridgeGateway_BridgedSupplyAlreadyInitialized();
        if (bridgedSupply != 0) revert LZBridgeGateway_BridgedSupplyAlreadyNonZero(bridgedSupply);
        _requireNonzeroAmount(amount_);

        bridgedSupplyInitialized = true;
        _increaseSupplyAndMintApproval(amount_);
        emit BridgedSupplyInitialized(amount_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - IS_CANONICAL is false.
    ///      - `amount_` is zero.
    function increaseBridgedSupply(uint256 amount_) external override onlyBridgeConfigurator {
        // Checks: IS_CANONICAL; amount_ != 0
        validateIncreaseBridgedSupply(amount_);

        _increaseSupplyAndMintApproval(amount_);
        emit BridgedSupplyForciblyIncreased(amount_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///      - IS_CANONICAL is false.
    ///      - `amount_` is zero.
    ///      - The bridged supply would underflow.
    function decreaseBridgedSupply(uint256 amount_) external override onlyBridgeConfigurator {
        // Checks: IS_CANONICAL; amount_ != 0; bridgedSupply >= amount_
        validateDecreaseBridgedSupply(amount_);

        unchecked {
            bridgedSupply -= amount_;
        }
        MINTR.decreaseMintApproval(address(this), amount_);
        emit BridgedSupplyForciblyDecreased(amount_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - Any option entry is not Type 3 format.
    function setEnforcedOptions(
        EnforcedOptionParam[] calldata enforcedOptions_
    ) external override onlyAdminRole {
        for (uint256 i = 0; i < enforcedOptions_.length; ++i) {
            _assertOptionsType3(enforcedOptions_[i].options);
            enforcedOptions[enforcedOptions_[i].eid][
                enforcedOptions_[i].msgType
            ] = enforcedOptions_[i].options;
        }
        emit EnforcedOptionsSet(enforcedOptions_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///
    ///      Decays the existing in-flight amount of the targeted outbound limit and
    ///      checkpoints the counterpart inbound limit before writing the new `limit`
    ///      and `window`. The counterpart inbound limit's own `limit` and `window`
    ///      are preserved.
    function setOutRateLimits(
        RateLimitConfig[] calldata configs_
    ) external override onlyBridgeConfigurator {
        _setOutRateLimits(configs_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///
    ///      Symmetric with `setOutRateLimits`: decays the existing inbound in-flight
    ///      and checkpoints the counterpart outbound limit before writing the new
    ///      inbound `limit` and `window`. The counterpart outbound limit's own
    ///      `limit` and `window` are preserved.
    function setInRateLimits(
        RateLimitConfig[] calldata configs_
    ) external override onlyBridgeConfigurator {
        _setInRateLimits(configs_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///
    ///      Sets `inFlight` to zero and refreshes `lastUpdated` to the current
    ///      timestamp; the configured `limit` and `window` are preserved. The
    ///      corresponding inbound rate limit is not affected.
    function clearOutboundInFlight(
        uint32[] calldata eids_
    ) external override onlyBridgeConfigurator {
        _clearOutboundInFlight(eids_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_configurator role.
    ///
    ///      Sets `inFlight` to zero and refreshes `lastUpdated` to the current
    ///      timestamp; the configured `limit` and `window` are preserved. The
    ///      corresponding outbound rate limit is not affected.
    function clearInboundInFlight(
        uint32[] calldata eids_
    ) external override onlyBridgeConfigurator {
        _clearInboundInFlight(eids_);
    }

    // ========= RESCUE FUNCTIONS ========= //

    /// @inheritdoc Rescueable
    function _authorizeRescue() internal view override onlyManagerOrAdminRole {}

    // ========= VIEW FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - Extra options are provided but are not Type 3 format.
    ///      - Extra options have length 1 (insufficient for Type 3 prefix).
    function combineOptions(
        uint32 eid_,
        uint16 msgType_,
        bytes calldata extraOptions_
    ) external view override returns (bytes memory) {
        return _combineOptions(eid_, msgType_, extraOptions_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - `delegate_` is the zero address.
    function validateSetDelegate(address delegate_) public pure override {
        _requireNonzeroAddress(delegate_, "delegate");
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The chain is not canonical.
    ///      - `amount_` is zero.
    function validateIncreaseBridgedSupply(uint256 amount_) public view override {
        _requireCanonical();
        _requireNonzeroAmount(amount_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The chain is not canonical.
    ///      - `amount_` is zero.
    ///      - The current `bridgedSupply` is below `amount_`.
    function validateDecreaseBridgedSupply(uint256 amount_) public view override {
        _requireCanonical();
        _requireNonzeroAmount(amount_);
        _requireSupplyAtLeastAmount(amount_);
    }

    // ========= ERC165 ========= //

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(PolicyReEnabler, ReEnablerGracePeriod, Rescueable) returns (bool) {
        return
            interfaceId == type(ILZBridgeGateway).interfaceId ||
            interfaceId == type(ILayerZeroReceiver).interfaceId ||
            interfaceId == type(IOffsettingRateLimiter).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ========= PRIVATE FUNCTIONS ========= //

    /// @notice Increments `bridgedSupply` by `amount_` and grants the matching MINTR mint
    ///         approval to the gateway.
    /// @dev Used on canonical chains to keep `bridgedSupply` and the MINTR mint approval in
    ///      lockstep during outflow and forced supply increases.
    /// @param amount_ The amount of OHM to add to bridged supply and mint approval.
    function _increaseSupplyAndMintApproval(uint256 amount_) private {
        bridgedSupply += amount_;
        _increaseMintApproval(amount_);
    }

    /// @notice Grants `amount_` of additional MINTR mint approval to the gateway.
    /// @dev Wraps the MINTR call so the `address(this)` argument is not duplicated at each
    ///      use site, saving bytecode.
    /// @param amount_ The mint approval delta to add.
    function _increaseMintApproval(uint256 amount_) private {
        MINTR.increaseMintApproval(address(this), amount_);
    }

    /// @notice Sets `isReceiveEnabled` and emits the corresponding event.
    /// @param  isReceiveEnabled_ The new flag value.
    function _setIsReceiveEnabled(bool isReceiveEnabled_) private {
        isReceiveEnabled = isReceiveEnabled_;
        emit IsReceiveEnabledSet(isReceiveEnabled_);
    }

    /// @notice Reverts with `LZBridgeGateway_BridgedSupplyUnderflow` if the current
    ///         `bridgedSupply` is below `amount_`.
    /// @param amount_ The amount that would be subtracted from bridged supply.
    function _requireSupplyAtLeastAmount(uint256 amount_) private view {
        uint256 supply = bridgedSupply;
        if (supply < amount_) revert LZBridgeGateway_BridgedSupplyUnderflow(supply, amount_);
    }

    /// @notice Reverts with `LZBridgeGateway_ZeroAmount` if `amount_` is zero.
    /// @param amount_ The amount to validate.
    function _requireNonzeroAmount(uint256 amount_) private pure {
        if (amount_ == 0) revert LZBridgeGateway_ZeroAmount();
    }

    /// @notice Builds the outbound bridge-OHM payload and the combined options for a given
    ///         destination.
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM being bridged.
    /// @param extraOptions_ Caller-supplied Type 3 options to merge with enforced options.
    /// @return payload The ABI-encoded `(MSG_BRIDGE_OHM, abi.encode(to_, amount_))` message.
    /// @return options The combination of enforced and caller-supplied options.
    function _encodeBridgeOhmMessage(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata extraOptions_
    ) private view returns (bytes memory payload, bytes memory options) {
        payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        options = _combineOptions(dstEid_, MSG_BRIDGE_OHM, extraOptions_);
    }

    /// @notice Decodes the message type from the payload and routes to the appropriate handler.
    function _decodeAndRoute(uint32 srcEid_, bytes32 guid_, bytes calldata payload_) private {
        if (payload_.length < _MIN_PAYLOAD_LENGTH) revert LZBridgeGateway_InvalidPayload();
        (uint8 msgType, bytes memory data) = abi.decode(payload_, (uint8, bytes));

        if (msgType == MSG_BRIDGE_OHM) {
            _receiveBridgeOhm(srcEid_, guid_, data);
        } else {
            revert LZBridgeGateway_InvalidMessageType(msgType);
        }
    }

    /// @notice Processes a received OHM bridge message.
    /// @dev On canonical chains, decrements bridgedSupply and mints from pre-funded approval
    ///      (set during outflow). On non-canonical chains, uses JIT self approval.
    function _receiveBridgeOhm(uint32 srcEid_, bytes32 guid_, bytes memory data_) private {
        if (data_.length != _BRIDGE_OHM_DATA_LENGTH) revert LZBridgeGateway_InvalidPayload();
        (address to, uint256 amount) = abi.decode(data_, (address, uint256));

        _requireNonzeroRecipient(to);

        // Track bridged supply on canonical chain
        if (IS_CANONICAL) {
            _requireSupplyAtLeastAmount(amount);
            unchecked {
                bridgedSupply -= amount;
            }
            emit BridgedSupplyDecreased(amount);
            // Approval already exists from outflow, no JIT needed
        } else {
            // Non-canonical: JIT self approval
            _increaseMintApproval(amount);
        }

        _inflow(srcEid_, amount); // Rate limit inflow

        MINTR.mintOhm(to, amount);

        emit Received(to, amount, srcEid_, guid_);
    }

    function _getPeerOrRevert(uint32 eid_) private view returns (bytes32) {
        bytes32 peer = peers[eid_];
        if (peer == bytes32(0)) revert LZBridgeGateway_NoPeer(eid_);
        return peer;
    }

    function _requireCanonical() private view {
        if (!IS_CANONICAL) revert LZBridgeGateway_NotCanonical();
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert LZBridgeGateway_InvalidAddress(parameter_);
    }

    /// @notice Reverts with `LZBridgeGateway_InvalidAddress("to")` if `to_` is the zero address.
    /// @param  to_ The recipient address to validate.
    function _requireNonzeroRecipient(address to_) private pure {
        _requireNonzeroAddress(to_, "to");
    }

    // ========= ENFORCED OPTIONS (composed from OAppOptionsType3) ========= //

    /// @notice Combines enforced options with caller-provided extra options.
    function _combineOptions(
        uint32 eid_,
        uint16 msgType_,
        bytes calldata extraOptions_
    ) internal view returns (bytes memory) {
        bytes memory enforced = enforcedOptions[eid_][msgType_];

        // No enforced options, pass whatever the caller supplied
        if (enforced.length == 0) return extraOptions_;

        // No caller options, return enforced
        if (extraOptions_.length == 0) return enforced;

        _assertOptionsType3(extraOptions_);

        // Strip the 2-byte Type 3 prefix from extra options before concatenation
        return bytes.concat(enforced, extraOptions_[2:]);
    }

    /// @notice Validates that calldata options bytes begin with the Type 3 prefix.
    function _assertOptionsType3(bytes calldata options_) internal pure {
        if (options_.length < 2 || uint16(bytes2(options_[:2])) != _OPTION_TYPE_3)
            revert LZBridgeGateway_InvalidOptions(options_);
    }
}
