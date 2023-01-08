// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

error Raffle_Not_Enough_EnteranceFee();
error Raffle_Not_Open();
error Raffle_UpKeep_Not_Needed();
error Raffle_TransferFailed();

// Simple Raffle Contract using Chainlink VRF
contract SimpleRaffle is VRFConsumerBaseV2 {
    enum RaffleState {
        Open,
        Calculating
    }

    RaffleState public s_raffleState;
    uint256 public immutable i_entranceFee;
    uint256 public immutable i_interval;
    uint256 public s_lastRaffleTime;
    address payable[] public s_participants;
    VRFCoordinatorV2Interface public immutable i_vrfCoordinatorV2;
    bytes32 public immutable i_gasLane;
    uint64 public immutable i_subscriptionId;
    uint32 public immutable i_callbackGasLimit;
    address public s_recentWinner;

    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;

    event RaffleEntered(address indexed participant);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinatorV2,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinatorV2 = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle_Not_Enough_EnteranceFee();
        }

        if (s_raffleState == RaffleState.Open) {
            revert Raffle_Not_Open();
        }

        s_participants.push(payable(msg.sender));

        emit RaffleEntered(msg.sender);
    }

    function checkUpKeep(
        bytes memory
    ) public view returns (bool upKeepNeeded, bytes memory) {
        bool isOpen = RaffleState.Open == s_raffleState;
        bool timePassed = (block.timestamp - s_lastRaffleTime) > i_interval;
        bool hasBalance = address(this).balance > 0;
        bool hasParticipants = s_participants.length > 0;

        upKeepNeeded = isOpen && timePassed && hasBalance && hasParticipants;

        return (upKeepNeeded, "");
    }

    function performUpKeep(bytes calldata) external {
        (bool upKeepNeeded, ) = checkUpKeep("");

        if (!upKeepNeeded) {
            revert Raffle_UpKeep_Not_Needed();
        }

        s_raffleState = RaffleState.Calculating;

        uint256 requestId = i_vrfCoordinatorV2.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_participants.length;
        address payable winner = s_participants[indexOfWinner];
        s_recentWinner = winner;

        s_participants = new address payable[](0);
        s_raffleState = RaffleState.Open;
        s_lastRaffleTime = block.timestamp;

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
        emit RaffleWinner(winner);
    }
}
