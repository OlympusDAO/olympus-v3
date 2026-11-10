// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateralVaultTest} from "./BurnerLoansCollateralVaultTest.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

abstract contract BurnerLoansCollateralTokenCallbackTest is BurnerLoansCollateralVaultTest {
    ReentrantFeeToken internal _token;
    MockERC4626 internal _vault;

    function _prepareDirectToken() internal {
        _token = new ReentrantFeeToken();
        _price.setPrice(address(_token), 1e18);
        _admit(address(_token));
        _fundCallbackParticipants();
    }

    function _prepareVaultToken() internal {
        _token = new ReentrantFeeToken();
        _vault = new MockERC4626(OZERC20(address(_token)), "Callback vault", "CV");
        _admitVault(_token, address(_vault), false);
        _fundCallbackParticipants();
    }

    function _fundCallbackParticipants() internal {
        _depositAsset(_token, 10e18, _borrower);
        _depositAsset(_token, 17, _OTHER_BORROWER);
        _token.mint(_borrower, 2e18);
        _token.mint(_recipient, 2e18);
        _token.mint(address(_token), 1e18);
        vm.prank(_recipient);
        _token.approve(address(_core), type(uint256).max);
        vm.prank(address(_token));
        _token.approve(address(_core), type(uint256).max);
        vm.startPrank(_borrower);
        _approveOperatorForAsset(_borrower, address(_token), type(uint48).max, address(_token));
        _approveOperatorForAsset(_borrower, _recipient, type(uint48).max, address(_token));
        vm.stopPrank();
    }

    function _armNestedDeposit(address invoker_) internal {
        _token.setCallbackFrom(
            invoker_,
            address(_collateral),
            abi.encodeCall(_collateral.depositCollateral, (address(_token), uint128(1), _borrower))
        );
    }

    function _armNestedWithdrawal(address invoker_) internal {
        _token.setCallbackFrom(
            invoker_,
            address(_collateral),
            abi.encodeCall(
                _collateral.withdrawCollateral,
                (address(_token), uint128(1), _borrower, address(_token))
            )
        );
    }

    function _armCoreConfiguration(address invoker_) internal {
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_token));
        _token.setCallbackFrom(
            invoker_,
            address(_core),
            abi.encodeCall(_core.setGracePeriod, (uint32(1)))
        );
    }

    function _assertGuardCaught() internal view {
        assertFalse(_token.callbackSucceeded(), "Nested action is rejected");
        assertEq(
            _token.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Funded and authorized nested action reaches Core guard"
        );
        assertEq(
            _lens.getPosition(address(_token), _OTHER_BORROWER).depositedCollateral,
            17,
            "Unrelated position is preserved"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
