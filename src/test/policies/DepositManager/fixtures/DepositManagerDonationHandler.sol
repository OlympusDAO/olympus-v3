// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Three real custody routes and two independent namespaces, including external losses.
/// @dev Models raw share, receipt-principal and debt changes independently. Small handler transfers
///      keep sequence exploration fast; unit tests independently cover full uint256 boundaries.
contract DepositManagerDonationHandler is Test {
    DepositManager internal immutable _MANAGER;
    address internal immutable _ADMIN;
    MockERC20[3] internal _assets;
    address[3] internal _vaults;
    IERC20[3] internal _custody;
    address[2] internal _operators;
    address[2] internal _donors;
    uint256[2][3] internal _shares;
    uint256[2][3] internal _principal;
    uint256[2][3] internal _borrowed;
    uint256[3] internal _unsolicited;

    uint256 public donations;
    uint256 public deposits;
    uint256 public withdrawals;
    uint256 public yieldClaims;
    uint256 public borrows;
    uint256 public repayments;
    uint256 public violations;

    constructor(
        DepositManager manager_,
        address admin_,
        MockERC20[3] memory assets_,
        address[3] memory vaults_,
        IERC20[3] memory custody_,
        address[2] memory operators_,
        address[2] memory donors_
    ) {
        _MANAGER = manager_;
        _ADMIN = admin_;
        _assets = assets_;
        _vaults = vaults_;
        _custody = custody_;
        _operators = operators_;
        _donors = donors_;
    }

    function _fund(uint256 route_, address payer_, uint256 amount_) internal {
        _assets[route_].mint(payer_, amount_);
        vm.prank(payer_);
        _assets[route_].approve(address(_MANAGER), amount_);
    }

    function _toShares(uint256 route_, uint256 amount_) internal view returns (uint256) {
        if (route_ == 0) return amount_;
        uint256 supply = _custody[route_].totalSupply();
        if (supply == 0) return route_ == 2 ? amount_ / 1e12 : amount_;
        uint256 backing = _assets[route_].balanceOf(_vaults[route_]);
        if (backing == 0 && route_ == 2) return amount_ / 1e12;
        return Math.mulDiv(amount_, supply, backing);
    }

    function _value(uint256 route_, uint256 shares_) internal view returns (uint256) {
        if (route_ == 0) return shares_;
        uint256 supply = _custody[route_].totalSupply();
        if (supply == 0) return route_ == 2 ? shares_ * 1e12 : shares_;
        return Math.mulDiv(shares_, _assets[route_].balanceOf(_vaults[route_]), supply);
    }

    function _model(uint256 route_) internal view returns (bytes32) {
        IERC20 token = IERC20(address(_assets[route_]));
        uint256[2] memory receipts;
        uint256[2] memory liabilities;
        uint256[2] memory debt;
        for (uint256 i; i < 2; ++i) {
            uint256 id = _MANAGER.getReceiptTokenId(token, 1, _operators[i]);
            receipts[i] = _MANAGER.getReceiptTokenManager().balanceOf(_operators[i], id);
            liabilities[i] = _MANAGER.getOperatorLiabilities(token, _operators[i]);
            debt[i] = _MANAGER.getBorrowedAmount(token, _operators[i]);
        }
        return
            keccak256(
                abi.encode(
                    receipts,
                    liabilities,
                    debt,
                    _MANAGER.getAssetDepositCapStatus(token).utilization
                )
            );
    }

    function donate(
        uint8 routeSeed_,
        uint8 operatorSeed_,
        uint8 donorSeed_,
        uint96 amountSeed_
    ) external {
        uint256 r = routeSeed_ % 3;
        uint256 o = operatorSeed_ % 2;
        address donor = _donors[donorSeed_ % 2];
        uint256 amount = bound(uint256(amountSeed_), 1, 1e18);
        _fund(r, donor, amount);
        uint256 expectedShares = _toShares(r, amount);
        bytes32 beforeModel = _model(r);
        vm.prank(donor);
        try _MANAGER.donate(IERC20(address(_assets[r])), _operators[o], amount) returns (
            uint256 credit,
            uint256 shares
        ) {
            if (shares != expectedShares || credit != _value(r, expectedShares)) ++violations;
            _shares[r][o] += expectedShares;
            if (_model(r) != beforeModel) ++violations;
            ++donations;
        } catch {}
    }

    function deposit(uint8 routeSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 r = routeSeed_ % 3;
        uint256 o = operatorSeed_ % 2;
        uint256 amount = bound(uint256(amountSeed_), 1, 1e18);
        _fund(r, _operators[o], amount);
        uint256 expectedShares = _toShares(r, amount);
        vm.prank(_operators[o]);
        try
            _MANAGER.deposit(
                IDepositManager.DepositParams(
                    IERC20(address(_assets[r])),
                    1,
                    _operators[o],
                    amount,
                    false
                )
            )
        returns (uint256, uint256 credit) {
            uint256 expectedCredit = _value(r, expectedShares);
            if (credit != expectedCredit) ++violations;
            _shares[r][o] += expectedShares;
            _principal[r][o] += expectedCredit;
            if (_value(r, _shares[r][o]) + _borrowed[r][o] < _principal[r][o]) ++violations;
            ++deposits;
        } catch {}
    }

    function gain(uint8 routeSeed_, uint96 amountSeed_) external {
        uint256 r = 1 + (routeSeed_ % 2);
        _assets[r].mint(_vaults[r], bound(uint256(amountSeed_), 1, 1e18));
    }

    function loss(uint8 routeSeed_, uint96 amountSeed_) external {
        uint256 r = 1 + (routeSeed_ % 2);
        uint256 backing = _assets[r].balanceOf(_vaults[r]);
        // Leave one raw backing unit so the real proportional conversion remains defined.
        if (backing <= 1) return;
        _assets[r].burn(_vaults[r], bound(uint256(amountSeed_), 1, backing - 1));
    }

    function withdraw(uint8 routeSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 r = routeSeed_ % 3;
        uint256 o = operatorSeed_ % 2;
        if (_principal[r][o] == 0) return;
        uint256 amount = bound(uint256(amountSeed_), 1, _principal[r][o]);
        uint256 expectedShares = _toShares(r, amount);
        IERC20 token = IERC20(address(_assets[r]));
        uint256 id = _MANAGER.getReceiptTokenId(token, 1, _operators[o]);
        vm.startPrank(_operators[o]);
        _MANAGER.getReceiptTokenManager().approve(address(_MANAGER), id, amount);
        try
            _MANAGER.withdraw(
                IDepositManager.WithdrawParams(
                    token,
                    1,
                    _operators[o],
                    _operators[o],
                    amount,
                    false
                )
            )
        returns (uint256 output) {
            // BaseAssetManager deliberately preserves shares when conversion yields zero output.
            if (output != 0) _shares[r][o] -= expectedShares;
            _principal[r][o] -= amount;
            ++withdrawals;
        } catch {}
        vm.stopPrank();
    }

    function claimYield(uint8 routeSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 r = routeSeed_ % 3;
        uint256 o = operatorSeed_ % 2;
        uint256 value = _value(r, _shares[r][o]);
        uint256 netLiability = _principal[r][o] >= _borrowed[r][o]
            ? _principal[r][o] - _borrowed[r][o]
            : 0;
        if (value <= netLiability) return;
        uint256 amount = bound(uint256(amountSeed_), 1, value - netLiability);
        uint256 expectedShares = _toShares(r, amount);
        vm.prank(_operators[o]);
        try _MANAGER.claimYield(IERC20(address(_assets[r])), _operators[o], amount) returns (
            uint256 output
        ) {
            if (output != 0) _shares[r][o] -= expectedShares;
            ++yieldClaims;
        } catch {}
    }

    function borrow(uint8 routeSeed_, uint8 operatorSeed_, uint96 amountSeed_) external {
        uint256 r = routeSeed_ % 3;
        uint256 o = operatorSeed_ % 2;
        if (_borrowed[r][o] >= _principal[r][o]) return;
        uint256 capacity = _principal[r][o] - _borrowed[r][o];
        uint256 amount = bound(uint256(amountSeed_), 1, capacity);
        uint256 expectedShares = _toShares(r, amount);
        vm.prank(_operators[o]);
        try
            _MANAGER.borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams(
                    IERC20(address(_assets[r])),
                    _operators[o],
                    amount
                )
            )
        returns (uint256 output) {
            if (output != 0) _shares[r][o] -= expectedShares;
            _borrowed[r][o] += amount;
            ++borrows;
        } catch {}
    }

    function repay(
        uint8 routeSeed_,
        uint8 operatorSeed_,
        uint8 donorSeed_,
        uint96 amountSeed_
    ) external {
        uint256 r = routeSeed_ % 3;
        uint256 o = operatorSeed_ % 2;
        if (_borrowed[r][o] == 0) return;
        uint256 amount = bound(uint256(amountSeed_), 1, _borrowed[r][o]);
        address payer = _donors[donorSeed_ % 2];
        _fund(r, payer, amount);
        uint256 expectedShares = _toShares(r, amount);
        vm.prank(_operators[o]);
        try
            _MANAGER.borrowingRepay(
                IDepositManager.BorrowingRepayParams(
                    IERC20(address(_assets[r])),
                    payer,
                    amount,
                    amount
                )
            )
        returns (uint256 credit) {
            uint256 expectedCredit = _value(r, expectedShares);
            if (credit != expectedCredit) ++violations;
            _shares[r][o] += expectedShares;
            _borrowed[r][o] -= expectedCredit < amount ? expectedCredit : amount;
            ++repayments;
        } catch {}
    }

    function unsolicited(uint8 routeSeed_, uint96 amountSeed_) external {
        uint256 r = routeSeed_ % 3;
        uint256 amount = bound(uint256(amountSeed_), 1e12, 1e18);
        if (r == 0) {
            _assets[r].mint(address(_MANAGER), amount);
            _unsolicited[r] += amount;
        } else {
            _assets[r].mint(address(this), amount);
            _assets[r].approve(_vaults[r], amount);
            uint256 shares = IERC4626(_vaults[r]).deposit(amount, address(this));
            _custody[r].transfer(address(_MANAGER), shares);
            _unsolicited[r] += shares;
        }
    }

    function pauseResume() external {
        bool enabled = _MANAGER.isEnabled();
        vm.prank(_ADMIN);
        if (enabled) _MANAGER.disable("");
        else _MANAGER.reEnable();
    }

    // Scenarios: DM-DONATE-P15, DM-DONATE-P16, DM-DONATE-P17.
    function assertModels() public view {
        assertEq(violations, 0, "No donation, deposit or repayment accounting violations");
        for (uint256 r; r < 3; ++r) {
            IERC20 token = IERC20(address(_assets[r]));
            uint256 totalShares;
            uint256 totalPrincipal;
            for (uint256 o; o < 2; ++o) {
                (uint256 shares, ) = _MANAGER.getOperatorAssets(token, _operators[o]);
                assertEq(shares, _shares[r][o], "Independent namespace share model");
                assertEq(
                    _MANAGER.getOperatorLiabilities(token, _operators[o]),
                    _principal[r][o],
                    "Independent receipt liability model"
                );
                assertEq(
                    _MANAGER.getBorrowedAmount(token, _operators[o]),
                    _borrowed[r][o],
                    "Independent borrowed-principal model"
                );
                uint256 id = _MANAGER.getReceiptTokenId(token, 1, _operators[o]);
                assertEq(
                    _MANAGER.getReceiptTokenManager().balanceOf(_operators[o], id),
                    _principal[r][o],
                    "No donation creates receipt claims"
                );
                totalShares += _shares[r][o];
                totalPrincipal += _principal[r][o];
            }
            assertEq(
                _MANAGER.getAssetDepositCapStatus(token).utilization,
                totalPrincipal,
                "Cap tracks receipt principal only"
            );
            assertEq(
                _custody[r].balanceOf(address(_MANAGER)),
                totalShares + _unsolicited[r],
                "Physical custody equals allocated plus unsolicited units"
            );
        }
    }
}
