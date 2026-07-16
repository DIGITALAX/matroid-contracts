// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

library GandaLibrary {
    struct Game {
        bytes32 ownerTag;
        address scorer;
        string uri;
        uint64 version;
        uint64 publishedAt;
        bool exists;
        bool removed;
    }

    struct EpochGameTotals {
        uint256 totalPoints;
        uint256 playerCount;
    }

    struct Proposal {
        uint8 kind;
        uint256 target;
        bytes32 tagTarget;
        uint256 value;
        uint256 yes;
        uint256 no;
        uint64 start;
        uint64 end;
        bool executed;
        string uri;
    }
}
