// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

/// @title 抽奖
/// @author Jerrytq
/// @notice 抽奖
/// @dev Chainlink VRFv2
contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle_NotEnoughEthSent();
    error Raffle_timeNotPassed();
    error Raffle_TransferFailed();
    error Raffle_RaffleNotOpen();

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1; //一个随机数 -> 一个中奖者

    uint256 private immutable i_entranceFee; //报名金额
    uint256 private immutable i_interval; //抽奖持续时间，以秒为单位
    IVRFCoordinatorV2Plus private immutable i_vrfCoordinator; //VRF的地址
    bytes32 private immutable i_gasLane; //gas限制hash
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players; //用户列表
    uint256 private s_lastTimeStamp; //时间戳
    address payable private s_recentWinner; // 中奖者

    RaffleState private s_raffleState; //当前抽奖状态

    event EnteredRaffle(address indexed player);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp; //函数调用时开始计时
        i_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator); //初始化VRF地址
        i_gasLane = gasLane; //初始化GasLane的hash
        i_subscriptionId = subscriptionId; //订阅VRF的ID
        i_callbackGasLimit = callbackGasLimit; //gas限制
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    function pickWinner() public {
        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert Raffle_timeNotPassed();
        }

        //改变状态
        s_raffleState = RaffleState.CALCULATING;

        //获取VRF的随机数
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }

        //重置状态
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN; // 重新开放抽奖
    }

    //getters
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
