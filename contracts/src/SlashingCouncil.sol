// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MatroidRegistry} from "./MatroidRegistry.sol";
import {Treasury} from "./Treasury.sol";
import "./MatroidErrors.sol";
import "./MatroidLibrary.sol";

contract SlashingCouncil is ReentrancyGuard {
    using SafeERC20 for IERC20;

   
    IERC20 public immutable mona;
    MatroidRegistry public immutable registry;
    Treasury public immutable treasury;

    uint256 public constant MIN_STAKE = 1 ether;
    uint256 public votingWindow;
    uint256 public minVoterDivisor;
    uint16 public maxSlashBps;
    uint16 public thresholdBps;

    mapping(uint256 => uint256) public epochTotalWeight;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public lockedStake;
    uint256 public nextEpochToFinalize;
    mapping(uint256 => bool) public votingEpochFinalized;
    mapping(uint256 => uint256) public finalizedCount;
    mapping(uint256 => mapping(address => MatroidLibrary.Proposal)) public proposals;
    mapping(uint256 => mapping(address => mapping(address => bool))) public voted;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public voteStake;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public rewardClaimed;
    mapping(uint256 => mapping(address => mapping(address => MatroidLibrary.VoterChoice))) public voterChoices;

    event Voted(uint256 indexed epoch, address indexed project, address indexed voter, uint256 weight);
    event ProposalExecuted(uint256 indexed epoch, address indexed project, uint16 slashBps, bool blacklist);
    event ProposalResolved(uint256 indexed epoch, address indexed project, bool passed);
    event VoterRewardNotified(uint256 indexed epoch, address indexed project, uint256 amount);
    event VoterRewarded(uint256 indexed epoch, address indexed project, address indexed voter, uint256 amount);

    constructor(
        address monaToken,
        address registryAddress,
        address treasuryAddress,
        uint256 votingWindowSeconds,
        uint256 minVoterDivisorValue,
        uint16 maxSlashBpsValue,
        uint16 thresholdBpsValue
    ) {
        if (monaToken == address(0) || registryAddress == address(0) || treasuryAddress == address(0)) {
            revert MatroidErrors.ZeroAddress();
        }
        if (votingWindowSeconds == 0 || minVoterDivisorValue == 0) {
            revert MatroidErrors.ZeroAmount();
        }
        if (maxSlashBpsValue == 0 || maxSlashBpsValue > 10_000) {
            revert MatroidErrors.InvalidSlash();
        }
        if (thresholdBpsValue == 0 || thresholdBpsValue > 10_000) {
            revert MatroidErrors.InvalidSlash();
        }
        mona = IERC20(monaToken);
        registry = MatroidRegistry(registryAddress);
        treasury = Treasury(treasuryAddress);
        votingWindow = votingWindowSeconds;
        minVoterDivisor = minVoterDivisorValue;
        maxSlashBps = maxSlashBpsValue;
        thresholdBps = thresholdBpsValue;
    }

    function vote(
        uint256 epoch,
        address project,
        uint256 amount,
        uint16 slashBps,
        bool blacklist
    ) external nonReentrant {
        if (amount < MIN_STAKE) revert MatroidErrors.MinStakeNotMet();
        if (slashBps > maxSlashBps) revert MatroidErrors.InvalidSlash();
        if (blacklist) {
            slashBps = 10_000;
        }
        _requireActiveProject(project);

        _ensureVotingOpen(epoch);

        uint256 weight = _recordVote(epoch, project, amount, slashBps, blacklist);
        emit Voted(epoch, project, msg.sender, weight);
    }

    function unvote(uint256 epoch, address project) external nonReentrant {
        if (!voted[epoch][project][msg.sender]) return;
        MatroidLibrary.EpochData memory data = treasury.getEpochData(epoch);
        if (!data.finalized) revert MatroidErrors.EpochNotFinalized();
        if (block.timestamp <= data.finalizedAt || block.timestamp > data.finalizedAt + votingWindow) {
            revert MatroidErrors.VoteWindowClosed();
        }
        MatroidLibrary.VoterChoice storage choice = voterChoices[epoch][project][msg.sender];
        if (!choice.active) return;
        choice.active = false;

        uint256 stakeAmount = lockedStake[epoch][project][msg.sender];
        if (stakeAmount > 0) {
            epochTotalWeight[epoch] -= _sqrt(stakeAmount);
            lockedStake[epoch][project][msg.sender] = 0;
            voteStake[epoch][project][msg.sender] = 0;
            mona.safeTransfer(msg.sender, stakeAmount);
        }
    }

    function finalizeProposal(uint256 epoch, address project) external {
        _finalizeProposalBatch(epoch, project, 0);
    }

    function finalizeProposalBatch(uint256 epoch, address project, uint256 maxVoters) external {
        _finalizeProposalBatch(epoch, project, maxVoters);
    }

    function _finalizeProposalBatch(uint256 epoch, address project, uint256 maxVoters) internal {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        if (proposal.executed) return;

        if (!_ensureFinalizeOpen(epoch, project)) {
            proposal.executed = true;
            _markProposalFinalized(epoch);
            return;
        }
        uint256 minVoters = _minVoters(epoch, project);

        if (!proposal.tallyComplete) {
            bool done = _tallyProposal(epoch, project, maxVoters);
            if (!done) return;
        }

        if (proposal.voterCount < minVoters) {
            proposal.executed = true;
            _markProposalFinalized(epoch);
            return;
        }

        uint256 requiredWeight = (epochTotalWeight[epoch] * thresholdBps) / 10_000;
        if (proposal.weightFor < requiredWeight) {
            proposal.executed = true;
            _markProposalFinalized(epoch);
            return;
        }

        proposal.executed = true;
        proposal.passed = true;
        treasury.applySlash(epoch, project, proposal.slashBps, proposal.blacklist);
        emit ProposalExecuted(epoch, project, proposal.slashBps, proposal.blacklist);

        _markProposalFinalized(epoch);
    }

    function resolveFailure(uint256 epoch, address project) external nonReentrant {
        _resolveFailureBatch(epoch, project, 0);
    }

    function resolveFailureBatch(uint256 epoch, address project, uint256 maxVoters) external nonReentrant {
        _resolveFailureBatch(epoch, project, maxVoters);
    }

    function _resolveFailureBatch(uint256 epoch, address project, uint256 maxVoters) internal {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        if (proposal.resolved || proposal.passed) return;

        _ensureResolveOpen(epoch);

        _finalizeProposalBatch(epoch, project, maxVoters);
        if (proposal.passed) return;

        if (!proposal.tallyComplete) return;

        if (!_resolveFailureChunk(epoch, project, maxVoters)) return;

        proposal.resolved = true;
        _finalizeFailurePayout(epoch, project, proposal.resolveTotalSlashed);

        emit ProposalResolved(epoch, project, false);
    }

    function _markProposalFinalized(uint256 epoch) internal {
        if (votingEpochFinalized[epoch]) return;
        uint256 count = finalizedCount[epoch] + 1;
        finalizedCount[epoch] = count;
        uint256 projectCount = registry.projectCount();
        if (count < projectCount) return;
        votingEpochFinalized[epoch] = true;
        while (votingEpochFinalized[nextEpochToFinalize]) {
            nextEpochToFinalize += 1;
        }
    }
    function notifyVoterReward(uint256 epoch, address project, uint256 amount) external {
        if (msg.sender != address(treasury)) revert MatroidErrors.NotTreasury();
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        if (!proposal.passed || proposal.resolved) return;
        if (amount == 0 || proposal.totalVoteStake == 0) return;
        proposal.rewardTotal += amount;
        emit VoterRewardNotified(epoch, project, amount);
    }

    function claimVoterReward(uint256 epoch, address project) external nonReentrant {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        if (!proposal.passed) revert MatroidErrors.ClaimNotAvailable();
        uint256 stakeAmount = voteStake[epoch][project][msg.sender];
        if (stakeAmount == 0 || proposal.totalVoteStake == 0) revert MatroidErrors.ZeroAmount();
        uint256 totalReward = proposal.rewardTotal;
        uint256 entitled = (totalReward * stakeAmount) / proposal.totalVoteStake;
        uint256 claimed = rewardClaimed[epoch][project][msg.sender];
        if (entitled <= claimed) revert MatroidErrors.ZeroAmount();
        uint256 payout = entitled - claimed;
        rewardClaimed[epoch][project][msg.sender] = entitled;
        mona.safeTransfer(msg.sender, payout);
        emit VoterRewarded(epoch, project, msg.sender, payout);
    }

    function withdrawStake(uint256 epoch, address project) external nonReentrant {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        if (!proposal.passed && !proposal.resolved) revert MatroidErrors.ClaimNotAvailable();
        uint256 stakeAmount = lockedStake[epoch][project][msg.sender];
        if (stakeAmount == 0) revert MatroidErrors.ZeroAmount();
        lockedStake[epoch][project][msg.sender] = 0;
        mona.safeTransfer(msg.sender, stakeAmount);
    }

    function _requireRegisteredProject(address project) internal view {
        MatroidLibrary.Project memory _project = registry.getProject(project);
        if (!_project.registered) revert MatroidErrors.NotProject();
    }

    function _requireActiveProject(address project) internal view {
        _requireRegisteredProject(project);
        if (treasury.blacklisted(project)) revert MatroidErrors.ProjectBlacklisted();
    }

    function _ensureVotingOpen(uint256 epoch) internal view {
        MatroidLibrary.EpochData memory data = treasury.getEpochData(epoch);
        if (!data.finalized) {
            revert MatroidErrors.EpochNotFinalized();
        }
        if (block.timestamp <= data.finalizedAt || block.timestamp > data.finalizedAt + votingWindow) {
            revert MatroidErrors.VoteWindowClosed();
        }
    }

    function _recordVote(
        uint256 epoch,
        address project,
        uint256 amount,
        uint16 slashBps,
        bool blacklist
    ) internal returns (uint256 weight) {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        MatroidLibrary.VoterChoice storage choice = voterChoices[epoch][project][msg.sender];
        uint256 priorStake = lockedStake[epoch][project][msg.sender];

        if (!voted[epoch][project][msg.sender]) {
            voted[epoch][project][msg.sender] = true;
            proposal.voters.push(msg.sender);
        }

        _adjustEpochWeight(epoch, choice.active, priorStake, amount);
        _transferStakeDelta(priorStake, amount);

        lockedStake[epoch][project][msg.sender] = amount;
        choice.slashBps = slashBps;
        choice.blacklist = blacklist;
        choice.active = true;

        weight = _sqrt(amount);
    }

    function _ensureResolveOpen(uint256 epoch) internal view {
        MatroidLibrary.EpochData memory data = treasury.getEpochData(epoch);
        if (!data.finalized) revert MatroidErrors.EpochNotFinalized();
        if (block.timestamp <= data.finalizedAt + votingWindow) revert MatroidErrors.VoteWindowClosed();
    }

    function _ensureFinalizeOpen(uint256 epoch, address project) internal view returns (bool active) {
        _ensureResolveOpen(epoch);
        if (!treasury.getEpochData(epoch).finalized) revert MatroidErrors.EpochNotFinalized();
        _requireRegisteredProject(project);
        return !treasury.blacklisted(project);
    }

    function _minVoters(
        uint256 epoch,
        address project
    ) internal view returns (uint256 minVoters) {
        minVoters = registry.getEpochStats(project, epoch).monaUniqueUsers / minVoterDivisor;
        if (minVoters < 3) minVoters = 3;
    }

    function _resolveFailureChunk(
        uint256 epoch,
        address project,
        uint256 maxVoters
    ) internal returns (bool done) {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        uint256 remaining = maxVoters == 0 ? type(uint256).max : maxVoters;
        uint256 len = proposal.voters.length;
        uint256 processed;

        while (proposal.resolveIndex < len && processed < remaining) {
            address voter = proposal.voters[proposal.resolveIndex];
            proposal.resolveIndex += 1;
            processed += 1;

            uint256 baseStake = lockedStake[epoch][project][voter];
            if (baseStake == 0) continue;
            uint256 slashAmount = (baseStake * 10_000) / 100_000; // 10%
            if (slashAmount == 0) continue;
            lockedStake[epoch][project][voter] = baseStake - slashAmount;
            proposal.resolveTotalSlashed += slashAmount;
        }

        if (proposal.resolveIndex < len) return false;
        return true;
    }

    function _finalizeFailurePayout(
        uint256 epoch,
        address project,
        uint256 totalSlashed
    ) internal {
        if (totalSlashed == 0) return;
        uint256 treasuryShare = totalSlashed / 2;
        uint256 projectShare = totalSlashed - treasuryShare;
        mona.safeTransfer(address(treasury), totalSlashed);
        treasury.notifySlashReward(epoch, project, projectShare);
    }

    function _adjustEpochWeight(
        uint256 epoch,
        bool wasActive,
        uint256 priorStake,
        uint256 amount
    ) internal {
        uint256 newWeight = _sqrt(amount);
        if (!wasActive) {
            epochTotalWeight[epoch] += newWeight;
            return;
        }
        uint256 oldWeight = priorStake == 0 ? 0 : _sqrt(priorStake);
        if (newWeight > oldWeight) {
            epochTotalWeight[epoch] += (newWeight - oldWeight);
        } else if (oldWeight > newWeight) {
            epochTotalWeight[epoch] -= (oldWeight - newWeight);
        }
    }

    function _transferStakeDelta(uint256 priorStake, uint256 amount) internal {
        if (amount > priorStake) {
            mona.safeTransferFrom(msg.sender, address(this), amount - priorStake);
        } else if (priorStake > amount) {
            mona.safeTransfer(msg.sender, priorStake - amount);
        }
    }

    function _tallyProposal(
        uint256 epoch,
        address project,
        uint256 maxVoters
    ) internal returns (bool done) {
        if (!_tallyChunk(epoch, project, maxVoters)) return false;
        _finalizeTally(epoch, project);
        return true;
    }

    function _tallyChunk(
        uint256 epoch,
        address project,
        uint256 maxVoters
    ) internal returns (bool done) {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        uint256 remaining = maxVoters == 0 ? type(uint256).max : maxVoters;
        uint256 len = proposal.voters.length;
        uint256 processed;

        while (proposal.tallyIndex < len && processed < remaining) {
            address voter = proposal.voters[proposal.tallyIndex];
            proposal.tallyIndex += 1;
            processed += 1;
            _tallyVoter(epoch, project, voter);
        }

        if (proposal.tallyIndex < len) return false;
        return true;
    }

    function _tallyVoter(uint256 epoch, address project, address voter) internal {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        MatroidLibrary.VoterChoice memory choice = voterChoices[epoch][project][voter];
        uint256 currentStake = lockedStake[epoch][project][voter];
        if (!choice.active || currentStake < MIN_STAKE) {
            voteStake[epoch][project][voter] = 0;
            return;
        }
        proposal.tallyVoterCount += 1;
        proposal.tallyTotalStake += currentStake;
        proposal.tallyWeight += _sqrt(currentStake);
        voteStake[epoch][project][voter] = currentStake;
        if (choice.slashBps > proposal.tallySlashBps) {
            proposal.tallySlashBps = choice.slashBps;
        }
        if (choice.blacklist) {
            proposal.tallyBlacklist = true;
        }
    }

    function _finalizeTally(uint256 epoch, address project) internal {
        MatroidLibrary.Proposal storage proposal = proposals[epoch][project];
        proposal.voterCount = proposal.tallyVoterCount;
        proposal.totalVoteStake = proposal.tallyTotalStake;
        proposal.weightFor = proposal.tallyWeight;
        proposal.slashBps = proposal.tallySlashBps;
        proposal.blacklist = proposal.tallyBlacklist;
        proposal.tallyComplete = true;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return 0;
        z = y;
        uint256 x = (y / 2) + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}
