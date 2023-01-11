// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {NonblockingLzApp, ILayerZeroEndpoint} from "layer-zero/lzApp/NonblockingLzApp.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

/// @notice Message bus defining interface for cross-chain communications.
/// @dev Uses LayerZero as communication protocol.
contract OlympusTransmitter is Policy, RolesConsumer, NonblockingLzApp {
    error InsufficientAmount();
    error CallerMustBeLZEndpoint();

    event OffchainTransferred(address sender_, uint256 amount_, uint16 dstChain_);
    event OffchainReceived(address receiver_, uint256 amount_, uint16 srcChain_);
    event ChainStatusUpdated(uint16 chainId_, bool isValid_);

    // Modules
    MINTRv1 public MINTR;

    mapping(uint16 => bool) public validChains;

    ERC20 ohm;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        ERC20 ohm_,
        address endpoint_
    ) Policy(kernel_) NonblockingLzApp(endpoint_) {
        ohm = ohm_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](4);
        permissions[0] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(MINTR.KEYCODE(), MINTR.decreaseMintApproval.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function setChainStatus(uint16 chainId_, bool isValid_) external onlyRole("bridge_admin") {
        validChains[chainId_] = isValid_;

        emit ChainStatusUpdated(chainId_, isValid_);
    }

    // TODO Send information needed to mint OHM on another chain
    function sendOhm(address to_, uint256 amount_, uint16 dstChainId_) external payable {
        if (ohm.balanceOf(msg.sender) < amount_) revert InsufficientAmount();

        bytes memory payload = abi.encode(to_, amount_);

        MINTR.burnOhm(msg.sender, amount_);

        //uint256 gasFee = lzEndpoint.estimateFees()

        _lzSend(
            dstChainId_,
            payload,
            payable(msg.sender),
            address(0x0),
            bytes(""),
            msg.value
        );

        emit OffchainTransferred(msg.sender, amount_, dstChainId_);
    }

    // TODO receives info to mint to a user's wallet
    function _nonblockingLzReceive(
        uint16 srcChainId_,
        bytes memory srcAddress_,
        uint64 nonce_,
        bytes memory payload_
    ) internal override {
        if (msg.sender != address(lzEndpoint)) revert CallerMustBeLZEndpoint();

        //(MessageType msgType, bytes memory payload) = abi.decode(payload_, (MessageType, bytes));
        (address to, uint256 amount) = abi.decode(payload_, (address, uint256));

        MINTR.increaseMintApproval(address(this), amount);
        MINTR.mintOhm(to, amount);
        
        emit OffchainReceived(to, amount, srcChainId_);
    }
}
