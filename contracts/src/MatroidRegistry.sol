// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MatroidErrors.sol";
import "./MatroidLibrary.sol";
import {StakingFactory} from "./StakingFactory.sol";

contract MatroidRegistry is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable mona;
    address public matroidKit;
    address public owner;
    uint256 public immutable epochDuration;
    uint256 public immutable deployedAt;
    uint256 public immutable maxTxPerWallet;
    uint256 public immutable maxVolumePerWallet;
    StakingFactory public stakingFactory;

    mapping(address => MatroidLibrary.Project) private _projects;
    mapping(address => mapping(address => MatroidLibrary.TokenStats))
        private _projectTokenStats;
    mapping(address => mapping(address => mapping(address => bool)))
        private _projectTokenUserSeen;
    mapping(address => mapping(address => bool)) private _projectClaimers;
    mapping(address => mapping(uint256 => MatroidLibrary.EpochStats))
        private _epochStats;
    mapping(address => mapping(uint256 => mapping(address => bool)))
        private _epochMonaUserSeen;
    mapping(address => mapping(uint256 => mapping(address => bool)))
        private _epochOtherUserSeen;
    mapping(address => mapping(uint256 => mapping(address => bool)))
        private _epochOtherTokenCounted;
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        private _epochMonaUserTxCount;
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        private _epochMonaUserVolume;
    mapping(uint256 => mapping(address => uint256))
        private _epochTokenProjectCount;
    mapping(uint256 => mapping(address => mapping(address => bool)))
        private _epochTokenProjectSeen;
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        private _epochOtherTokenUniqueUsers;
    mapping(address => mapping(uint256 => mapping(address => mapping(address => bool))))
        private _epochOtherTokenUserSeen;
    address[] private _projectList;
    mapping(address => bool) private _listed;

    event ProjectRegistered(address indexed project, string metadata);
    event ClaimerUpdated(
        address indexed project,
        address indexed claimer,
        bool allowed
    );
    event ProjectPoolsCreated(
        address indexed project,
        address erc20Pool,
        address nftPool
    );
    event RewardSplitsUpdated(
        address indexed project,
        uint16 globalSplitBps,
        uint16 projectErc20SplitBps,
        uint16 projectNftSplitBps
    );
    event FlowRecorded(
        address indexed project,
        address indexed user,
        address indexed token,
        uint256 amount,
        bool isIn
    );
    event ProjectMetadataUpdated(address indexed project, string metadata);
    event ProjectLeft(address indexed project);
    event ProjectErased(address indexed project);
    event EpochErased(address indexed project, uint256 indexed epoch);
    event ChipWeightCredited(address indexed project, uint256 indexed epoch);

    constructor(
        address monaToken,
        address stakingFactoryAddress,
        uint256 epochDurationSeconds,
        uint256 maxTxPerWalletCount,
        uint256 maxVolumePerWalletAmount
    ) {
        if (monaToken == address(0)) revert MatroidErrors.ZeroAddress();
        if (stakingFactoryAddress == address(0))
            revert MatroidErrors.ZeroAddress();
        if (epochDurationSeconds == 0) revert MatroidErrors.ZeroAmount();
        if (maxTxPerWalletCount == 0) revert MatroidErrors.ZeroAmount();
        if (maxVolumePerWalletAmount == 0) revert MatroidErrors.ZeroAmount();
        owner = msg.sender;
        mona = IERC20(monaToken);
        epochDuration = epochDurationSeconds;
        deployedAt = block.timestamp;
        maxTxPerWallet = maxTxPerWalletCount;
        maxVolumePerWallet = maxVolumePerWalletAmount;
        stakingFactory = StakingFactory(stakingFactoryAddress);
    }

    modifier onlyMatroidKit() {
        if (msg.sender != matroidKit) revert MatroidErrors.NotMatroidKit();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert MatroidErrors.NotOwner();
        _;
    }

    function setMatroidKit(address newKit) external onlyOwner {
        if (matroidKit != address(0)) revert MatroidErrors.AlreadySet();
        if (newKit == address(0)) revert MatroidErrors.ZeroAddress();
        matroidKit = newKit;
    }

    function registerProject(
        address project,
        string calldata metadata,
        bool pool
    ) external onlyMatroidKit {
        if (project == address(0)) revert MatroidErrors.ZeroAddress();
        if (project.code.length == 0) revert MatroidErrors.NotContract();
        MatroidLibrary.Project storage info = _projects[project];
        if (info.registered) revert MatroidErrors.AlreadyRegistered();
        info.registered = true;
        info.project = project;
        info.metadata = metadata;
        info.registeredAt = uint64(block.timestamp);
        if (!_listed[project]) {
            _projectList.push(project);
            _listed[project] = true;
        }

        // registration event must precede pool creation: the subgraph's pool
        // handler loads the Project entity created by ProjectRegistered
        emit ProjectRegistered(project, metadata);

        if (pool) {
            _createPool(project);
        }
    }

    function createProjectPool() external {
        _createPool(msg.sender);
    }

    function updateMetadata(string calldata metadata) external {
        MatroidLibrary.Project storage info = _projects[msg.sender];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();
        info.metadata = metadata;
        emit ProjectMetadataUpdated(msg.sender, metadata);
    }

    function leave() external {
        MatroidLibrary.Project storage info = _projects[msg.sender];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();
        info.registered = false;
        delete _epochStats[msg.sender][currentEpoch()];
        emit ProjectLeft(msg.sender);
    }

    function eraseSelf() external {
        if (!_listed[msg.sender]) revert MatroidErrors.ProjectNotRegistered();
        delete _projects[msg.sender];
        delete _epochStats[msg.sender][currentEpoch()];
        emit ProjectErased(msg.sender);
    }

    function eraseEpoch(uint256 epoch) external {
        if (!_listed[msg.sender]) revert MatroidErrors.ProjectNotRegistered();
        delete _epochStats[msg.sender][epoch];
        emit EpochErased(msg.sender, epoch);
    }

    function creditChipWeight(address project) external onlyMatroidKit {
        _epochStats[project][currentEpoch()].weightedUniqueUsers += 1;
        emit ChipWeightCredited(project, currentEpoch());
    }

    function _createPool(address project) internal {
        MatroidLibrary.Project storage info = _projects[project];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();
        if (address(stakingFactory) == address(0))
            revert MatroidErrors.ZeroAddress();
        if (info.projectPool != address(0) && info.projectNftPool != address(0))
            return;
        (address erc20Pool, address nftPool) = stakingFactory
            .createProjectPools(address(mona), project);
        info.projectPool = erc20Pool;
        info.projectNftPool = nftPool;
        emit ProjectPoolsCreated(project, erc20Pool, nftPool);
    }

    function setRewardSplits(
        uint16 globalSplitBps,
        uint16 projectErc20SplitBps,
        uint16 projectNftSplitBps
    ) external {
        MatroidLibrary.Project storage info = _projects[msg.sender];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();
        if (
            uint256(globalSplitBps) +
                uint256(projectErc20SplitBps) +
                uint256(projectNftSplitBps) >
            10_000
        ) {
            revert MatroidErrors.InvalidSplit();
        }
        if (projectErc20SplitBps > 0 && info.projectPool == address(0)) {
            revert MatroidErrors.PoolNotSet();
        }
        if (projectNftSplitBps > 0 && info.projectNftPool == address(0)) {
            revert MatroidErrors.PoolNotSet();
        }
        info.globalSplitBps = globalSplitBps;
        info.projectErc20SplitBps = projectErc20SplitBps;
        info.projectNftSplitBps = projectNftSplitBps;
        emit RewardSplitsUpdated(
            msg.sender,
            globalSplitBps,
            projectErc20SplitBps,
            projectNftSplitBps
        );
    }

    function projectCount() external view returns (uint256) {
        return _projectList.length;
    }

    function projectAt(uint256 index) external view returns (address) {
        return _projectList[index];
    }

    function getProject(
        address project
    ) external view returns (MatroidLibrary.Project memory) {
        return _projects[project];
    }

    function projectRewards(
        address project
    )
        external
        view
        returns (
            address erc20Pool,
            address nftPool,
            uint16 globalSplitBps,
            uint16 projectErc20SplitBps,
            uint16 projectNftSplitBps
        )
    {
        MatroidLibrary.Project storage info = _projects[project];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();
        return (
            info.projectPool,
            info.projectNftPool,
            info.globalSplitBps,
            info.projectErc20SplitBps,
            info.projectNftSplitBps
        );
    }

    function projectTokenStats(
        address project,
        address token
    ) external view returns (MatroidLibrary.TokenStats memory) {
        return _projectTokenStats[project][token];
    }

    function projectTokenUserSeen(
        address project,
        address token,
        address user
    ) external view returns (bool) {
        return _projectTokenUserSeen[project][token][user];
    }

    function projectClaimers(
        address project,
        address claimer
    ) external view returns (bool) {
        return _projectClaimers[project][claimer];
    }

    function getEpochStats(
        address project,
        uint256 epoch
    ) external view returns (MatroidLibrary.EpochStats memory) {
        return _epochStats[project][epoch];
    }

    function epochMonaUserSeen(
        address project,
        uint256 epoch,
        address user
    ) external view returns (bool) {
        return _epochMonaUserSeen[project][epoch][user];
    }

    function epochOtherUserSeen(
        address project,
        uint256 epoch,
        address user
    ) external view returns (bool) {
        return _epochOtherUserSeen[project][epoch][user];
    }

    function epochOtherTokenCounted(
        address project,
        uint256 epoch,
        address token
    ) external view returns (bool) {
        return _epochOtherTokenCounted[project][epoch][token];
    }

    function epochMonaUserTxCount(
        address project,
        uint256 epoch,
        address user
    ) external view returns (uint256) {
        return _epochMonaUserTxCount[project][epoch][user];
    }

    function epochMonaUserVolume(
        address project,
        uint256 epoch,
        address user
    ) external view returns (uint256) {
        return _epochMonaUserVolume[project][epoch][user];
    }

    function epochTokenProjectCount(
        uint256 epoch,
        address token
    ) external view returns (uint256) {
        return _epochTokenProjectCount[epoch][token];
    }

    function epochTokenProjectSeen(
        uint256 epoch,
        address token,
        address project
    ) external view returns (bool) {
        return _epochTokenProjectSeen[epoch][token][project];
    }

    function epochOtherTokenUniqueUsers(
        address project,
        uint256 epoch,
        address token
    ) external view returns (uint256) {
        return _epochOtherTokenUniqueUsers[project][epoch][token];
    }

    function epochOtherTokenUserSeen(
        address project,
        uint256 epoch,
        address token,
        address user
    ) external view returns (bool) {
        return _epochOtherTokenUserSeen[project][epoch][token][user];
    }

    function setClaimer(address claimer, bool allowed) external {
        if (claimer == address(0)) revert MatroidErrors.ZeroAddress();
        MatroidLibrary.Project storage info = _projects[msg.sender];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();
        _projectClaimers[msg.sender][claimer] = allowed;
        emit ClaimerUpdated(msg.sender, claimer, allowed);
    }

    function isClaimer(
        address project,
        address claimer
    ) external view returns (bool) {
        return _projectClaimers[project][claimer];
    }

    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - deployedAt) / epochDuration;
    }

    function epochBounds(
        uint256 epoch
    ) public view returns (uint256 start, uint256 end) {
        start = deployedAt + (epoch * epochDuration);
        end = start + epochDuration;
    }

    function recordFlow(
        address project,
        address user,
        address token,
        uint256 amount,
        bool isIn
    ) external onlyMatroidKit nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        MatroidLibrary.Project storage info = _projects[project];
        if (!info.registered) revert MatroidErrors.ProjectNotRegistered();

        IERC20 asset = IERC20(token);
        address receiver = isIn ? project : user;
        uint256 beforeBal = asset.balanceOf(receiver);
        if (isIn) {
            asset.safeTransferFrom(user, project, amount);
        } else {
            asset.safeTransferFrom(project, user, amount);
        }
        uint256 afterBal = asset.balanceOf(receiver);
        if (afterBal <= beforeBal) revert MatroidErrors.ZeroAmount();
        uint256 actualAmount = afterBal - beforeBal;

        MatroidLibrary.TokenStats storage stats = _projectTokenStats[project][
            token
        ];
        if (!_projectTokenUserSeen[project][token][user]) {
            _projectTokenUserSeen[project][token][user] = true;
            stats.uniqueUsers += 1;
            if (token == address(mona)) {
                info.monaUniqueUsers += 1;
            }
        }

        if (isIn) {
            stats.totalIn += actualAmount;
            if (token == address(mona)) {
                info.monaIn += actualAmount;
            }
        } else {
            stats.totalOut += actualAmount;
            if (token == address(mona)) {
                info.monaOut += actualAmount;
            }
        }

        stats.txCount += 1;
        if (token == address(mona)) {
            info.monaTxCount += 1;
        }

        uint256 epoch = currentEpoch();
        if (token == address(mona)) {
            _recordMonaEpoch(project, user, actualAmount, epoch);
        } else {
            _recordOtherEpoch(project, user, token, epoch);
        }
        emit FlowRecorded(project, user, token, actualAmount, isIn);
    }

    function _recordMonaEpoch(
        address project,
        address user,
        uint256 amount,
        uint256 epoch
    ) internal {
        MatroidLibrary.EpochStats storage _epochInfo = _epochStats[project][
            epoch
        ];

        if (!_epochMonaUserSeen[project][epoch][user]) {
            _epochMonaUserSeen[project][epoch][user] = true;
            _epochInfo.monaUniqueUsers += 1;
            _epochInfo.weightedUniqueUsers += 1;
            if (epoch > 0 && _epochMonaUserSeen[project][epoch - 1][user]) {
                _epochInfo.monaRecurringUsers += 1;
            }
        }

        _epochInfo.monaTxCount += 1;
        _epochInfo.monaTotalVolume += amount;

        uint256 prevTx = _epochMonaUserTxCount[project][epoch][user];
        uint256 nextTx = prevTx + 1;
        _epochMonaUserTxCount[project][epoch][user] = nextTx;
        uint256 cappedPrevTx = prevTx > maxTxPerWallet
            ? maxTxPerWallet
            : prevTx;
        uint256 cappedNextTx = nextTx > maxTxPerWallet
            ? maxTxPerWallet
            : nextTx;
        _epochInfo.monaCappedTxCount += (cappedNextTx - cappedPrevTx);

        uint256 prevVol = _epochMonaUserVolume[project][epoch][user];
        uint256 nextVol = prevVol + amount;
        _epochMonaUserVolume[project][epoch][user] = nextVol;
        uint256 cappedPrevVol = prevVol > maxVolumePerWallet
            ? maxVolumePerWallet
            : prevVol;
        uint256 cappedNextVol = nextVol > maxVolumePerWallet
            ? maxVolumePerWallet
            : nextVol;
        _epochInfo.monaCappedVolume += (cappedNextVol - cappedPrevVol);
    }

    function _recordOtherEpoch(
        address project,
        address user,
        address token,
        uint256 epoch
    ) internal {
        MatroidLibrary.EpochStats storage epochInfo = _epochStats[project][
            epoch
        ];
        if (!_epochOtherUserSeen[project][epoch][user]) {
            _epochOtherUserSeen[project][epoch][user] = true;
            epochInfo.otherUniqueUsers += 1;
        }
        epochInfo.otherTxCount += 1;
        if (!_epochTokenProjectSeen[epoch][token][project]) {
            _epochTokenProjectSeen[epoch][token][project] = true;
            _epochTokenProjectCount[epoch][token] += 1;
        }

        if (!_epochOtherTokenUserSeen[project][epoch][token][user]) {
            _epochOtherTokenUserSeen[project][epoch][token][user] = true;
            _epochOtherTokenUniqueUsers[project][epoch][token] += 1;
        }

        if (
            _epochOtherTokenUniqueUsers[project][epoch][token] >= 10 &&
            _epochTokenProjectCount[epoch][token] >= 2 &&
            !_epochOtherTokenCounted[project][epoch][token]
        ) {
            _epochOtherTokenCounted[project][epoch][token] = true;
            epochInfo.otherTokensUsed += 1;
        }
    }
}
