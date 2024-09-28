/ SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract AstroPet is ERC721URIStorage, Ownable, VRFConsumerBaseV2, ChainlinkClient {
    uint256 public tokenCounter;
    uint256 public constant MAX_LEVEL = 5;
    uint256 public resourcePrice;

    // VRF Variables
    VRFCoordinatorV2Interface COORDINATOR;
    bytes32 internal keyHash;
    uint64 internal subscriptionId;
    uint16 requestConfirmations = 3;
    uint32 callbackGasLimit = 100000;
    uint32 numWords = 1; // Number of random values

    // Chainlink Oracle Variables
    address public oracle;
    bytes32 public jobId;
    uint256 public oracleFee;

    mapping(uint256 => AstroPetData) public astroPets;
    mapping(uint256 => uint256) public requestIdToTokenId;

    struct AstroPetData {
        string name;
        uint256 level;
        uint256 spaceMissionSuccess;
    }

    event AstroPetMinted(uint256 tokenId, address owner, string name);
    event AstroPetLeveledUp(uint256 tokenId, uint256 newLevel);
    event SpaceMissionCompleted(uint256 tokenId, bool success);
    event SpaceBattle(uint256 winnerTokenId, uint256 loserTokenId);
    event ResourcePriceUpdated(uint256 price);

    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address _oracle,
        bytes32 _jobId,
        uint256 _oracleFee
    )
        ERC721("AstroPet", "ASTRO")
        VRFConsumerBaseV2(_vrfCoordinator)
    {
        tokenCounter = 0;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        oracle = _oracle;
        jobId = _jobId;
        oracleFee = _oracleFee;
        _setPublicChainlinkToken();
    }

    // Function to mint AstroPet NFT
    function mintAstroPet(string memory _name, string memory _tokenURI) public returns (uint256) {
        uint256 newTokenId = tokenCounter;
        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _tokenURI);

        astroPets[newTokenId] = AstroPetData(_name, 1, 0); // Initial level is 1, zero missions completed
        emit AstroPetMinted(newTokenId, msg.sender, _name);
        tokenCounter += 1;
        return newTokenId;
    }

    // Request randomness for space mission
    function sendOnSpaceMission(uint256 _tokenId) public returns (uint256 requestId) {
        require(ownerOf(_tokenId) == msg.sender, "Not your AstroPet!");

        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,          // Subscription ID
            requestConfirmations,     // Minimum confirmations before fulfilling the request
            callbackGasLimit,         // Gas limit for the callback function
            numWords                  // Number of random values requested
        );
        
        requestIdToTokenId[requestId] = _tokenId;
    }

    // Callback function for VRF random number
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 tokenId = requestIdToTokenId[requestId];
        bool missionSuccess = randomWords[0] % 2 == 0; // 50% chance of success

        if (missionSuccess) {
            astroPets[tokenId].spaceMissionSuccess += 1;

            // Level up every 3 successful missions, up to MAX_LEVEL
            if (astroPets[tokenId].spaceMissionSuccess % 3 == 0 && astroPets[tokenId].level < MAX_LEVEL) {
                astroPets[tokenId].level += 1;
                emit AstroPetLeveledUp(tokenId, astroPets[tokenId].level);
            }
        }

        emit SpaceMissionCompleted(tokenId, missionSuccess);
    }

    // Function for player interactions (AstroPet battles)
    function battleAstroPets(uint256 _tokenId1, uint256 _tokenId2) public {
        require(ownerOf(_tokenId1) == msg.sender || ownerOf(_tokenId2) == msg.sender, "Not your AstroPet!");

        AstroPetData storage pet1 = astroPets[_tokenId1];
        AstroPetData storage pet2 = astroPets[_tokenId2];

        // Simple battle logic based on levels and randomness
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 100;
        uint256 pet1Score = pet1.level * 10 + rand;
        uint256 pet2Score = pet2.level * 10 + (100 - rand);

        if (pet1Score > pet2Score) {
            emit SpaceBattle(_tokenId1, _tokenId2); // Pet1 wins
        } else {
            emit SpaceBattle(_tokenId2, _tokenId1); // Pet2 wins
        }
    }

    // Request external data (resource price) from Chainlink oracle
    function requestResourcePrice() public {
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillResourcePrice.selector
        );
        _sendChainlinkRequestTo(oracle, req, oracleFee);
    }

    // Callback for oracle response (update resource price)
    function fulfillResourcePrice(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        resourcePrice = _price;
        emit ResourcePriceUpdated(_price);
    }
} 