// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity ^0.8.15;

// Interfaces
import {ICoolerCompositesV2} from "src/periphery/interfaces/ICoolerCompositesV2.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ICoolerComposites} from "src/periphery/interfaces/ICoolerComposites.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";

// Libraries
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";

// Periphery
import {PeripheryEnabler} from "src/periphery/PeripheryEnabler.sol";

/// @title  Cooler Composites V2
/// @notice The CoolerCompositesV2 contract enables users to combine multiple operations into a single call,
///         with added support for auto-delegation and OHM/gOHM staking.
contract CoolerCompositesV2 is Owned, PeripheryEnabler, ICoolerCompositesV2, IVersioned {
    using SafeTransferLib for ERC20;

    // ========= STATE ========= //

    /// @notice The address of the Cooler v2 contract
    /// @dev    This address is immutable and cannot be changed
    IMonoCooler public immutable COOLER;

    /// @notice The address of the staking contract
    /// @dev    This address is immutable and cannot be changed
    IStaking public immutable STAKING;

    /// @notice The address of the Cooler v2 collateral token
    /// @dev    This address is fetched at the time of deployment
    ERC20 internal immutable _COLLATERAL_TOKEN;

    /// @notice The address of the OHM token
    /// @dev    This address is fetched at the time of deployment
    ERC20 internal immutable _OHM;

    // ========= CONSTRUCTOR ========= //

    constructor(address owner_, IMonoCooler cooler_, IStaking staking_) Owned(owner_) {
        COOLER = cooler_;
        STAKING = staking_;

        _COLLATERAL_TOKEN = ERC20(address(cooler_.collateralToken()));
        _COLLATERAL_TOKEN.approve(address(cooler_), type(uint256).max);

        _OHM = ERC20(address(staking_.OHM()));

        // Validate that the collateral token is the same as the staking token
        if (address(_COLLATERAL_TOKEN) != address(staking_.gOHM()))
            revert Params_CollateralTokenMismatch(
                address(_COLLATERAL_TOKEN),
                address(staking_.gOHM())
            );
    }

    // ========= ICoolerCompositesV2 IMPLEMENTATION ========= //

    function _getGohmAmount(
        uint128 collateralAmount_,
        bool useGohm_
    ) internal view returns (uint128) {
        // No conversion necessary if using gOHM
        if (useGohm_) return collateralAmount_;

        // Otherwise, convert OHM to gOHM
        return
            SafeCast.encodeUInt128(IgOHM(address(_COLLATERAL_TOKEN)).balanceTo(collateralAmount_));
    }

    /// @inheritdoc ICoolerCompositesV2
    ///
    /// @return remainingBorrowable If unsuccessful, this return value will reflect the maximum amount borrowable after depositing the collateral
    function previewAddCollateralAndBorrow(
        uint128 collateralAmount_,
        uint128 borrowAmount_,
        bool useGohm_
    ) external view returns (bool, uint256, uint256) {
        // Convert the collateral amount to gOHM (if needed)
        uint128 gOhmCollateralDelta = _getGohmAmount(collateralAmount_, useGohm_);

        // Obtain the current account position
        IMonoCooler.AccountPosition memory originalPosition = COOLER.accountPosition(msg.sender);
        int128 maxDebtDelta = COOLER.debtDeltaForMaxOriginationLtv(
            msg.sender,
            int128(gOhmCollateralDelta)
        );

        uint256 totalGohmCollateral = originalPosition.collateral + gOhmCollateralDelta;

        // Validate that maxDebtDelta is positive
        if (maxDebtDelta < 0) {
            return (false, totalGohmCollateral, 0);
        }

        // Validate that the LLTV will not be exceeded by the borrow
        uint128 maxDebtDeltaPositive = uint128(maxDebtDelta);
        if (maxDebtDeltaPositive < borrowAmount_) {
            return (false, totalGohmCollateral, maxDebtDeltaPositive);
        }

        return (true, totalGohmCollateral, maxDebtDeltaPositive - borrowAmount_);
    }

    /// @inheritdoc ICoolerCompositesV2
    /// @dev        This function is used to add collateral and borrow from the Cooler contract in a single call
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - Delegation requests are provided while auto-delegation is true
    ///             - The staking warmup period is active and the caller is supplying OHM as collateral
    ///             - The caller has not provided the required authorization and signature
    function addCollateralAndBorrow(
        IMonoCooler.Authorization calldata authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests,
        bool autoDelegate,
        bool useGohm
    ) public onlyEnabled {
        // Validate that the delegation requests are not provided while auto-delegation is true
        if (autoDelegate && delegationRequests.length > 0) {
            revert DelegationRequestsInvalid();
        }

        // Set authorization if provided
        if (authorization.account != address(0)) {
            COOLER.setAuthorizationWithSig(authorization, signature);
        }

        // Pull collateral from the caller and convert to gOHM if necessary
        uint256 gohmAmount = _pullCollateral(collateralAmount, useGohm);

        // Create delegation requests if auto-delegation is enabled
        IDLGTEv1.DelegationRequest[] memory requests = delegationRequests;
        if (autoDelegate) {
            requests = new IDLGTEv1.DelegationRequest[](1);
            requests[0] = IDLGTEv1.DelegationRequest({
                delegate: msg.sender,
                amount: int256(gohmAmount)
            });
        }

        // Add collateral to the Cooler contract
        COOLER.addCollateral(uint128(gohmAmount), msg.sender, requests);

        // Borrow from the Cooler contract
        COOLER.borrow(borrowAmount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICoolerCompositesV2
    ///
    /// @return remainingGohmCollateral If unsuccesful, returns the current collateral amount
    /// @return remainingDebt   If unsuccessful, returns the current debt amount
    function previewRepayAndRemoveCollateral(
        uint128 repayAmount_,
        uint128 collateralAmount_,
        bool useGohm_
    ) external view returns (bool, uint256, uint256) {
        // Convert the collateral amount to gOHM (if needed)
        uint128 gOhmCollateralDelta = _getGohmAmount(collateralAmount_, useGohm_);

        // Obtain the current account position
        IMonoCooler.AccountPosition memory originalPosition = COOLER.accountPosition(msg.sender);
        int128 maxDebtDelta = COOLER.debtDeltaForMaxOriginationLtv(
            msg.sender,
            -int128(gOhmCollateralDelta)
        );

        // Validate that there is enough gOHM collateral
        if (originalPosition.collateral < gOhmCollateralDelta) {
            return (false, originalPosition.collateral, originalPosition.currentDebt);
        }

        uint256 totalGohmCollateral = originalPosition.collateral - gOhmCollateralDelta;

        // Validate that the LLTV will not be exceeded by the repay and withdraw
        uint128 maxDebtDeltaPositive = uint128(maxDebtDelta);
        if (maxDebtDeltaPositive < repayAmount_) {
            return (false, totalGohmCollateral, originalPosition.currentDebt);
        }

        // Validate that the caller is not over-paying
        if (originalPosition.currentDebt < repayAmount_) {
            return (false, totalGohmCollateral, 0);
        }

        return (true, totalGohmCollateral, originalPosition.currentDebt - repayAmount_);
    }

    /// @inheritdoc ICoolerCompositesV2
    /// @dev        This function is used to repay debt and remove collateral from the Cooler contract in a single call
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - Delegation requests are provided while auto-delegation is true
    ///             - The caller has not provided the required authorization and signature
    function repayAndRemoveCollateral(
        IMonoCooler.Authorization calldata authorization,
        IMonoCooler.Signature calldata signature,
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests,
        bool autoDelegate,
        bool useGohm
    ) public onlyEnabled {
        // Validate that the delegation requests are not provided while auto-delegation is true
        if (autoDelegate && delegationRequests.length > 0) {
            revert DelegationRequestsInvalid();
        }

        // Set authorization if provided
        if (authorization.account != address(0)) {
            COOLER.setAuthorizationWithSig(authorization, signature);
        }

        // Pull debt token from the caller
        ERC20 coolerDebtToken = ERC20(address(COOLER.debtToken()));
        coolerDebtToken.safeTransferFrom(msg.sender, address(this), repayAmount);

        // Repay debt
        coolerDebtToken.safeApprove(address(COOLER), repayAmount);
        COOLER.repay(repayAmount, msg.sender);

        // Create delegation requests if auto-delegation is enabled
        IDLGTEv1.DelegationRequest[] memory requests = delegationRequests;
        if (autoDelegate) {
            requests = new IDLGTEv1.DelegationRequest[](1);
            requests[0] = IDLGTEv1.DelegationRequest({
                delegate: msg.sender,
                amount: -int256(uint256(collateralAmount))
            });
        }

        // Withdraw collateral from the Cooler contract
        COOLER.withdrawCollateral(collateralAmount, address(this), msg.sender, requests);

        // Transfer gOHM or OHM to the caller
        if (useGohm) {
            _COLLATERAL_TOKEN.safeTransfer(msg.sender, collateralAmount);
        } else {
            _COLLATERAL_TOKEN.approve(address(STAKING), collateralAmount);
            STAKING.unstake(msg.sender, collateralAmount, false, false);
        }

        // Return excess debt token to the caller
        uint256 debtTokenBalance = coolerDebtToken.balanceOf(address(this));
        if (debtTokenBalance > 0) {
            coolerDebtToken.safeTransfer(msg.sender, debtTokenBalance);
            emit TokenRefunded(address(coolerDebtToken), msg.sender, debtTokenBalance);
        }
    }

    // ========= ICoolerComposites ========= //

    /// @inheritdoc ICoolerComposites
    function addCollateralAndBorrow(
        IMonoCooler.Authorization calldata authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override {
        addCollateralAndBorrow(
            authorization,
            signature,
            collateralAmount,
            borrowAmount,
            delegationRequests,
            false, // auto-delegation is disabled
            false // use gOHM as collateral
        );
    }

    /// @inheritdoc ICoolerComposites
    function repayAndRemoveCollateral(
        IMonoCooler.Authorization calldata authorization,
        IMonoCooler.Signature calldata signature,
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override {
        repayAndRemoveCollateral(
            authorization,
            signature,
            repayAmount,
            collateralAmount,
            delegationRequests,
            false, // auto-delegation is disabled
            false // use gOHM as collateral
        );
    }

    // ========= HELPER FUNCTIONS ========= //

    /// @notice     Pull collateral from the caller and convert to gOHM if necessary
    ///
    /// @param  collateralAmount    Amount of collateral to pull
    /// @param  useGohm             Whether the caller is supplying OHM (false) or gOHM (true) as collateral
    /// @return gOhmAmount          Resulting amount of gOHM
    function _pullCollateral(
        uint128 collateralAmount,
        bool useGohm
    ) internal returns (uint128 gOhmAmount) {
        // If using gOHM, pull the collateral from the caller
        if (useGohm) {
            gOhmAmount = collateralAmount;
            _COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), gOhmAmount);
            return gOhmAmount;
        }

        // Otherwise OHM is being supplied by the caller
        // Validate that the warmup period is 0, otherwise staking to gOHM is not possible
        if (STAKING.warmupPeriod() > 0) revert OhmWarmupPeriodActive();

        // Pull OHM from the caller
        _OHM.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Stake to gOHM
        _OHM.approve(address(STAKING), collateralAmount);
        gOhmAmount = SafeCast.encodeUInt128(
            STAKING.stake(address(this), collateralAmount, false, true)
        );

        return gOhmAmount;
    }

    // ========= VIEW FUNCTIONS ========= //

    /// @inheritdoc ICoolerComposites
    function collateralToken() external view override returns (IERC20) {
        return IERC20(address(_COLLATERAL_TOKEN));
    }

    /// @inheritdoc ICoolerComposites
    /// @dev        Returns the debt token address from the Cooler contract
    function debtToken() external view override returns (IERC20) {
        return IERC20(address(COOLER.debtToken()));
    }

    /// @notice     Address of the OHM token
    function OHM() external view returns (IERC20) {
        return IERC20(address(_OHM));
    }

    // ========= IVersioned ========= //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (2, 0);
    }

    // ========= PeripheryEnabler ========= //

    /// @inheritdoc PeripheryEnabler
    function _onlyOwner() internal view override {
        if (msg.sender != owner) revert OnlyOwner();
    }

    /// @inheritdoc PeripheryEnabler
    /// @dev        This function is empty
    function _enable(bytes calldata) internal override {}

    /// @inheritdoc PeripheryEnabler
    /// @dev        This function is empty
    function _disable(bytes calldata) internal override {}

    // ========= ERC165 IMPLEMENTATION ========= //

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(PeripheryEnabler) returns (bool) {
        return
            interfaceId == type(ICoolerCompositesV2).interfaceId ||
            interfaceId == type(ICoolerComposites).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function)
