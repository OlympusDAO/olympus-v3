// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";

// Libraries
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Inventory
/// @notice Custodies protocol-supplied OHM and funds one authenticated fixed-term loan facility.
/// @dev Burner Loans Inventory deliberately does not read FLOAN. Its active-principal ledger changes only
///      through atomic deltas submitted by the immutable facility address. The immutable OHM
///      dependency is assumed to be a standard, non-fee-on-transfer token.
contract BurnerLoansInventory is
    Policy,
    PolicyEnablerV2,
    ReentrancyGuardTransient,
    IBurnerLoansInventory,
    IVersioned
{
    using SafeTransferLib for ERC20;

    /// @notice OHM token funded and custodied by Burner Loans Inventory.
    IERC20 internal immutable _OHM;

    /// @notice Minter module used to mint, burn, and manage approval.
    MINTRv1 internal _MINTR;

    /// @notice Treasury module that receives rescued surplus.
    TRSRYv1 internal _TRSRY;

    /// @notice Immutable Burner Loans policy authorized to change principal accounting.
    address internal immutable _FACILITY;

    /// @notice Burner Loans Config policy authorized to set the global debt cap.
    address internal _configurator;

    /// @notice Maximum active OHM principal funded by Burner Loans Inventory.
    uint128 internal _globalDebtCapOhm;

    /// @notice Aggregate principal currently outstanding.
    uint128 internal _activePrincipalOhm;

    /// @notice Supplied OHM held by Burner Loans Inventory and available for funding or withdrawal.
    uint128 internal _suppliedIdleOhm;

    /// @notice All providers' aggregate outstanding claim on supplied OHM.
    uint128 internal _suppliedOhm;

    /// @notice Outstanding supplied-OHM claim belonging to each authorized provider.
    mapping(address provider => uint128 claimOhm) internal _providerClaimOhm;

    /// @notice Constructs Burner Loans Inventory for one immutable Burner Loans facility.
    /// @dev The facility may be inactive during deployment, but it must already be deployed and
    ///      belong to `kernel_`.
    /// @param kernel_ Kernel shared by Burner Loans Inventory and the facility.
    /// @param ohm_ OHM token funded by Burner Loans Inventory and burned through MINTR.
    /// @param facility_ Burner Loans policy permanently authorized to change principal accounting.
    constructor(Kernel kernel_, IERC20 ohm_, address facility_) Policy(kernel_) {
        if (address(ohm_) == address(0) || facility_ == address(0)) {
            revert BurnerLoansInventory_ZeroAddress();
        }
        if (facility_.code.length == 0 || address(Policy(facility_).kernel()) != address(kernel_)) {
            revert BurnerLoansInventory_InvalidPolicy(facility_);
        }
        _OHM = ohm_;
        _FACILITY = facility_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("TRSRY");

        MINTRv1 priorMintr = _MINTR;
        _MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        _TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));

        (uint8 mintrMajor, ) = _MINTR.VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        (uint8 trsryMajor, ) = _TRSRY.VERSION();
        if (mintrMajor != 1 || rolesMajor != 1 || trsryMajor != 1) {
            revert BurnerLoansInventory_InvalidModuleVersion();
        }
        address mintrOhm = address(_MINTR.ohm());
        if (mintrOhm != address(_OHM)) {
            revert BurnerLoansInventory_InvalidOhm(address(_OHM), mintrOhm);
        }

        // MINTR burns repayment OHM through `OHM.burnFrom(BurnerLoansInventory, amount)`, so it
        // needs a standing token allowance. A MINTR upgrade first revokes the obsolete module's
        // allowance, then grants the current module the burn allowance. Mint approval is separate
        // MINTR accounting and is reconciled to the global-cap-derived target below.
        ERC20 token = ERC20(address(_OHM));
        if (address(priorMintr) != address(0) && priorMintr != _MINTR) {
            token.safeApprove(address(priorMintr), 0);
        }
        token.safeApprove(address(_MINTR), type(uint256).max);
        if (address(priorMintr) != address(0) && priorMintr != _MINTR) {
            _restoreApproval(_globalDebtCapOhm);
        }
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode mintr = toKeycode("MINTR");
        requests = new Permissions[](4);
        requests[0] = Permissions({keycode: mintr, funcSelector: MINTRv1.mintOhm.selector});
        requests[1] = Permissions({keycode: mintr, funcSelector: MINTRv1.burnOhm.selector});
        requests[2] = Permissions({
            keycode: mintr,
            funcSelector: MINTRv1.increaseMintApproval.selector
        });
        requests[3] = Permissions({
            keycode: mintr,
            funcSelector: MINTRv1.decreaseMintApproval.selector
        });
    }

    /// @inheritdoc IBurnerLoansInventory
    function setConfigurator(address configurator_) external givenDisabled onlyAdminRole {
        if (configurator_ == address(0)) revert BurnerLoansInventory_ZeroAddress();
        _requireActivePolicy(configurator_);
        try IBurnerLoansConfig(configurator_).facility() returns (address facility_) {
            if (facility_ != _FACILITY) {
                revert BurnerLoansInventory_InvalidPolicy(configurator_);
            }
        } catch {
            revert BurnerLoansInventory_InvalidPolicy(configurator_);
        }
        _configurator = configurator_;
        emit ConfiguratorSet(configurator_);
    }

    /// @inheritdoc IBurnerLoansInventory
    function setGlobalDebtCap(uint128 capOhm_) external nonReentrant {
        _onlyConfigurator();
        if (capOhm_ < _activePrincipalOhm) {
            revert BurnerLoansInventory_InvalidCap(capOhm_, _activePrincipalOhm);
        }
        _globalDebtCapOhm = capOhm_;
        _syncMintApproval();
        emit GlobalDebtCapSet(capOhm_);
    }

    /// @inheritdoc IBurnerLoansInventory
    function supply(uint128 amount_) external givenEnabled nonReentrant {
        _requireRole(msg.sender, BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        _providerClaimOhm[msg.sender] += amount_;
        _suppliedIdleOhm += amount_;
        _suppliedOhm += amount_;
        ERC20(address(_OHM)).safeTransferFrom(msg.sender, address(this), amount_);
        _reduceUnsafeApproval();
        emit OhmSupplied(msg.sender, amount_, _providerClaimOhm[msg.sender], _suppliedOhm);
    }

    /// @inheritdoc IBurnerLoansInventory
    function withdraw(uint128 amount_, address recipient_) external givenEnabled nonReentrant {
        _requireRole(msg.sender, BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        if (recipient_ == address(0)) revert BurnerLoansInventory_ZeroAddress();
        uint128 providerClaim = _providerClaimOhm[msg.sender];
        if (amount_ > providerClaim) {
            revert BurnerLoansInventory_InsufficientClaim(amount_, providerClaim);
        }
        if (amount_ > _suppliedIdleOhm) {
            revert BurnerLoansInventory_InsufficientIdle(amount_, _suppliedIdleOhm);
        }
        _providerClaimOhm[msg.sender] = providerClaim - amount_;
        _suppliedOhm -= amount_;
        _suppliedIdleOhm -= amount_;
        _restoreApproval(amount_);
        ERC20(address(_OHM)).safeTransfer(recipient_, amount_);
        emit OhmWithdrawn(msg.sender, amount_, _providerClaimOhm[msg.sender], _suppliedOhm);
    }

    /// @inheritdoc IBurnerLoansInventory
    function draw(address recipient_, uint128 amount_) external givenEnabled nonReentrant {
        _onlyFacility();
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        if (recipient_ == address(0)) revert BurnerLoansInventory_ZeroAddress();
        uint256 capacity = availableCapacity();
        if (amount_ > capacity) {
            revert BurnerLoansInventory_InsufficientCapacity(amount_, capacity);
        }

        _activePrincipalOhm += amount_;
        uint128 suppliedAmount = amount_ < _suppliedIdleOhm ? amount_ : _suppliedIdleOhm;
        _suppliedIdleOhm -= suppliedAmount;
        uint128 mintedAmount = amount_ - suppliedAmount;
        if (mintedAmount != 0) _MINTR.mintOhm(address(this), mintedAmount);
        ERC20(address(_OHM)).safeTransfer(recipient_, amount_);
        emit OhmDrawn(recipient_, amount_, suppliedAmount, mintedAmount);
    }

    /// @inheritdoc IBurnerLoansInventory
    function settleRepayment(uint128 amount_) external givenEnabled nonReentrant {
        _onlyFacility();
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        uint256 requiredBalance = uint256(_suppliedIdleOhm) + amount_;
        uint256 balance = _OHM.balanceOf(address(this));
        if (balance < requiredBalance) {
            revert BurnerLoansInventory_InsufficientBalance(requiredBalance, balance);
        }

        _decreaseActivePrincipal(amount_);
        // Principal can exceed the aggregate supplied claim because Burner Loans Inventory may
        // have funded the loan with minted OHM. Retain only the claim deficit and burn the excess.
        uint128 deficit = _suppliedOhm - _suppliedIdleOhm;
        uint128 retained = amount_ < deficit ? amount_ : deficit;
        _suppliedIdleOhm += retained;
        uint128 burnAmount = amount_ - retained;
        uint128 burned;
        if (burnAmount != 0) {
            try _MINTR.burnOhm(address(this), burnAmount) {
                burned = burnAmount;
                _restoreApproval(burnAmount);
            } catch (bytes memory failureData) {
                emit OhmBurnFailed(burnAmount, failureData);
            }
        }
        emit RepaymentSettled(amount_, retained, burned);
    }

    /// @inheritdoc IBurnerLoansInventory
    function recordDefault(uint128 amount_) external givenEnabled nonReentrant {
        _onlyFacility();
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        _decreaseActivePrincipal(amount_);
        _restoreApproval(amount_);
        emit PrincipalDefaulted(amount_);
    }

    /// @inheritdoc IBurnerLoansInventory
    function syncMintApproval() external givenEnabled nonReentrant returns (uint256 approval_) {
        _requireRole(msg.sender, BURNER_LOANS_ADMIN_ROLE);
        approval_ = _syncMintApproval();
        emit MintApprovalSynchronized(approval_);
    }

    /// @inheritdoc IBurnerLoansInventory
    function burnSurplus() external givenEnabled onlyAdminRole nonReentrant {
        uint256 surplus = surplusOhm();
        if (surplus == 0) return;
        _MINTR.burnOhm(address(this), surplus);
        emit SurplusBurned(surplus);
    }

    /// @inheritdoc IBurnerLoansInventory
    function rescueSurplus() external givenEnabled onlyAdminRole nonReentrant {
        uint256 surplus = surplusOhm();
        if (surplus == 0) return;
        ERC20(address(_OHM)).safeTransfer(address(_TRSRY), surplus);
        emit SurplusRescued(surplus);
    }

    /// @inheritdoc IBurnerLoansInventory
    function ohm() external view returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoansInventory
    function configurator() external view returns (address) {
        return _configurator;
    }

    /// @inheritdoc IBurnerLoansInventory
    function facility() external view returns (address) {
        return _FACILITY;
    }

    /// @inheritdoc IBurnerLoansInventory
    function globalDebtCapOhm() external view returns (uint128) {
        return _globalDebtCapOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    function activePrincipalOhm() external view returns (uint128) {
        return _activePrincipalOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    function suppliedIdleOhm() external view returns (uint128) {
        return _suppliedIdleOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    function suppliedOhm() external view returns (uint128) {
        return _suppliedOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    function providerClaimOhm(address provider_) external view returns (uint128) {
        return _providerClaimOhm[provider_];
    }

    /// @inheritdoc IBurnerLoansInventory
    function desiredMintApproval() public view returns (uint256) {
        uint256 committed = uint256(_activePrincipalOhm) + _suppliedIdleOhm;
        return _globalDebtCapOhm > committed ? _globalDebtCapOhm - committed : 0;
    }

    /// @inheritdoc IBurnerLoansInventory
    function availableCapacity() public view returns (uint256) {
        uint256 capRoom = _globalDebtCapOhm - _activePrincipalOhm;
        uint256 idle = _suppliedIdleOhm;
        if (idle >= capRoom) return capRoom;

        uint256 approval = _MINTR.mintApproval(address(this));
        uint256 requiredApproval = capRoom - idle;
        return approval < requiredApproval ? idle + approval : capRoom;
    }

    /// @inheritdoc IBurnerLoansInventory
    function surplusOhm() public view returns (uint256) {
        uint256 balance = _OHM.balanceOf(address(this));
        uint256 idle = _suppliedIdleOhm;
        return balance > idle ? balance - idle : 0;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, IERC165) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansInventory).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @dev Reverts unless the caller is Burner Loans' current configuration policy.
    function _onlyConfigurator() internal view {
        if (msg.sender != _configurator) {
            revert BurnerLoansInventory_Unauthorized(msg.sender);
        }
    }

    /// @dev Reverts unless the caller is the immutable Burner Loans facility.
    function _onlyFacility() internal view {
        if (msg.sender != _FACILITY) revert BurnerLoansInventory_Unauthorized(msg.sender);
    }

    /// @dev Revalidates constructor and mutable policy links before operational enablement.
    function _beforeEnable(bytes calldata) internal view override {
        _requireActivePolicy(_FACILITY);
        address configurator_ = _configurator;
        if (configurator_ != address(0)) _requireActivePolicy(configurator_);
    }

    /// @dev Reverts unless `policy_` is active in and reports this Kernel.
    function _requireActivePolicy(address policy_) internal view {
        if (!kernel.isPolicyActive(Policy(policy_))) {
            revert BurnerLoansInventory_InvalidPolicy(policy_);
        }
        try Policy(policy_).kernel() returns (Kernel reportedKernel) {
            if (address(reportedKernel) != address(kernel)) {
                revert BurnerLoansInventory_InvalidPolicy(policy_);
            }
        } catch {
            revert BurnerLoansInventory_InvalidPolicy(policy_);
        }
    }

    /// @dev Reverts when `amount_` exceeds active principal; otherwise decrements it exactly.
    function _decreaseActivePrincipal(uint128 amount_) internal {
        uint128 activePrincipal = _activePrincipalOhm;
        if (amount_ > activePrincipal) {
            revert BurnerLoansInventory_ExcessivePrincipal(amount_, activePrincipal);
        }
        _activePrincipalOhm = activePrincipal - amount_;
    }

    /// @dev Reduces unsafe over-approval.
    function _reduceUnsafeApproval() internal {
        uint256 desired = desiredMintApproval();
        uint256 current = _MINTR.mintApproval(address(this));
        if (current > desired) _MINTR.decreaseMintApproval(address(this), current - desired);
    }

    /// @dev Best-effort restores capacity. A failed restoration requires an admin sync.
    function _restoreApproval(uint128 amount_) internal {
        if (amount_ == 0) return;
        uint256 current = _MINTR.mintApproval(address(this));
        uint256 desired = desiredMintApproval();
        if (current > desired) {
            _MINTR.decreaseMintApproval(address(this), current - desired);
            return;
        }
        uint256 gap = desired > current ? desired - current : 0;
        uint256 restorable = amount_ < gap ? amount_ : gap;
        if (restorable == 0) return;
        try _MINTR.increaseMintApproval(address(this), restorable) {} catch (
            bytes memory failureData
        ) {
            emit ApprovalRestorationFailed(restorable, failureData);
        }
    }

    /// @dev Strictly reconciles MINTR approval to the current cap-derived target.
    function _syncMintApproval() internal returns (uint256 approval_) {
        approval_ = _MINTR.mintApproval(address(this));
        uint256 desired = desiredMintApproval();
        if (approval_ > desired) {
            _MINTR.decreaseMintApproval(address(this), approval_ - desired);
            return desired;
        }
        if (approval_ < desired) {
            _MINTR.increaseMintApproval(address(this), desired - approval_);
            return desired;
        }
    }
}
