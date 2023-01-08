// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NFTRaffle is VRFConsumerBaseV2, IERC721Receiver {
    enum RaffleState {
        Open,
        Calculating,
        Closed
    }

    struct RaffleInfo {
        uint256 startTime;
        uint256 endTime;
        RaffleState state;
        address[] participants;
        address winner;
        address payable feeReceiver;
        uint256 entranceFee;
        address refunder;
    }

    struct NFTInfo {
        address nft;
        uint256 id;
    }

    // nft address, id, state, start time, end time

    mapping(address => mapping(uint256 => RaffleInfo)) public s_raffleInfos;

    mapping(uint256 => NFTInfo) public s_nftInfoByRequestId;

    VRFCoordinatorV2Interface public immutable i_vrfCoordinatorV2;
    bytes32 public immutable i_gasLane;
    uint64 public immutable i_subscriptionId;
    uint32 public immutable i_callbackGasLimit;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;

    event RaffleRegistered(
        address indexed nft,
        uint256 indexed id,
        uint256 startTime,
        uint256 endTime
    );
    event RaffleEntered(address participant, address nft, uint256 id);
    event RaffleWinner(address winner, address nft, uint256 id);

    constructor(
        address _vrfCoordinatorV2,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinatorV2) {
        i_vrfCoordinatorV2 = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
    }

    function registerRaffleNFT(
        IERC721 _nft,
        uint256 _id,
        uint256 startTime,
        uint256 endTimes,
        address payable feeReceiver,
        uint256 entranceFee
    ) external {
        require(
            startTime > block.timestamp,
            "Raffle: start time must be in the future"
        );
        require(
            endTimes > startTime,
            "Raffle: end time must be after start time"
        );

        _nft.safeTransferFrom(msg.sender, address(this), _id);

        s_raffleInfos[address(_nft)][_id] = RaffleInfo({
            startTime: startTime,
            endTime: endTimes,
            state: RaffleState.Open,
            participants: new address[](0),
            winner: address(0),
            feeReceiver: feeReceiver,
            entranceFee: entranceFee,
            refunder: msg.sender
        });

        emit RaffleRegistered(address(_nft), _id, startTime, endTimes);
    }

    function enterRaffle(address _nft, uint256 _id) external payable {
        RaffleInfo storage raffleInfo = s_raffleInfos[_nft][_id];

        require(
            raffleInfo.state == RaffleState.Open,
            "Raffle: raffle is not open"
        );
        require(
            raffleInfo.startTime < block.timestamp,
            "Raffle: raffle has not started"
        );
        require(
            raffleInfo.endTime > block.timestamp,
            "Raffle: raffle has ended"
        );
        require(
            msg.value == raffleInfo.entranceFee,
            "Raffle: incorrect entrance fee"
        );

        raffleInfo.participants.push(msg.sender);

        (bool suc, ) = raffleInfo.feeReceiver.call{value: msg.value}("");
        require(suc, "Raffle: fee transfer failed");

        emit RaffleEntered(msg.sender, _nft, _id);
    }

    function checkUpKeep(address _nft, uint256 _id) public view returns (bool) {
        RaffleInfo memory raffleInfo = s_raffleInfos[_nft][_id];

        bool isRaffleOpen = raffleInfo.state == RaffleState.Open;
        bool timePassed = raffleInfo.endTime < block.timestamp;

        return isRaffleOpen && timePassed;
    }

    function performUpKeep(address _nft, uint256 _id) external {
        bool upKeepNeeded = checkUpKeep(_nft, _id);
        require(upKeepNeeded, "Raffle: upkeep not needed");

        RaffleInfo storage raffleInfo = s_raffleInfos[_nft][_id];

        raffleInfo.state = RaffleState.Calculating;

        if (raffleInfo.participants.length == 0) {
            raffleInfo.state = RaffleState.Closed;
            // refund
            IERC721(_nft).safeTransferFrom(
                address(this),
                raffleInfo.refunder,
                _id
            );
            emit RaffleWinner(address(0), _nft, _id);
            return;
        }

        uint256 requestId = i_vrfCoordinatorV2.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        s_nftInfoByRequestId[requestId] = NFTInfo({nft: _nft, id: _id});
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        NFTInfo memory nftInfo = s_nftInfoByRequestId[requestId];
        RaffleInfo storage raffleInfo = s_raffleInfos[nftInfo.nft][nftInfo.id];

        uint256 indexOfWinner = randomWords[0] % raffleInfo.participants.length;
        address winner = raffleInfo.participants[indexOfWinner];
        raffleInfo.winner = winner;

        raffleInfo.state = RaffleState.Closed;

        // or user can claim the NFT?
        IERC721(nftInfo.nft).safeTransferFrom(
            address(this),
            winner,
            nftInfo.id
        );

        emit RaffleWinner(winner, nftInfo.nft, nftInfo.id);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
