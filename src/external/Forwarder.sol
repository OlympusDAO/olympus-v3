// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
 
import {IERC20} from "src/interfaces/IERC20.sol";
import {Ownable} from "src/external/testnet/Ownable.sol";
 
contract Forwarder is Ownable{
 
    address public immutable depositCoin;
    address public immutable saleToken;
    address public immutable multisig;
    uint public cap = 0;
    uint public individualCap = 0;
    // uint public concludedFinalStakingAmount;
    mapping(address => uint) public share;
    // mapping(address => bool) public claimed;
    bool public saleConcluded = false;
    bool public stakingConcluded = false;
    uint public total;
 
    constructor (address _depositCoin, address _saleToken, address _multisig) {
        depositCoin = _depositCoin;
        saleToken = _saleToken;
        multisig = _multisig;
    }
 
    modifier onlySaleNotConcludedAndBothCapsNotReached(uint amount) {
        require(!saleConcluded && total + amount <= cap && share[msg.sender] + amount <= individualCap);
        _;
    }
 
    modifier onlyStakingConcluded {
        require(stakingConcluded);
        _;
    }
 
    modifier onlyStakingNotConcludedAndSaleConcluded {
        require(!stakingConcluded && saleConcluded);
        _;
    }
 
    // modifier onlyNotClaimed {
    //     require(!claimed[msg.sender]);
    //     _;
    // }
 
    function changeCap(uint _cap, uint _individualCap) onlyOwner external {
        cap = _cap;
        individualCap = _individualCap;
    }
 
    function deposit(uint amount) onlySaleNotConcludedAndBothCapsNotReached(amount) external {
        share[msg.sender] = amount;
        total = total + amount;
        IERC20(depositCoin).transferFrom(msg.sender, multisig, amount);
    }
 
    function setSaleConcluded(bool _saleConcluded) external onlyOwner {
        saleConcluded = _saleConcluded;
    }
 
    // function stake(address pool, uint amount, bytes calldata poolInstruction) external onlyStakingNotConcludedAndSaleConcluded onlyOwner {
    //     IERC20(saleToken).approve(pool, amount);
    //     // call pool
    //     pool.call(poolInstruction);
    // }
 
    // function unstake(address pool, bytes calldata poolInstruction) external onlyStakingNotConcludedAndSaleConcluded onlyOwner {
    //     pool.call(poolInstruction);
    // }
 
    // function setStakingConcluded(bool _stakingConcluded) external onlyOwner {
    //     stakingConcluded = _stakingConcluded;
    //     if (stakingConcluded) concludedFinalStakingAmount = IERC20(saleToken).balanceOf(address(this));
    // }
 
    // function withdraw() onlyStakingConcluded onlyNotClaimed external {
    //     claimed[msg.sender] = true;
    //     IERC20(saleToken).transfer(msg.sender, share[msg.sender] / total * concludedFinalStakingAmount);
    // }
 
}