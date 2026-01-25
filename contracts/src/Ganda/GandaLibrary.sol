// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

contract GandaLibrary {
 
    struct Ganda {
        uint256 ganadaId;
        address creator;
        string uri;
        uint64 createdAt;
        bool active;
        uint256 reactionCount;
    }

    struct ReactionUsage {
        uint256 reactionId;
        uint256 count;
    }

    struct GandaReaction {
        address reviewer;
        uint256 reactionId;
        uint256 ganadaId;
        uint256 timestamp;
        string uri;
        ReactionUsage[] reactions;
    }

    struct Designer {
        address wallet;
        address invitedBy;
        bool active;
        uint256 designerId;
        uint256 inviteTimestamp;
        uint256 packCount;
        uint256[] reactionPackIds;
        string uri;
    }

    struct ReactionPack {
        address designer;
        uint256 packId;
        uint256 currentPrice;
        uint256 maxEditions;
        uint256 soldCount;
        uint256 holderReservedSpots;
        bool active;
        string packUri;
        uint256[] reactionIds;
        address[] buyers;
        uint256[] buyerShares;
    }

    struct Reaction {
        uint256 reactionId;
        uint256 packId;
        string reactionUri;
        uint256[] tokenIds;
    }

    struct Purchase {
        address buyer;
        uint256 purchaseId;
        uint256 packId;
        uint256 price;
        uint256 editionNumber;
        uint256 shareWeight;
        uint256 timestamp;
    }
}
