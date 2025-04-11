// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Interfaces
import {IERC20} from "../interfaces/IERC20.sol";
import {IMonoCooler} from "../policies/interfaces/cooler/IMonoCooler.sol";
import {ICoolerComposites} from "./interfaces/ICoolerComposites.sol";
import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";
import {IEnabler} from "./interfaces/IEnabler.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";

/// @title  Cooler Composites
/// @notice The CoolerComposites contract enables users to combine multiple operations into a single call
contract CoolerComposites is ICoolerComposites, Owned, IEnabler {
    using SafeTransferLib for ERC20;

    // ========= STATE ========= //

    /// @notice Whether the contract is enabled
    bool public isEnabled;

    IMonoCooler public immutable COOLER;

    ERC20 internal immutable _COLLATERAL_TOKEN;

    ERC20 internal immutable _DEBT_TOKEN;

    constructor(IMonoCooler cooler_, address owner_) Owned(owner_) {
        COOLER = cooler_;

        _COLLATERAL_TOKEN = ERC20(address(cooler_.collateralToken()));
        _COLLATERAL_TOKEN.approve(address(cooler_), type(uint256).max);

        _DEBT_TOKEN = ERC20(address(cooler_.debtToken()));
        _DEBT_TOKEN.approve(address(cooler_), type(uint256).max);

        // Disabled by default
    }

    // ===== Composite Functions ===== //

    /// @inheritdoc ICoolerComposites
    function addCollateralAndBorrow(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external onlyEnabled {
        if (authorization.account != address(0)) {
            COOLER.setAuthorizationWithSig(authorization, signature);
        }

        _COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), collateralAmount);
        COOLER.addCollateral(collateralAmount, msg.sender, delegationRequests);
        COOLER.borrow(borrowAmount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICoolerComposites
    function repayAndRemoveCollateral(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external onlyEnabled {
        if (authorization.account != address(0)) {
            COOLER.setAuthorizationWithSig(authorization, signature);
        }

        _DEBT_TOKEN.safeTransferFrom(msg.sender, address(this), repayAmount);
        COOLER.repay(repayAmount, msg.sender);
        COOLER.withdrawCollateral(collateralAmount, msg.sender, msg.sender, delegationRequests);

        // Return excess debt token to the caller
        // This can happen if the repayment amount is greater than the debt
        uint256 debtTokenBalance = _DEBT_TOKEN.balanceOf(address(this));
        if (debtTokenBalance > 0) {
            _DEBT_TOKEN.safeTransfer(msg.sender, debtTokenBalance);
            emit TokenRefunded(address(_DEBT_TOKEN), msg.sender, debtTokenBalance);
        }
    }

    // ===== View Functions ===== //

    /// @inheritdoc ICoolerComposites
    function collateralToken() external view returns (IERC20) {
        return IERC20(address(_COLLATERAL_TOKEN));
    }

    /// @inheritdoc ICoolerComposites
    function debtToken() external view returns (IERC20) {
        return IERC20(address(_DEBT_TOKEN));
    }

    // ============ ENABLER FUNCTIONS ============ //

    modifier onlyEnabled() {
        if (!isEnabled) revert NotEnabled();
        _;
    }

    /// @inheritdoc IEnabler
    function enable(bytes calldata) external onlyOwner {
        // Validate that the contract is disabled
        if (isEnabled) revert NotDisabled();

        // Enable the contract
        isEnabled = true;

        // Emit the enabled event
        emit Enabled();
    }

    /// @inheritdoc IEnabler
    function disable(bytes calldata) external onlyEnabled onlyOwner {
        // Disable the contract
        isEnabled = false;

        // Emit the disabled event
        emit Disabled();
    }
}
