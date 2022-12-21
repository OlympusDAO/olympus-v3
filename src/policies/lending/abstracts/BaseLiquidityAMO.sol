// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {LENDRv1} from "src/modules/LENDR/LENDR.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus Base Liquidity AMO
contract BaseLiquidityAMO is Policy, ReentrancyGuard {
    // ========= DATA STRUCTURES ========= //

    struct UserDeposit {
        uint256 lpAmount;
        uint256 accumulatedRewards;
    }

    // ========= STATE ========= //

    // Modules
    MINTRv1 public MINTR;
    LENDRv1 public LENDR;

    // Tokens
    ERC20 public ohm;
    ERC20 public pairToken;

    // User State
    mapping(address => uint256) public pairTokenDeposits; // User pair token deposits
    mapping(address => UserDeposit) public userPositions; // User LP positions

    // Reward Token State
    address[] public rewardTokens;
    mapping(address => uint256) rewardsPerSecond;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address pairToken_
    ) Policy(kernel_) {
        // Set tokens
        ohm = ERC20(ohm_);
        pairToken = ERC20(pairToken_);
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
        Keycode memory mintrKeycode = MINTR.KEYCODE();
        Keycode memory lendrKeycode = LENDR.KEYCODE();

        permissions = new Permissions[](5);
        permissions[0] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.burnOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(lendrKeycode, LENDR.borrow.selector);
        permissions[4] = Permissions(lendrKeycode, LENDR.repay.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @dev    This needs to be non-reentrant since the contract only knows the amount of LP tokens it
    ///         receives after an external interaction with the Balancer pool
    function deposit(uint256 amount_) external nonReentrant returns (uint256 lpAmountOut) {
        UserDeposit memory currentDeposit = userPositions[msg.sender];

        // Update state about user's deposits and borrows
        pairTokenDeposits[msg.sender] += amount_;

        // Take pair token from user
        pairToken.transferFrom(msg.sender, address(this), amount_);

        // Borrow OHM
        uint256 ohmToBorrow = _valueCollateral(amount_);
        _borrow(ohmToBorrow);

        uint256 lpReceived = _deposit(ohmToBorrow, amount_);

        // Update user's LP position
        userPositions[msg.sender].lpAmount += lpReceived;
    }

    /// @dev    This needs to be non-reentrant since the contract only knows the amount of OHM and
    ///         pair tokens it receives after an external call to withdraw liquidity from Balancer
    function withdraw(uint256 lpAmount_) external nonReentrant returns (uint256) {
        // TODO: Check pool vs oracle price

        userPositions[msg.sender].lpAmount -= lpAmount_;

        (uint256 ohmReceived, uint256 pairTokenReceived) = _withdraw(lpAmount_);

        // Reduce deposit values
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;

        // Return assets
        _repay(ohmReceived);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    function withdrawAndClaim(uint256 lpAmount_) external nonReentrant returns (uint256) {
        // TODO: Check pool vs oracle price

        _claimRewards();

        userPositions[msg.sender].lpAmount -= lpAmount_;

        (uint256 ohmReceived, uint256 pairTokenReceived) = _withdraw(lpAmount_);

        // Reduce deposit values
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;

        // Return assets
        _repay(ohmReceived);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    function claimRewards() external returns (uint256) {
        _claimRewards();
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view virtual returns (uint256) {}

    function _deposit(uint256 ohmAmount_, uint256 pairAmount_) internal virtual returns (uint256) {}

    function _withdraw(uint256 lpAmount_) internal virtual returns (uint256, uint256) {}

    function _claimRewards() internal returns (uint256) {
        // TODO
    }

    function _borrow(uint256 amount_) internal {
        LENDR.borrow(amount_);
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    // TODO: Need a way to report net minted amount
    function _repay(uint256 amount_) internal {
        MINTR.burnOhm(address(this), amount_);
        LENDR.repay(amount_);
    }
}
