// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// DEPS

import "solmate/auth/Auth.sol";
import "test-utils/convert.sol";

/// LOCAL

import "src/Kernel.sol";

import "modules/VOPOM.sol";

import "./types/VotingPowerToken/ERC20.sol";

error VotingPowerToken_AmountNotAllowed(
    address account_,
    uint256 allowedAmount_,
    uint256 attemptedAmount_
);

contract VotingPowerToken is ERC20, Auth, Policy {
    using convert for *;

    VotingPowerModule public vopom;

    uint64[] public openPoolIds;

    mapping(address => uint256) public allowedUserAmounts;

    constructor(address kernel_)
        ERC20("OlympusVotingPowerToken", "OVPT", 18)
        Auth(kernel_, Authority(address(0)))
        Policy(Kernel(kernel_))
    {}

    // ######################## ~ DEFAULT ~ ########################

    function configureReads() external override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Role[] memory roles)
    {
        roles = new Role[](0);
    }

    // ######################## ~  MODIFIER ~ ########################

    modifier mustBeAllowedFor(address account, uint256 amount) {
        _mustBeAllowedFor(account, amount);
        _;
    }

    // ######################## ~ SETTERS ~ ########################

    function setOpenPoolIds(uint64[] calldata openPoolIds_)
        external
        requiresAuth
    {
        openPoolIds = openPoolIds_;
    }

    function allowAmountFor(address account, uint256 amount)
        external
        requiresAuth
    {
        allowedUserAmounts[account] = amount;
    }

    // ######################## ~ ERC20 ~ ########################

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        mustBeAllowedFor(msg.sender, amount)
        returns (bool)
    {
        // amount is multiplied by 1e18 already due to decimals...
        int256 totalVotingPower = vopom.getVotingPower(
            msg.sender,
            vopom.getUserOpenPoolPointIds(msg.sender)
        );

        vopom.noteVotingPowerDelegation(
            msg.sender,
            to,
            (amount.cui() / totalVotingPower).ci128i()
        );

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        int256 totalVotingPower = vopom.getVotingPower(
            from,
            vopom.getUserOpenPoolPointIds(from)
        );

        vopom.noteVotingPowerDelegation(
            from,
            to,
            (amount.cui() / totalVotingPower).ci128i()
        );

        emit Transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        mustBeAllowedFor(msg.sender, amount)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override mustBeAllowedFor(owner, value) {
        return super.permit(owner, spender, value, deadline, v, r, s);
    }

    function balanceOf(address account) public view returns (uint256) {
        return
            (vopom.getOpenVotingPower(account) +
                vopom.getDelegatedVotingPower(account)).ciu() * (10**decimals);
    }

    function totalSupply() public view returns (uint256) {
        return vopom.getGlobalVotingPower(openPoolIds).ciu() * (10**decimals);
    }

    // ######################## ~ REST ~ ########################

    /// @dev killed
    function setOwner(address) public override {}

    function _mustBeAllowedFor(address account, uint256 amount) internal {
        uint256 allowedAmount = allowedUserAmounts[account];

        if (allowedAmount < amount)
            revert VotingPowerToken_AmountNotAllowed(
                account,
                allowedAmount,
                amount
            );

        allowedUserAmounts[account] = allowedAmount - amount;
    }
}
