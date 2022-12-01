// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {LENDRv1} from "src/modules/LENDR/LENDR.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import external dependencies
import {IVault, JoinPoolRequest, ExitPoolRequest} from "src/interfaces/IBalancerVault.sol";
import {IBasePool} from "src/interfaces/IBasePool.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus Base Liquidity AMO
contract BaseLiquidityAMO is Policy, ReentrancyGuard, RolesConsumer {
    // ========= STATE ========= //

    // Modules
    LENDRv1 public LENDR;
    MINTRv1 public MINTR;

    // Tokens
    ERC20 public ohm;
    ERC20 public pairToken;

    // Balancer Vault
    IVault public vault;

    // Liquidity Pool
    address public balancerPool; // Pair token/OHM Balancer pool

    // User State
    mapping(address => uint256) public pairTokenDeposits; // User pair token deposits
    mapping(address => uint256) public ohmDebtOutstanding; // OHM debt outstanding
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
    ) Policy(kernel_) {
        // Set tokens
        ohm = ERC20(ohm_);
        pairToken = ERC20(pairToken_);

        // Set Balancer addresses
        vault = IVault(vault_);
        balancerPool = balancerPool_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("LENDR");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        LENDR = LENDRv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](6);
        permissions[0] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(MINTR.KEYCODE(), MINTR.decreaseMintApproval.selector);
        permissions[4] = Permissions(LENDR.KEYCODE(), LENDR.borrow.selector);
        permissions[5] = Permissions(LENDR.KEYCODE(), LENDR.repay.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @dev    This needs to be non-reentrant since the contract only knows the amount of LP tokens it
    ///         receives after an external interaction with the Balancer pool
    function depositAndLP(uint256 pairTokenAmount_)
        external
        nonReentrant
        returns (uint256 lpAmountOut)
    {
        // Calculate how much OHM the user needs to borrow
        uint256 ohmToBorrow = _valueCollateral(pairTokenAmount_);

        // Update state about user's deposits and borrows
        pairTokenDeposits[msg.sender] += pairTokenAmount_;
        ohmDebtOutstanding[msg.sender] += ohmToBorrow;

        // Take pair token from user
        pairToken.transferFrom(msg.sender, address(this), pairTokenAmount_);

        // Borrow OHM
        LENDR.borrow(ohmToBorrow);
        MINTR.mintOhm(address(this), ohmToBorrow);

        // OHM-PAIR BPT before
        uint256 bptBefore = ERC20(address(balancerPool)).balanceOf(address(this));

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmToBorrow;
        maxAmountsIn[1] = pairTokenAmount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, 0), // need to change last parameter based on estimate of LP received
            fromInternalBalance: false
        });

        // Join Balancer pool
        ohm.approve(address(vault), ohmToBorrow);
        pairToken.approve(address(vault), pairTokenAmount_);
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
    function unwindAndRepay(
        uint256 lpAmount_,
        uint256 expectedOhmAmount_,
        uint256 expectedPairTokenAmount_
    ) external nonReentrant returns (uint256) {
        lpPositions[msg.sender] -= lpAmount_;

        // OHM and pair token amounts before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 pairTokenBefore = pairToken.balanceOf(address(this));

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = expectedOhmAmount_;
        minAmountsOut[1] = expectedPairTokenAmount_;

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
        uint256 userDebt = ohmDebtOutstanding[msg.sender];
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        ohmDebtOutstanding[msg.sender] -= ohmReceived > userDebt ? userDebt : ohmReceived;
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;
        LENDR.repay(ohmReceived > userDebt ? userDebt : ohmReceived);

        // Return assets
        MINTR.burnOhm(address(this), ohmReceived);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view virtual returns (uint256) {}
}
