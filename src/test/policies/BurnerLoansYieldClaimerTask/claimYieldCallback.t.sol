// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Contracts
import {YieldClaimerModularTest} from "./fixtures/YieldClaimerModularTest.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

contract BurnerLoansYieldClaimerTaskClaimYieldCallbackTest is YieldClaimerModularTest {
    ReentrantFeeToken internal _callbackToken;
    MockERC4626 internal _callbackVault;

    function setUp() public override {
        super.setUp();
        _callbackToken = new ReentrantFeeToken();
        _callbackVault = new MockERC4626(OZERC20(address(_callbackToken)), "Callback vault", "CV");
        _admitVault(address(_callbackToken), address(_callbackVault), false);
        _deposit(address(_callbackToken), 2000);
        _callbackToken.mint(address(_callbackVault), 100);
        _yieldAsset.mint(address(_yieldVault), 3);
    }

    function _arm(bool propagate_) internal {
        _callbackToken.setCallbackFrom(
            address(_callbackVault),
            address(_claimer),
            abi.encodeCall(_claimer.claimYield, (address(_yieldAsset)))
        );
        _callbackToken.setCallbackPhases(true, false);
        _callbackToken.setBubbleCallbackFailure(propagate_);
    }

    // Scenarios: BLYC-CLAIM-YIELD-C01.
    function test_givenCaughtTokenCallback_whenClaimed() public {
        bytes32 quoteBefore = _state();
        assertEq(
            _claimer.previewClaimYield(address(_callbackToken)).amountOut,
            98,
            "Independent pre-callback quote"
        );
        assertEq(_state(), quoteBefore, "Preview changes no custody or callback state");
        _arm(false);
        uint256 before = _callbackToken.balanceOf(_payout.treasury());
        (, uint256 amount) = _claimer.claimYield(address(_callbackToken));
        // floor((100-1)*2000/2100)=94 shares; floor(94*2100/2000)=98 raw underlying.
        assertEq(amount, 98, "Outer claim pays exactly once");
        assertEq(_callbackToken.balanceOf(_payout.treasury()) - before, 98, "Exact direct output");
        assertFalse(
            _callbackToken.callbackSucceeded(),
            "Authorized nested settlement reaches shared Core guard"
        );
        assertEq(
            _callbackToken.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Exact guard rejection"
        );
        assertEq(
            _claimer.previewClaimYield(address(_yieldAsset)).amountOut,
            1,
            "Other eligible market remains unclaimed"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_callbackToken)), address(_core)),
            2000,
            "Liabilities preserved"
        );
        _assertNoPayoutCustody(address(_callbackToken));
    }

    // Scenarios: BLYC-CLAIM-YIELD-C02.
    function test_givenPropagatedTokenCallback_whenClaimed_reverts() public {
        assertEq(
            _claimer.previewClaimYield(address(_callbackToken)).amountOut,
            98,
            "Quote does not invoke execution callback"
        );
        _arm(true);
        bytes32 before = _state();
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        _claimer.claimYield(address(_callbackToken));
        assertEq(
            _state(),
            before,
            "Failure rolls back shares, assets, liabilities, approvals, reserves and cursor"
        );
        _callbackToken.setBubbleCallbackFailure(false);
        (, uint256 amount) = _claimer.claimYield(address(_callbackToken));
        assertEq(amount, 98, "Restoration allows exact retry");
    }

    function _state() internal view returns (bytes32) {
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(
            IERC20(address(_callbackToken)),
            address(_core)
        );
        (uint256 fees, uint256 seized, uint256 total) = _payout.payoutReserves(
            address(_callbackToken)
        );
        bytes32 custody = keccak256(
            abi.encode(
                shares,
                assets,
                _callbackToken.balanceOf(address(_callbackVault)),
                _callbackToken.balanceOf(_payout.treasury()),
                _callbackVault.balanceOf(address(_depositManager)),
                _callbackToken.allowance(address(_depositManager), address(_callbackVault))
            )
        );
        return
            keccak256(
                abi.encode(
                    custody,
                    _depositManager.getOperatorLiabilities(
                        IERC20(address(_callbackToken)),
                        address(_core)
                    ),
                    _core.totalActiveDebtOhm(),
                    _claimer.nextAssetIndex(),
                    _callbackToken.callbackEnabled(),
                    fees,
                    seized,
                    total
                )
            );
    }
}
