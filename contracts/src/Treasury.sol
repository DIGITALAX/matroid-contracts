
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MatroidRegistry} from "./MatroidRegistry.sol";
import {MatroidScorer} from "./MatroidScorer.sol";
import {GlobalStakingPool} from "./GlobalStakingPool.sol";
import {ProjectStakingPool} from "./ProjectStakingPool.sol";
import {ProjectNFTStakingPool} from "./ProjectNFTStakingPool.sol";
import {MatroidLibrary} from "./MatroidLibrary.sol";
import "./MatroidErrors.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ISlashingCouncil {
    function votingWindow() external view returns (uint256);
    function finalizeProposal(uint256 epoch, address project) external;
    function resolveFailure(uint256 epoch, address project) external;
    function notifyVoterReward(uint256 epoch, address project, uint256 amount) external;
}

contract Treasury is ReentrancyGuard {
    using SafeERC20 for IERC20;
 

    IERC20 public immutable mona;
    MatroidRegistry public immutable registry;
    MatroidScorer public immutable scorer;
    address public owner;
    GlobalStakingPool public globalPool;
    address public slashingContract;
    uint256 public immutable claimWindow;
    uint256 public targetTotal;
    uint256 public targetDuration;
    uint256 public distributionStart;
    uint256 public totalDistributed;
    uint256 public baseBudget;
    uint256 public perProjectBudget;

    mapping(uint256 => mapping(address => uint256)) private _claimable;
    mapping(uint256 => mapping(address => bool)) private _claimableSet;
    mapping(uint256 =>MatroidLibrary.EpochData) private _epochData;
    mapping(uint256 => mapping(address => bool)) private _epochSlashed;
    mapping(uint256 => mapping(address => uint16)) private _epochSlashBps;
    mapping(uint256 => mapping(address => uint256)) private _slashRewards;
    mapping(uint256 => mapping(address => bool)) private _slashResolved;
    mapping(address => bool) private _blacklisted;

    event FundsDeposited(address indexed from, uint256 amount);
    event TargetUpdated(uint256 oldTarget, uint256 newTarget);
    event TargetReconciled(uint256 oldTarget, uint256 newTarget);
    event DistributionStarted(uint256 timestamp);
    event TargetDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event EpochFinalized(uint256 indexed epoch, uint256 totalScore, uint256 activeProjects, uint256 budget);
    event ClaimableSet(uint256 indexed epoch, address indexed project, uint256 amount);
    event ClaimableCleared(uint256 indexed epoch, address indexed project);
    event Claimed(uint256 indexed epoch, address indexed project, address indexed claimer, uint256 amount);
    event SlashingContractUpdated(address indexed oldContract, address indexed newContract);
    event ProjectSlashed(uint256 indexed epoch, address indexed project, uint16 slashBps, bool blacklisted);
    event SlashRewardNotified(uint256 indexed epoch, address indexed project, uint256 amount);
    event SlashResolved(uint256 indexed epoch, address indexed project, uint256 voterReward);

    constructor(
        address monaToken,
        address registryAddress,
        address scorerAddress,
        address globalPoolAddress,
        uint256 claimWindowSeconds,
        uint256 targetTotalAmount,
        uint256 targetDurationSeconds,
        uint256 baseBudgetAmount,
        uint256 perProjectBudgetAmount
    ) {
        if (
            monaToken == address(0)
            || registryAddress == address(0)
            || scorerAddress == address(0)
            || globalPoolAddress == address(0)
        ) {
            revert MatroidErrors.ZeroAddress();
        }
        if (claimWindowSeconds == 0) {
            revert MatroidErrors.ZeroAmount();
        }
        if (targetDurationSeconds == 0) revert MatroidErrors.InvalidDuration();
        if (baseBudgetAmount == 0 || perProjectBudgetAmount == 0) {
            revert MatroidErrors.ZeroAmount();
        }
        owner = msg.sender;
        mona = IERC20(monaToken);
        registry = MatroidRegistry(registryAddress);
        scorer = MatroidScorer(scorerAddress);
        globalPool = GlobalStakingPool(globalPoolAddress);
        claimWindow = claimWindowSeconds;
        targetTotal = targetTotalAmount;
        targetDuration = targetDurationSeconds;
        baseBudget = baseBudgetAmount;
        perProjectBudget = perProjectBudgetAmount;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert MatroidErrors.NotOwner();
        _;
    }

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        mona.safeTransferFrom(msg.sender, address(this), amount);
        if (amount > 0) {
            uint256 oldTarget = targetTotal;
            targetTotal = oldTarget + amount;
            emit TargetUpdated(oldTarget, targetTotal);
        }
        emit FundsDeposited(msg.sender, amount);
    }

    function setTargetTotal(uint256 newTarget) external onlyOwner {
        if (newTarget < targetTotal) revert MatroidErrors.ZeroAmount();
        uint256 oldTarget = targetTotal;
        targetTotal = newTarget;
        emit TargetUpdated(oldTarget, newTarget);
    }

    function reconcileTarget() external {
        uint256 available = mona.balanceOf(address(this)) + totalDistributed;
        if (available <= targetTotal) return;
        uint256 oldTarget = targetTotal;
        targetTotal = available;
        emit TargetReconciled(oldTarget, available);
    }

    function setTargetDuration(uint256 newDuration) external onlyOwner {
        if (newDuration < targetDuration) revert MatroidErrors.InvalidDuration();
        uint256 oldDuration = targetDuration;
        targetDuration = newDuration;
        emit TargetDurationUpdated(oldDuration, newDuration);
    }

    function setBudgets(uint256 newBaseBudget, uint256 newPerProjectBudget) external onlyOwner {
        if (newBaseBudget == 0 || newPerProjectBudget == 0) revert MatroidErrors.ZeroAmount();
        baseBudget = newBaseBudget;
        perProjectBudget = newPerProjectBudget;
    }

    function setSlashingContract(address slashing) external onlyOwner {
        if (slashing == address(0)) revert MatroidErrors.ZeroAddress();
        address old = slashingContract;
        slashingContract = slashing;
        emit SlashingContractUpdated(old, slashing);
    }

    function getEpochData(uint256 epoch) external view returns (MatroidLibrary.EpochData memory) {
        return _epochData[epoch];
    }

    function claimable(uint256 epoch, address project) external view returns (uint256) {
        return _claimable[epoch][project];
    }

    function claimableSet(uint256 epoch, address project) external view returns (bool) {
        return _claimableSet[epoch][project];
    }

    function epochData(uint256 epoch) external view returns (MatroidLibrary.EpochData memory) {
        return _epochData[epoch];
    }

    function epochSlashed(uint256 epoch, address project) external view returns (bool) {
        return _epochSlashed[epoch][project];
    }

    function epochSlashBps(uint256 epoch, address project) external view returns (uint16) {
        return _epochSlashBps[epoch][project];
    }

    function slashRewards(uint256 epoch, address project) external view returns (uint256) {
        return _slashRewards[epoch][project];
    }

    function slashResolved(uint256 epoch, address project) external view returns (bool) {
        return _slashResolved[epoch][project];
    }

    function blacklisted(address project) external view returns (bool) {
        return _blacklisted[project];
    }

    function remainingEpochs() public view returns (uint256) {
        if (distributionStart == 0) return 0;
        uint256 endTime = distributionStart + targetDuration;
        if (block.timestamp >= endTime) return 0;
        uint256 epochDuration = registry.epochDuration();
        return (endTime - block.timestamp + epochDuration - 1) / epochDuration;
    }

    function effectiveRemainingEpochs() public view returns (uint256) {
        uint256 remaining = remainingEpochs();
        if (remaining == 0 && mona.balanceOf(address(this)) > 0) {
            return 1;
        }
        return remaining;
    }

    function epochBudget(uint256 totalScore, uint256 activeProjects) public view returns (uint256) {
        if (totalScore == 0 || activeProjects == 0) return 0;
        uint256 dynamicBudget = baseBudget + (perProjectBudget * activeProjects);
        uint256 remaining = effectiveRemainingEpochs();
        if (remaining == 0) return 0;
        uint256 remainingTarget = 0;
        if (targetTotal > totalDistributed) {
            remainingTarget = targetTotal - totalDistributed;
        }
        uint256 scheduleBudget = remainingTarget / remaining;
        if (scheduleBudget == 0) return 0;
        uint256 budget = dynamicBudget < scheduleBudget ? dynamicBudget : scheduleBudget;
        uint256 available = mona.balanceOf(address(this));
        if (budget > available) return available;
        return budget;
    }

    function finalizeEpoch(uint256 epoch) external {
        MatroidLibrary.EpochData storage data = _epochData[epoch];
        if (data.finalized) return;

        (, uint256 end) = epochBounds(epoch);
        if (block.timestamp <= end) revert MatroidErrors.ClaimNotAvailable();

        uint256 projectCount = registry.projectCount();
        uint256 totalScore;
        uint256 activeProjects;
        uint256 totalUniqueUsers;

        for (uint256 i = 0; i < projectCount; i++) {
            address project = registry.projectAt(i);
            uint256 scoreValue = scorer.score(project, epoch);
            if (scoreValue > 0) {
                totalScore += scoreValue;
                activeProjects += 1;
            }
            MatroidLibrary.EpochStats memory stats = registry.getEpochStats(project, epoch);
            totalUniqueUsers += stats.monaUniqueUsers;
        }

        uint256 budget = epochBudget(totalScore, activeProjects);
        data.finalized = true;
        data.totalScore = totalScore;
        data.activeProjects = activeProjects;
        data.budget = budget;
        data.finalizedAt = block.timestamp;
        data.totalUniqueUsers = totalUniqueUsers;
        emit EpochFinalized(epoch, totalScore, activeProjects, budget);
    }

    function applySlash(uint256 epoch, address project, uint16 slashBps, bool blacklist) external {
        if (msg.sender != slashingContract) revert MatroidErrors.NotSlashing();
        if (slashBps > 10_000) revert MatroidErrors.InvalidSlash();
        if (blacklist) {
            _blacklisted[project] = true;
            slashBps = 10_000;
        }
        if (slashBps > 0) {
            _epochSlashed[epoch][project] = true;
        }
        _epochSlashBps[epoch][project] = slashBps;
        emit ProjectSlashed(epoch, project, slashBps, blacklist);
    }

    function computeClaimable(uint256 epoch, address project) public {
        MatroidLibrary.EpochData storage data = _epochData[epoch];
        if (!data.finalized) revert MatroidErrors.ClaimNotAvailable();
        if (_claimableSet[epoch][project]) return;

        uint256 scoreValue = scorer.score(project, epoch);
        uint256 amount = 0;
        if (data.totalScore > 0 && scoreValue > 0 && data.budget > 0) {
            amount = (data.budget * scoreValue) / data.totalScore;
        }
        _claimable[epoch][project] = amount;
        _claimableSet[epoch][project] = true;
        emit ClaimableSet(epoch, project, amount);
    }

    function sweepExpired(uint256 epoch, address project) external {
        (, uint256 end) = epochBounds(epoch);
        if (block.timestamp <= end + claimWindow) revert MatroidErrors.ClaimNotAvailable();
        if (!_claimableSet[epoch][project]) return;
        if (_claimable[epoch][project] == 0) return;
        _claimable[epoch][project] = 0;
        emit ClaimableCleared(epoch, project);
    }

    function currentEpoch() public view returns (uint256) {
        return registry.currentEpoch();
    }

    function epochBounds(uint256 epoch) public view returns (uint256 start, uint256 end) {
        return registry.epochBounds(epoch);
    }

    function notifySlashReward(uint256 epoch, address project, uint256 amount) external {
        if (msg.sender != slashingContract) revert MatroidErrors.NotSlashing();
        if (amount == 0) return;
        _slashRewards[epoch][project] += amount;
        emit SlashRewardNotified(epoch, project, amount);
    }

    function resolveSlash(uint256 epoch, address project) external nonReentrant {
        _resolveSlash(epoch, project);
    }

    function claim(uint256 epoch, address project) external nonReentrant {
        (, uint256 end) = epochBounds(epoch);
        if (block.timestamp <= end) revert MatroidErrors.ClaimNotAvailable();
        if (slashingContract != address(0)) {
            uint256 window = ISlashingCouncil(slashingContract).votingWindow();
            MatroidLibrary.EpochData memory data = _epochData[epoch];
            if (block.timestamp <= data.finalizedAt + window) revert MatroidErrors.ClaimNotAvailable();
        }
        if (block.timestamp > end + claimWindow) revert MatroidErrors.ClaimNotAvailable();
        if (!registry.isClaimer(project, msg.sender)) revert MatroidErrors.NotClaimer();

        computeClaimable(epoch, project);
        if (slashingContract != address(0)) {
            ISlashingCouncil(slashingContract).finalizeProposal(epoch, project);
            ISlashingCouncil(slashingContract).resolveFailure(epoch, project);
        }

        uint256 amount = _claimable[epoch][project];
        uint256 slashReward = _slashRewards[epoch][project];
        if (slashReward > 0) {
            _slashRewards[epoch][project] = 0;
            amount += slashReward;
        }
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        _claimable[epoch][project] = 0;
        if (distributionStart == 0) {
            distributionStart = block.timestamp;
            emit DistributionStarted(distributionStart);
        }
        uint16 slashBps = _epochSlashBps[epoch][project];
        if (_blacklisted[project]) {
            slashBps = 10_000;
        }
        if (_slashResolved[epoch][project]) {
            slashBps = 0;
        }
        uint256 slashedAmount = 0;
        uint256 claimableAmount = amount;
        if (slashBps > 0) {
            slashedAmount = (amount * slashBps) / 10_000;
            claimableAmount = amount - slashedAmount;
        }
        if (slashedAmount > 0) {
            uint256 voterReward = _resolveSlashWithAmount(epoch, project, slashedAmount);
            if (voterReward > 0) {
                totalDistributed += voterReward;
                emit SlashResolved(epoch, project, voterReward);
            }
        }

        (
            address erc20Pool,
            address nftPool,
            uint16 globalSplitBps,
            uint16 projectErc20SplitBps,
            uint16 projectNftSplitBps
        ) = registry.projectRewards(project);
        if (globalSplitBps > 0 && address(globalPool) == address(0)) {
            revert MatroidErrors.PoolNotSet();
        }
        uint256 globalShare = (claimableAmount * globalSplitBps) / 10_000;
        uint256 projectErc20Share = (claimableAmount * projectErc20SplitBps) / 10_000;
        uint256 projectNftShare = (claimableAmount * projectNftSplitBps) / 10_000;
        uint256 claimerShare = claimableAmount - globalShare - projectErc20Share - projectNftShare;

        if (globalShare > 0) {
            mona.forceApprove(address(globalPool), globalShare);
            globalPool.notifyReward(globalShare);
            mona.forceApprove(address(globalPool), 0);
        }

        if (projectErc20Share > 0) {
            if (erc20Pool == address(0)) revert MatroidErrors.PoolNotSet();
            mona.forceApprove(erc20Pool, projectErc20Share);
            ProjectStakingPool(erc20Pool).notifyRewardToken(address(mona), projectErc20Share);
            mona.forceApprove(erc20Pool, 0);
        }

        if (projectNftShare > 0) {
            if (nftPool == address(0)) revert MatroidErrors.PoolNotSet();
            mona.forceApprove(nftPool, projectNftShare);
            ProjectNFTStakingPool(nftPool).notifyRewardToken(address(mona), projectNftShare);
            mona.forceApprove(nftPool, 0);
        }

        if (claimerShare > 0) {
            mona.safeTransfer(msg.sender, claimerShare);
        }
        if (claimableAmount > 0) {
            totalDistributed += claimableAmount;
        }
        emit Claimed(epoch, project, msg.sender, amount);
    }

    function _resolveSlash(uint256 epoch, address project) internal {
        (, uint256 end) = epochBounds(epoch);
        if (block.timestamp <= end) revert MatroidErrors.ClaimNotAvailable();
        if (block.timestamp > end + claimWindow) revert MatroidErrors.ClaimNotAvailable();
        if (slashingContract != address(0)) {
            uint256 window = ISlashingCouncil(slashingContract).votingWindow();
            MatroidLibrary.EpochData memory data = _epochData[epoch];
            if (block.timestamp <= data.finalizedAt + window) revert MatroidErrors.ClaimNotAvailable();
            ISlashingCouncil(slashingContract).finalizeProposal(epoch, project);
            ISlashingCouncil(slashingContract).resolveFailure(epoch, project);
        }
        if (!_blacklisted[project] && !_epochSlashed[epoch][project]) revert MatroidErrors.ClaimNotAvailable();
        if (_slashResolved[epoch][project]) return;
        computeClaimable(epoch, project);
        uint256 amount = _claimable[epoch][project];
        uint256 slashReward = _slashRewards[epoch][project];
        if (slashReward > 0) {
            _slashRewards[epoch][project] = 0;
            amount += slashReward;
        }
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        _claimable[epoch][project] = 0;
        if (distributionStart == 0) {
            distributionStart = block.timestamp;
            emit DistributionStarted(distributionStart);
        }
        uint16 slashBps = _epochSlashBps[epoch][project];
        if (_blacklisted[project]) {
            slashBps = 10_000;
        }
        if (_slashResolved[epoch][project]) {
            slashBps = 0;
        }
        uint256 slashedAmount = 0;
        uint256 remaining = amount;
        if (slashBps > 0) {
            slashedAmount = (amount * slashBps) / 10_000;
            remaining = amount - slashedAmount;
        }
        if (slashedAmount > 0) {
            uint256 voterReward = _resolveSlashWithAmount(epoch, project, slashedAmount);
            if (voterReward > 0) {
                totalDistributed += voterReward;
                emit SlashResolved(epoch, project, voterReward);
            }
        }
        _claimable[epoch][project] = remaining;
    }

    function _resolveSlashWithAmount(
        uint256 epoch,
        address project,
        uint256 amount
    ) internal returns (uint256 voterReward) {
        if (_slashResolved[epoch][project]) return 0;
        _slashResolved[epoch][project] = true;
        if (slashingContract == address(0)) return 0;
        voterReward = amount / 2;
        if (voterReward > 0) {
            mona.safeTransfer(slashingContract, voterReward);
            ISlashingCouncil(slashingContract).notifyVoterReward(epoch, project, voterReward);
        }
    }
}
