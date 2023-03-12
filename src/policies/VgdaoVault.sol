// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {VOTESv1} from "../modules/VOTES/VOTES.v1.sol";
import "../Kernel.sol";

error VgdaoVault_NotVested();

/// @notice Policy to mint and burn VOTES to arbitrary addresses
contract VgdaoVault is Policy {
    // =========  STATE ========= //

    ERC20 public xGDAO;

    uint256 public constant VESTING_PERIOD = 1 hours;

    VOTESv1 public VOTES;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("VOTES");

        VOTES = VOTESv1(getModuleAddress(dependencies[0]));
        xGDAO = VOTES.xGDAO();
        xGDAO.approve(address(VOTES), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](5);
        permissions[0] = Permissions(toKeycode("VOTES"), VOTES.deposit.selector);
        permissions[1] = Permissions(toKeycode("VOTES"), VOTES.mint.selector);
        permissions[2] = Permissions(toKeycode("VOTES"), VOTES.withdraw.selector);
        permissions[3] = Permissions(toKeycode("VOTES"), VOTES.redeem.selector);
        permissions[4] = Permissions(toKeycode("VOTES"), VOTES.transferFrom.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    modifier onlyVested() {
        if (block.timestamp < VOTES.lastActionTimestamp(msg.sender) + VESTING_PERIOD) {
            revert VgdaoVault_NotVested();
        }
        _;
    }

    function deposit(uint256 assets_) public {
        xGDAO.transferFrom(msg.sender, address(this), assets_);
        VOTES.deposit(assets_, msg.sender);
    }

    function mint(uint256 shares_) public {
        uint256 assets = VOTES.previewMint(shares_);
        xGDAO.transferFrom(msg.sender, address(this), assets);
        VOTES.mint(shares_, msg.sender);
    }

    function withdraw(uint256 assets_) public onlyVested {
        VOTES.withdraw(assets_, msg.sender, msg.sender);
    }

    function redeem(uint256 shares_) public onlyVested {
        VOTES.redeem(shares_, msg.sender, msg.sender);
    }
}
