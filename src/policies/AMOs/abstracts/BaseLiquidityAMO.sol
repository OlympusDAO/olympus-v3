// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {BaseBorrower} from "policies/abstracts/BaseBorrower.sol";
import {Kernel} from "src/Kernel.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import external dependencies
import {IVault, JoinPoolRequest, ExitPoolRequest} from "src/interfaces/IBalancerVault.sol";
import {IBasePool} from "src/interfaces/IBasePool.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus Base Liquidity AMO
contract BaseLiquidityAMO is BaseBorrower, ReentrancyGuard {
    // ========= STATE ========= //

    // Tokens
    ERC20 public ohm;
    ERC20 public pairToken;

    // Balancer Vault
    IVault public vault;

    // Liquidity Pool
    address public balancerPool; // Pair token/OHM Balancer pool

    // User State
    mapping(address => uint256) public pairTokenDeposits; // User pair token deposits
    mapping(address => uint256) public lpPositions; // User LP positions

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address pairToken_,
        address vault_,
        address balancerPool_
    ) BaseBorrower(kernel_) {
        // Set tokens
        ohm = ERC20(ohm_);
        pairToken = ERC20(pairToken_);

        // Set Balancer addresses
        vault = IVault(vault_);
        balancerPool = balancerPool_;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @dev    This needs to be non-reentrant since the contract only knows the amount of LP tokens it
    ///         receives after an external interaction with the Balancer pool
    function deposit(uint256 amount_) external override nonReentrant returns (uint256 lpAmountOut) {
        // Update state about user's deposits and borrows
        pairTokenDeposits[msg.sender] += amount_;

        // Take pair token from user
        pairToken.transferFrom(msg.sender, address(this), amount_);

        // Borrow OHM
        uint256 ohmToBorrow = _valueCollateral(amount_);
        _borrow(ohmToBorrow);

        // OHM-PAIR BPT before
        uint256 bptBefore = ERC20(address(balancerPool)).balanceOf(address(this));

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmToBorrow;
        maxAmountsIn[1] = amount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, 0), // need to change last parameter based on estimate of LP received
            fromInternalBalance: false
        });

        // Join Balancer pool
        ohm.approve(address(vault), ohmToBorrow);
        pairToken.approve(address(vault), amount_);
        vault.joinPool(
            IBasePool(balancerPool).getPoolId(),
            address(this),
            address(this),
            joinPoolRequest
        );

        // OHM-PAIR BPT after
        lpAmountOut = ERC20(address(balancerPool)).balanceOf(address(this)) - bptBefore;

        // Update user's LP position
        lpPositions[msg.sender] += lpAmountOut;
    }

    /// @dev    This needs to be non-reentrant since the contract only knows the amount of OHM and
    ///         pair tokens it receives after an external call to withdraw liquidity from Balancer
    function withdraw(uint256 lpAmount_) external override nonReentrant returns (uint256) {
        lpPositions[msg.sender] -= lpAmount_;

        // OHM and pair token amounts before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 pairTokenBefore = pairToken.balanceOf(address(this));

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 0; // TODO: find way to calculate without adding function args
        minAmountsOut[1] = 0; // TODO: find way to calculate without adding function args

        ExitPoolRequest memory exitPoolRequest = ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(1, lpAmount_),
            toInternalBalance: false
        });

        // Exit Balancer pool
        ERC20(address(balancerPool)).approve(address(vault), lpAmount_);
        vault.exitPool(
            IBasePool(balancerPool).getPoolId(),
            address(this),
            payable(address(this)),
            exitPoolRequest
        );

        // OHM and pair token amounts received
        uint256 ohmReceived = ohm.balanceOf(address(this)) - ohmBefore;
        uint256 pairTokenReceived = pairToken.balanceOf(address(this)) - pairTokenBefore;

        // Reduce debt and deposit values
        uint256 userDebt = debtOutstanding[msg.sender];
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        uint256 ohmToRepay = ohmReceived > userDebt ? userDebt : ohmReceived;
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;

        // Return assets
        _repay(ohmToRepay);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view virtual returns (uint256) {}
}
