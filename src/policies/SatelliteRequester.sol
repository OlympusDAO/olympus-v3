// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStargateRouter {
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        bool _lzFeeInBps,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;
}

contract SatelliteRequester is NonblockingLzApp, Policy, RolesConsumer {
    address[] public tokens;
    mapping(address => uint256) public targetAmounts;
    mapping(address => uint256) public thresholds;
    mapping(address => uint256) public srcPoolIds;
    mapping(address => uint256) public dstPoolIds;
    
    TRSRY public localTreasury;
    address public mainnetTreasury;
    address public stargateRouter;
    uint16 public constant mainnetChainId = 1;

    event RequestSent(address token, uint256 amount);
    event TokenAdded(address token, uint256 targetAmount, uint256 threshold);
    event TargetUpdated(address token, uint256 newTarget);
    event ThresholdUpdated(address token, uint256 newThreshold);
    event ExcessTransferred(address token, uint256 amount);

    constructor(
        address _lzEndpoint,
        Kernel kernel_,
        address _localTreasury,
        address _mainnetTreasury,
        address _stargateRouter
    ) NonblockingLzApp(_lzEndpoint) Policy(kernel_) {
        localTreasury = _localTreasury;
        mainnetTreasury = _mainnetTreasury;
        stargateRouter = _stargateRouter;
    }

    function checkAndRequestTokens() external payable {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 target = targetAmounts[token];
            uint256 threshold = thresholds[token];
            uint256 balance = IERC20(token).balanceOf(localTreasury);
            
            if (balance < target - threshold) {
                // if low balance, request mainnet send inventory
                uint256 requestAmount = target - balance;
                bytes memory payload = abi.encode(i, requestAmount);
                
                _lzSend(
                    mainnetChainId,
                    payload,
                    payable(msg.sender),
                    address(0x0),
                    bytes(""),
                    msg.value
                );
                
                emit RequestSent(token, requestAmount);
            } else if (balance > target + threshold) {
                // if excess balance, send back to mainnet
                uint256 excess = balance - target;

                // pull from local treasury
                localTreasury.increaseWithdrawApproval(address(this), token, amount);
                localTreasury.withdrawReserves(address(this), token, amount);

                // approve to transfer to mainnet treasury
                IERC20(token).approve(stargateRouter, excess);
                bytes memory toAddress = abi.encodePacked(mainnetTreasury);
                
                // transfer token
                IStargateRouter(stargateRouter).swap{value: msg.value}(
                    mainnetChainId,
                    srcPoolIds[token],
                    dstPoolIds[token],
                    payable(msg.sender),
                    excess,
                    excess * 99 / 100, // 1% slippage
                    false,
                    toAddress,
                    bytes("")
                );
                
                emit ExcessTransferred(token, excess);
            }
        }
    }

    /// @notice             add a new token for rebalancing
    /// @dev                only callable by bridge admin
    /// @param token        token being rebalanced
    /// @param targetAmount token balance to target on satellite chain
    /// @param threshold    acceptable deviation from target
    /// @param srcPoolId    stargate pool ID on satellite chain
    /// @param dstPoolId    stargate pool ID on mainnet
    function addValidToken(
        address token, 
        uint256 targetAmount,
        uint256 threshold,
        uint256 srcPoolId,
        uint256 dstPoolId
    ) external hasRole("bridge_admin") {
        if (token == address(0)) revert("Invalid token address");
        if (threshold > targetAmount) revert("Threshold exceeds target");
        
        tokens.push(token);
        targetAmounts[token] = targetAmount;
        thresholds[token] = threshold;
        srcPoolIds[token] = srcPoolId;
        dstPoolIds[token] = dstPoolId;
        emit TokenAdded(token, targetAmount, threshold);
    }

    /// @notice             alter the target and threshold amounts for a token
    /// @dev                only callable by bridge admin
    /// @param token        token being rebalanced
    /// @param newTarget    new token balance to target on satellite chain
    /// @param newThreshold new acceptable deviation from target
    function updateTargetAmount(
        address token, 
        uint256 newTarget,
        uint256 newThreshold
    ) external hasRole("bridge_admin") {
        if (!isValidToken(token)) revert("Token not found");
        if (newThreshold > newTarget) revert("Target below threshold");
        
        targetAmounts[token] = newTarget;
        thresholds[token] = newThreshold;

        emit TargetUpdated(token, newTarget);
        emit ThresholdUpdated(token, newThreshold);
    }

    function isValidToken(address token) public view returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) return true;
        }
        return false;
    }
}