// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

contract MatroidLibrary {
    struct Project {
        bool registered;
        address project;
        string metadata;
        uint64 registeredAt;
        uint256 monaIn;
        uint256 monaOut;
        uint256 monaTxCount;
        uint256 monaUniqueUsers;
        address projectPool;
        address projectNftPool;
        uint16 globalSplitBps;
        uint16 projectErc20SplitBps;
        uint16 projectNftSplitBps;
    }

    struct Proposal {
        uint256 weightFor;
        uint256 voterCount;
        uint256 totalVoteStake;
        uint256 rewardTotal;
        uint256 tallyIndex;
        uint256 tallyWeight;
        uint256 tallyVoterCount;
        uint256 tallyTotalStake;
        uint256 resolveIndex;
        uint256 resolveTotalSlashed;
        uint16 slashBps;
        uint16 tallySlashBps;
        bool blacklist;
        bool tallyBlacklist;
        bool executed;
        bool resolved;
        bool passed;
        bool tallyComplete;
        address[] voters;
    }

    struct EpochData {
        bool finalized;
        uint256 totalScore;
        uint256 activeProjects;
        uint256 budget;
        uint256 finalizedAt;
        uint256 totalUniqueUsers;
    }

    struct VoterChoice {
        uint16 slashBps;
        bool blacklist;
        bool active;
    }

    struct RewardToken {
        bool enabled;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 periodFinish;
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct TokenStats {
        uint256 totalIn;
        uint256 totalOut;
        uint256 txCount;
        uint256 uniqueUsers;
    }

    struct EpochStats {
        uint256 monaUniqueUsers;
        uint256 weightedUniqueUsers;
        uint256 monaRecurringUsers;
        uint256 monaTxCount;
        uint256 monaTotalVolume;
        uint256 monaCappedTxCount;
        uint256 monaCappedVolume;
        uint256 otherUniqueUsers;
        uint256 otherTxCount;
        uint256 otherTokensUsed;
    }
}
