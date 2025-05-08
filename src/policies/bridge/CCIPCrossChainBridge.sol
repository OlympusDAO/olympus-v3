// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

// CCIP
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

/// @title CCIPCrossChainBridge
/// @notice Bophades policy to bridge OHM using Chainlink CCIP
contract CCIPCrossChainBridge is Policy, PolicyEnabler, TokenPool {
    // Tasks
    // [X] Add PolicyEnabler
    // [ ] Add compiler configuration for 0.8.24
    // [ ] Add function for user to send OHM
    // [X] Import TokenPool abstract
    // [X] Implement minting of OHM
    // [X] Implement burning of OHM
    // [ ] Implement support for rate-limiting
    // [X] Implement tracking of bridged supply from mainnet
    // [ ] _ccipReceive: validate source chain and sender against allowlist
    // [ ] _ccipSend: validate destination chain against allowlist
    // [ ] _ccipReceive: validate router address
    // [ ] immutable extraArgs
    // [ ] failure handling

    // =========  ERRORS ========= //

    error CrossChainBridge_MintApprovalOutOfSync(uint256 expected, uint256 actual);

    error CrossChainBridge_InvalidToken(address expected, address actual);

    // =========  STATE VARIABLES ========= //

    /// @notice Bophades module for minting and burning OHM
    MINTRv1 public MINTR;

    /// @notice Whether the contract is on mainnet
    bool internal immutable _IS_MAINNET;

    /// @notice Quantity of OHM bridged
    /// @dev    This will only be set on mainnet
    uint256 public bridgedSupply;

    /// @notice Initial bridged supply
    /// @dev    This is used in `configureDependencies` to set the initial value for `bridgedSupply`
    uint256 internal immutable _INITIAL_BRIDGED_SUPPLY;

    /// @notice Whether the bridged supply has been initialized
    bool internal _bridgeSupplyInitialized;

    // =========  CONSTRUCTOR ========= //

    constructor(
        address kernel_,
        uint256 initialBridgedSupply_,
        address ohm_,
        address rmnProxy_,
        address ccipRouter_
    )
        Policy(Kernel(kernel_))
        TokenPool(IERC20(ohm_), IERC20(ohm_).decimals(), new address[](0), rmnProxy_, ccipRouter_)
    {
        // Check if the contract is on mainnet
        _IS_MAINNET = block.chainid == 1;

        // Set the initial bridged supply
        _INITIAL_BRIDGED_SUPPLY = initialBridgedSupply_;

        // Disabled by default
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);

        // Check that OHM is the same as the token passed in to the constructor
        if (address(i_token) != address(MINTR.ohm()))
            revert CrossChainBridge_InvalidToken(address(MINTR.ohm()), address(i_token));

        // === Mint approvals ===

        // If the bridged supply has been initialized (policy re-installation)
        if (_bridgeSupplyInitialized) {
            // Ensure that the mint approval is in sync
            // If not in sync, it will need to be manually adjusted
            uint256 mintApproval = MINTR.mintApproval(address(this));
            if (mintApproval != bridgedSupply)
                revert CrossChainBridge_MintApprovalOutOfSync(bridgedSupply, mintApproval);

            // No need to adjust the mint approval
        }
        // Otherwise the initial bridged supply needs to be set
        else {
            // Ensure that the mint approval has not been set
            uint256 mintApproval = MINTR.mintApproval(address(this));
            if (mintApproval != 0) revert CrossChainBridge_MintApprovalOutOfSync(0, mintApproval);

            // Set the initial bridged supply
            MINTR.increaseMintApproval(address(this), _INITIAL_BRIDGED_SUPPLY);

            // Mark that the bridged supply has been initialized
            _bridgeSupplyInitialized = true;
        }
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        permissions = new Permissions[](4);
        permissions[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
    }

    /// @notice Returns the version of the policy
    ///
    /// @return major The major version of the policy
    /// @return minor The minor version of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========= MINT/BURN FUNCTIONS ========= //

    /// @inheritdoc TokenPool
    /// @dev        This is based on the {BurnMintTokenPoolAbstract.lockOrBurn} function, with customisations for the Olympus protocol stack.
    ///
    ///             This function performs the following:
    ///             - Validates the lockOrBurnIn data
    ///             - On mainnet: increments the bridged supply
    ///             - Pulls the OHM from the sender
    ///             - Burns the OHM
    ///             - Emits the Burned event
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external virtual override returns (Pool.LockOrBurnOutV1 memory) {
        _validateLockOrBurn(lockOrBurnIn);

        // Tracking of bridged amounts
        if (_IS_MAINNET) {
            // If the contract is on mainnet, increment the bridged supply
            // This is used to track the total supply of OHM that has been bridged, and hence the amount that can be minted on mainnet when bridged back
            bridgedSupply += lockOrBurnIn.amount;

            // In step, adjust the mint approval for the contract, so that it can mint the OHM when bridged back
            // The mint approval should be consistent with the bridgedSupply
            MINTR.increaseMintApproval(address(this), lockOrBurnIn.amount);
        }

        // Pull the OHM from the sender
        ohm.transferFrom(lockOrBurnIn.originalSender, address(this), lockOrBurnIn.amount);

        // Burn the OHM
        MINTR.burnOhm(address(this), lockOrBurnIn.amount);

        emit Burned(lockOrBurnIn.originalSender, lockOrBurnIn.amount);

        return
            Pool.LockOrBurnOutV1({
                destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
                destPoolData: _encodeLocalDecimals()
            });
    }

    /// @inheritdoc TokenPool
    /// @dev        This is based on the {BurnMintTokenPoolAbstract.releaseOrMint} function, with customisations for the Olympus protocol stack.
    ///
    ///             This function performs the following:
    ///             - Validates the releaseOrMintIn data
    ///             - Calculates the local amount
    ///             - Mints the OHM
    ///             - Emits the Minted event
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) public virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
        _validateReleaseOrMint(releaseOrMintIn);

        // Calculate the local amount
        uint256 localAmount = _calculateLocalAmount(
            releaseOrMintIn.amount,
            _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        );

        // Tracking of bridged amounts
        if (_IS_MAINNET) {
            // If the contract is on mainnet, decrement the bridged supply
            // This puts a hard cap on the amount of OHM that can be bridged back to mainnet
            bridgedSupply -= releaseOrMintIn.amount;

            // Mint approval would have already been granted in `lockOrBurn` when bridging from mainnet
        } else {
            // If the contract is not on mainnet, increment the mint approval
            // Although this permits infinite minting on the non-mainnet chain, it would not be possible to bridge back to mainnet due to the hard cap set by `bridgedSupply`
            MINTR.increaseMintApproval(address(this), releaseOrMintIn.amount);
        }

        // Mint to the receiver
        MINTR.mintOhm(releaseOrMintIn.receiver, localAmount);

        emit Minted(msg.sender, releaseOrMintIn.receiver, localAmount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: localAmount});
    }
}
