// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Interfaces
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC7540Operator, IERC7540Redeem} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";
import {IERC7575} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7575.sol";
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin-5.7.0/token/ERC20/extensions/ERC4626.sol";

/// @notice Real contract caller; the originating EOA's allowance is deliberately irrelevant.
contract DepositManagerDonationActor {
    function donate(
        IDepositManagerV1_1 manager_,
        IERC20 asset_,
        address operator_,
        uint256 amount_
    ) external returns (uint256, uint256) {
        asset_.approve(address(manager_), amount_);
        return manager_.donate(asset_, operator_, amount_);
    }
}

/// @notice Donation-local fault and callback fixture, retaining the real proportional vault math.
contract DepositManagerDonationVault is ERC4626 {
    error ZeroShares();
    error DepositFailed();
    error ValuationFailed();
    error AsyncRedeem();

    bool public depositFails;
    bool public valuationFails;
    bool public valuationZero;
    bool public asyncRedeem;
    address public callbackTarget;
    bytes public callbackData;
    bytes public callbackError;
    bool public callbackAttempted;

    constructor(OZIERC20 asset_) ERC20("Donation fault vault", "DFV") ERC4626(asset_) {}

    function _convertToShares(
        uint256 assets_,
        Math.Rounding rounding_
    ) internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets_ : Math.mulDiv(assets_, supply, totalAssets(), rounding_);
    }

    function _convertToAssets(
        uint256 shares_,
        Math.Rounding rounding_
    ) internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares_ : Math.mulDiv(shares_, totalAssets(), supply, rounding_);
    }

    function setFaults(bool deposit_, bool valuation_, bool zero_) external {
        depositFails = deposit_;
        valuationFails = valuation_;
        valuationZero = zero_;
    }

    function setAsyncRedeem(bool async_) external {
        asyncRedeem = async_;
    }

    function share() external view returns (address) {
        return address(this);
    }

    function supportsInterface(bytes4 id_) external view returns (bool) {
        return
            id_ == type(IERC165).interfaceId ||
            id_ == (type(IERC4626).interfaceId ^ type(IERC7575).interfaceId) ||
            id_ == type(IERC7540Operator).interfaceId ||
            (asyncRedeem && id_ == type(IERC7540Redeem).interfaceId);
    }

    function setCallback(address target_, bytes calldata data_) external {
        callbackTarget = target_;
        callbackData = data_;
    }

    function deposit(uint256 assets_, address receiver_) public override returns (uint256 shares) {
        if (depositFails) revert DepositFailed();
        if (previewDeposit(assets_) == 0) revert ZeroShares();
        shares = super.deposit(assets_, receiver_);
        if (callbackTarget != address(0)) {
            callbackAttempted = true;
            (, callbackError) = callbackTarget.call(callbackData);
        }
    }

    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        if (asyncRedeem) revert AsyncRedeem();
        if (shares_ != 0 && valuationFails) revert ValuationFailed();
        if (valuationZero) return 0;
        return super.previewRedeem(shares_);
    }

    function convertToAssets(uint256 shares_) public view override returns (uint256) {
        if (shares_ != 0 && valuationFails) revert ValuationFailed();
        if (valuationZero) return 0;
        return super.convertToAssets(shares_);
    }
}
