// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "src/interfaces/IERC20.sol";
import "src/interfaces/IStaking.sol";
import "./Ownable.sol";
import "src/types/OlympusAccessControlled.sol";

interface IFaucet is IERC20 {
    function faucetMint(address recipient_) external;
}

/// TODO - get this to be forward compatible if new contracts are deployed
///        i.e. if a new token is added, how can we mint without redeploying a contract
///        Add daily limit to prevent abuse
contract DevFaucet is OlympusAccessControlled {
    /*================== ERRORS ==================*/

    error CanOnlyMintOnceADay();
    error MintTooLarge();

    /*============= STATE VARIABLES =============*/
    IERC20 public DAI;
    IFaucet[] public mintable;

    /// Define current staking contracts
    /// @dev These have to be specifically and separately defined because they do not have
    ///      compatible interfaces
    IStaking public stakingV2;

    /// Define array to push future staking contracts to if they are ever swapped
    /// @dev These have to conform to the current staking interface (or at least the stake function)
    IStaking[] public futureStaking;

    /// Keep track of the last block a user minted at so we can prevent spam
    mapping(address => uint256) public lastMint;

    constructor(
        address dai_,
        address gdaoV2_,
        address stakingV2_,
        address authority_
    ) OlympusAccessControlled(IOlympusAuthority(authority_)) {
        DAI = IERC20(dai_);
        mintable.push(IFaucet(gdaoV2_));
        stakingV2 = IStaking(stakingV2_);
        mintable[1].approve(stakingV2_, type(uint256).max);
    }

    /*================== Modifiers ==================*/

    function _beenADay(uint256 lastMint_, uint256 timestamp_) internal pure returns (bool) {
        return (timestamp_ - lastMint_) > 1 days;
    }

    /*=============== FAUCET FUNCTIONS ===============*/

    function mintDAI() external {
        if (!_beenADay(lastMint[msg.sender], block.timestamp)) revert CanOnlyMintOnceADay();

        lastMint[msg.sender] = block.timestamp;

        DAI.transfer(msg.sender, 100000000000000000000);
    }

    function mintETH(uint256 amount_) external {
        if (!_beenADay(lastMint[msg.sender], block.timestamp)) revert CanOnlyMintOnceADay();
        if (amount_ > 150000000000000000) revert MintTooLarge();

        lastMint[msg.sender] = block.timestamp;

        /// Transfer rather than Send so it reverts if balance too low
        payable(msg.sender).transfer(amount_);
    }

    function mintGDAO(uint256 gdaoIndex_) external {
        if (!_beenADay(lastMint[msg.sender], block.timestamp)) revert CanOnlyMintOnceADay();

        lastMint[msg.sender] = block.timestamp;

        IFaucet gdao = mintable[gdaoIndex_];

        if (gdao.balanceOf(address(this)) < 10000000000) {
            gdao.faucetMint(msg.sender);
        } else {
            gdao.transfer(msg.sender, 10000000000);
        }
    }

    function mintSGDAO(uint256 gdaoIndex_) external {
        if (!_beenADay(lastMint[msg.sender], block.timestamp)) revert CanOnlyMintOnceADay();

        lastMint[msg.sender] = block.timestamp;

        IFaucet gdao = mintable[gdaoIndex_];

        if (gdao.balanceOf(address(this)) < 10000000000) {
            gdao.faucetMint(address(this));
        }

        if (gdaoIndex_ > 1) {
            IStaking currStaking = futureStaking[gdaoIndex_ - 2];
            currStaking.stake(msg.sender, 10000000000, true, true);
        } else if (gdaoIndex_ == 1) {
            stakingV2.stake(msg.sender, 10000000000, true, true);
        } else {
            // stakingV1.stake(10000000000, msg.sender);
            // stakingV1.claim(msg.sender);
        }
    }



    function mintGGDAO() external {
        if (!_beenADay(lastMint[msg.sender], block.timestamp)) revert CanOnlyMintOnceADay();

        lastMint[msg.sender] = block.timestamp;

        if (mintable[1].balanceOf(address(this)) < 10000000000) {
            mintable[1].faucetMint(address(this));
        }

        stakingV2.stake(msg.sender, 10000000000, false, true);
    }

    /*=============== CONFIG FUNCTIONS ===============*/

    function setDAI(address dai_) external onlyGovernor {
        DAI = IERC20(dai_);
    }

    function setGDAO(uint256 gdaoIndex_, address gdao_) external onlyGovernor {
        mintable[gdaoIndex_] = IFaucet(gdao_);
    }

    function addGDAO(address gdao_) external onlyGovernor {
        mintable.push(IFaucet(gdao_));
    }

    function setStakingV2(address stakingV2_) external onlyGovernor {
        stakingV2 = IStaking(stakingV2_);
    }

    function addStaking(address staking_) external onlyGovernor {
        futureStaking.push(IStaking(staking_));
    }

    function approveStaking(address gdao_, address staking_) external onlyGovernor {
        IERC20(gdao_).approve(staking_, type(uint256).max);
    }

    /*=============== RECEIVE FUNCTION ===============*/

    receive() external payable {
        return;
    }
}