// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepositTokenManager} from "src/policies/interfaces/IConvertibleDepositTokenManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title Convertible Deposit Token Manager
/// @notice This policy is used to manage convertible deposit ("CD") tokens on behalf of deposit facilities. It is meant to be used by the facilities, and is not an end-user policy.
contract CDTokenManager is Policy, PolicyEnabler, IConvertibleDepositTokenManager {
    using SafeTransferLib for ERC20;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSITOR = "cd_token_manager";

    // ========== STATE VARIABLES ========== //

    /// @notice The CDEPO module
    CDEPOv1 public CDEPO;

    /// @notice The mapping of depositors and vaults to the number of shares they have deposited
    mapping(address => mapping(IERC4626 => uint256)) internal _depositedShares;

    /// @notice The list of depositors
    address[] internal _depositors;

    // ========== CONSTRUCTOR ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
        // Disabled by default by PolicyEnabler
    }

    // ========== Policy Configuration ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDEPO");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode cdepoKeycode = toKeycode("CDEPO");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(cdepoKeycode, CDEPO.create.selector);
        permissions[1] = Permissions(cdepoKeycode, CDEPO.setReclaimRate.selector);
        permissions[2] = Permissions(cdepoKeycode, CDEPO.mintFor.selector);
        permissions[3] = Permissions(cdepoKeycode, CDEPO.burnFrom.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== DEPOSIT/WITHDRAW FUNCTIONS ========== //

    /// @notice Adds a depositor to the list of depositors
    ///
    /// @param  depositor_  The address of the depositor
    function _addDepositor(address depositor_) internal {
        // Check if the depositor is already in the list
        if (_depositors.length > 0) {
            for (uint256 i = 0; i < _depositors.length; i++) {
                if (_depositors[i] == depositor_) {
                    return;
                }
            }
        }

        // Add the depositor to the list
        _depositors.push(depositor_);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function mint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Pull funds from the caller
        ERC20 vaultAsset = ERC20(address(cdToken_.asset()));
        vaultAsset.safeTransferFrom(msg.sender, address(this), amount_);

        // Deposit into vault
        IERC4626 vault = cdToken_.vault();
        vaultAsset.safeApprove(address(vault), amount_);
        shares = vault.deposit(amount_, address(this));

        // Update the shares deposited for the caller
        _depositedShares[msg.sender][vault] += shares;

        // Add the caller to the list of depositors if they are not already in it
        _addDepositor(msg.sender);

        // Mint the CD token to the caller
        // This will also validate that the CD token is supported
        CDEPO.mintFor(cdToken_, msg.sender, amount_);

        // Emit an event
        emit Mint(msg.sender, address(cdToken_), amount_, shares);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function burn(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Burn the CD token from the caller
        CDEPO.burnFrom(cdToken_, msg.sender, amount_);

        // TODO split this into withdraw and burn? Allows for claiming yield.

        // Withdraw the funds from the vault
        IERC4626 vault = cdToken_.vault();
        shares = vault.withdraw(amount_, msg.sender, address(this));

        // Update the shares deposited for the caller
        _depositedShares[msg.sender][vault] -= shares;

        // Emit an event
        emit Burn(msg.sender, address(cdToken_), amount_, shares);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getDepositedShares(
        address depositor_,
        IERC4626 vault_
    ) external view returns (uint256 shares) {
        shares = _depositedShares[depositor_][vault_];
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getDepositors() external view returns (address[] memory depositors) {
        depositors = _depositors;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositTokenManager
    function createToken(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (IConvertibleDepositERC20 cdToken) {
        cdToken = CDEPO.create(vault_, periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function setTokenReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole {
        CDEPO.setReclaimRate(cdToken_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getTokenReclaimRate(
        IConvertibleDepositERC20 cdToken_
    ) external view returns (uint16 reclaimRate) {
        reclaimRate = CDEPO.reclaimRate(address(cdToken_));
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getDepositTokens()
        external
        view
        returns (IConvertibleDepository.DepositToken[] memory depositTokens)
    {
        depositTokens = CDEPO.getDepositTokens();
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getConvertibleDepositTokens()
        external
        view
        returns (IConvertibleDepositERC20[] memory convertibleDepositTokens)
    {
        convertibleDepositTokens = CDEPO.getConvertibleDepositTokens();
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function isConvertibleDepositToken(
        address convertibleDepositToken_
    ) external view returns (bool isConvertible) {
        isConvertible = CDEPO.isConvertibleDepositToken(convertibleDepositToken_);
    }
}
