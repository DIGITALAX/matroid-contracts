// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaAccessControl.sol";
import "./GandaGames.sol";
import {MatroidKit} from "../MatroidKit.sol";
import {MatroidRegistry} from "../MatroidRegistry.sol";
import {GlobalStakingPool} from "../GlobalStakingPool.sol";
import {ProjectStakingPool} from "../ProjectStakingPool.sol";
import {ProjectNFTStakingPool} from "../ProjectNFTStakingPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IGandaPot {
    function notifyPot(uint256 epoch, uint256 gameId, uint256 amount) external;
}

contract GandaHub is ReentrancyGuard {
    using SafeERC20 for IERC20;

    GandaAccessControl public immutable accessControl;
    GandaGames public immutable games;
    MatroidKit public immutable matroidKit;
    MatroidRegistry public immutable registry;
    GlobalStakingPool public immutable globalPool;
    IERC20 public immutable mona;

    address public score;
    uint16 public potBps;
    bool public bootstrapped;

    mapping(uint256 => mapping(uint256 => uint256)) public gameEpochUniquePlayers;
    mapping(uint256 => mapping(uint256 => uint256)) public gameEpochCappedVolume;
    mapping(uint256 => mapping(uint256 => uint256)) public gameEpochWeight;
    mapping(uint256 => uint256) public epochTotalWeight;
    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        private _gameEpochPlayerSeen;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        private _gameEpochPlayerVolume;

    event Bootstrapped(string metadata, uint16 globalBps, uint16 projectBps, uint16 nftBps, uint16 potBps);
    event FlowIn(uint256 indexed gameId, address indexed player, uint256 amount, address destination, uint256 epoch);
    event FlowOut(uint256 indexed gameId, address indexed recipient, uint256 amount, uint256 epoch);
    event PotFunded(uint256 indexed epoch, uint256 indexed gameId, uint256 amount);
    event SplitsSet(uint16 globalBps, uint16 projectBps, uint16 nftBps, uint16 potBps);
    event ScoreSet(address score);
    event LeftMatroid();
    event ErasedMatroid();
    event ErasedEpoch(uint256 epoch);

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    modifier onlyScorer(uint256 gameId) {
        if (!games.isActive(gameId)) revert GandaErrors.GameNotActive();
        if (games.scorerOf(gameId) != msg.sender) revert GandaErrors.NotScorer();
        _;
    }

    constructor(
        address accessControlAddress,
        address gamesAddress,
        address matroidKitAddress,
        address globalPoolAddress
    ) {
        if (
            accessControlAddress == address(0) ||
            gamesAddress == address(0) ||
            matroidKitAddress == address(0) ||
            globalPoolAddress == address(0)
        ) revert GandaErrors.ZeroAddress();
        accessControl = GandaAccessControl(accessControlAddress);
        games = GandaGames(gamesAddress);
        matroidKit = MatroidKit(matroidKitAddress);
        registry = MatroidKit(matroidKitAddress).registry();
        globalPool = GlobalStakingPool(globalPoolAddress);
        mona = IERC20(MatroidKit(matroidKitAddress).registry().mona());
    }

    function bootstrap(
        string calldata metadata,
        uint16 globalBps,
        uint16 projectBps,
        uint16 nftBps,
        uint16 potBpsValue
    ) external onlyAdmin {
        if (bootstrapped) revert GandaErrors.AlreadySet();
        if (score == address(0)) revert GandaErrors.ZeroAddress();
        _checkSplits(globalBps, projectBps, nftBps, potBpsValue);
        matroidKit.registerProject(metadata, true);
        registry.setRewardSplits(globalBps, projectBps, nftBps);
        potBps = potBpsValue;
        bootstrapped = true;
        emit Bootstrapped(metadata, globalBps, projectBps, nftBps, potBpsValue);
    }

    function setScore(address scoreAddress) external onlyAdmin {
        if (scoreAddress == address(0)) revert GandaErrors.ZeroAddress();
        if (score != address(0)) revert GandaErrors.AlreadySet();
        score = scoreAddress;
        emit ScoreSet(scoreAddress);
    }

    function setSplits(
        uint16 globalBps,
        uint16 projectBps,
        uint16 nftBps,
        uint16 potBpsValue
    ) external onlyAdmin {
        if (!bootstrapped) revert GandaErrors.ProjectNotRegistered();
        _checkSplits(globalBps, projectBps, nftBps, potBpsValue);
        registry.setRewardSplits(globalBps, projectBps, nftBps);
        potBps = potBpsValue;
        emit SplitsSet(globalBps, projectBps, nftBps, potBpsValue);
    }

    function monaIn(
        uint256 gameId,
        address player,
        uint256 amount,
        address destination
    ) external nonReentrant onlyScorer(gameId) {
        if (destination == address(0)) revert GandaErrors.ZeroAddress();
        if (!bootstrapped) revert GandaErrors.ProjectNotRegistered();
        matroidKit.matroidIn(player, address(mona), amount);
        _settleIn(gameId, player, amount, destination);
    }

    function monaInVerified(
        uint256 gameId,
        address player,
        uint256 amount,
        address destination,
        bytes32 merkleRoot,
        bytes calldata proof,
        bytes32 nullifier
    ) external nonReentrant onlyScorer(gameId) {
        if (destination == address(0)) revert GandaErrors.ZeroAddress();
        if (!bootstrapped) revert GandaErrors.ProjectNotRegistered();
        matroidKit.matroidInVerified(player, address(mona), amount, merkleRoot, proof, nullifier);
        _settleIn(gameId, player, amount, destination);
    }

    function monaOut(
        uint256 gameId,
        address recipient,
        uint256 amount
    ) external nonReentrant onlyScorer(gameId) {
        if (!bootstrapped) revert GandaErrors.ProjectNotRegistered();
        _settleOut(gameId, recipient, amount);
        matroidKit.matroidOut(recipient, address(mona), amount);
        mona.forceApprove(address(registry), 0);
    }

    function monaOutVerified(
        uint256 gameId,
        address recipient,
        uint256 amount,
        bytes32 merkleRoot,
        bytes calldata proof,
        bytes32 nullifier
    ) external nonReentrant onlyScorer(gameId) {
        if (!bootstrapped) revert GandaErrors.ProjectNotRegistered();
        _settleOut(gameId, recipient, amount);
        matroidKit.matroidOutVerified(recipient, address(mona), amount, merkleRoot, proof, nullifier);
        mona.forceApprove(address(registry), 0);
    }

    function leaveMatroid() external onlyAdmin {
        registry.leave();
        emit LeftMatroid();
    }

    function eraseMatroid() external onlyAdmin {
        registry.eraseSelf();
        emit ErasedMatroid();
    }

    function eraseEpoch(uint256 epoch) external onlyAdmin {
        registry.eraseEpoch(epoch);
        emit ErasedEpoch(epoch);
    }

    function currentEpoch() public view returns (uint256) {
        return registry.currentEpoch();
    }

    function _settleIn(
        uint256 gameId,
        address player,
        uint256 amount,
        address destination
    ) private {
        uint256 epoch = registry.currentEpoch();
        (
            ,
            ,
            uint16 globalBps,
            uint16 projectBps,
            uint16 nftBps
        ) = registry.projectRewards(address(this));

        uint256 globalShare = (amount * globalBps) / 10_000;
        uint256 projectShare = (amount * projectBps) / 10_000;
        uint256 nftShare = (amount * nftBps) / 10_000;
        uint256 potShare = (amount * potBps) / 10_000;
        uint256 rest = amount - globalShare - projectShare - nftShare - potShare;

        _streamToPools(globalShare, projectShare, nftShare);

        if (potShare > 0) {
            mona.safeTransfer(score, potShare);
            IGandaPot(score).notifyPot(epoch, gameId, potShare);
            emit PotFunded(epoch, gameId, potShare);
        }
        if (rest > 0) {
            mona.safeTransfer(destination, rest);
        }

        _recordActivity(epoch, gameId, player, amount);
        emit FlowIn(gameId, player, amount, destination, epoch);
    }

    function _settleOut(uint256 gameId, address recipient, uint256 amount) private {
        uint256 epoch = registry.currentEpoch();
        mona.safeTransferFrom(msg.sender, address(this), amount);
        mona.forceApprove(address(registry), amount);
        _recordActivity(epoch, gameId, recipient, amount);
        emit FlowOut(gameId, recipient, amount, epoch);
    }

    function _streamToPools(
        uint256 globalShare,
        uint256 projectShare,
        uint256 nftShare
    ) private {
        if (globalShare > 0) {
            mona.forceApprove(address(globalPool), globalShare);
            globalPool.notifyReward(globalShare);
            mona.forceApprove(address(globalPool), 0);
        }
        if (projectShare > 0 || nftShare > 0) {
            (address erc20Pool, address nftPool, , , ) = registry.projectRewards(address(this));
            if (projectShare > 0) {
                if (erc20Pool == address(0)) revert GandaErrors.ZeroAddress();
                mona.forceApprove(erc20Pool, projectShare);
                ProjectStakingPool(erc20Pool).notifyRewardToken(address(mona), projectShare);
                mona.forceApprove(erc20Pool, 0);
            }
            if (nftShare > 0) {
                if (nftPool == address(0)) revert GandaErrors.ZeroAddress();
                mona.forceApprove(nftPool, nftShare);
                ProjectNFTStakingPool(nftPool).notifyRewardToken(address(mona), nftShare);
                mona.forceApprove(nftPool, 0);
            }
        }
    }

    function _recordActivity(
        uint256 epoch,
        uint256 gameId,
        address wallet,
        uint256 amount
    ) private {
        if (!_gameEpochPlayerSeen[epoch][gameId][wallet]) {
            _gameEpochPlayerSeen[epoch][gameId][wallet] = true;
            gameEpochUniquePlayers[epoch][gameId] += 1;
        }

        uint256 cap = registry.maxVolumePerWallet();
        uint256 prevVol = _gameEpochPlayerVolume[epoch][gameId][wallet];
        uint256 nextVol = prevVol + amount;
        _gameEpochPlayerVolume[epoch][gameId][wallet] = nextVol;
        uint256 cappedPrev = prevVol > cap ? cap : prevVol;
        uint256 cappedNext = nextVol > cap ? cap : nextVol;
        gameEpochCappedVolume[epoch][gameId] += (cappedNext - cappedPrev);

        uint256 oldWeight = gameEpochWeight[epoch][gameId];
        uint256 newWeight = _sqrt(gameEpochUniquePlayers[epoch][gameId]) *
            gameEpochCappedVolume[epoch][gameId];
        gameEpochWeight[epoch][gameId] = newWeight;
        epochTotalWeight[epoch] = epochTotalWeight[epoch] + newWeight - oldWeight;
    }

    function _checkSplits(
        uint16 globalBps,
        uint16 projectBps,
        uint16 nftBps,
        uint16 potBpsValue
    ) private pure {
        if (
            uint256(globalBps) + uint256(projectBps) + uint256(nftBps) + uint256(potBpsValue) >
            10_000
        ) revert GandaErrors.InvalidSplit();
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y == 0) return 0;
        z = y;
        uint256 x = (y / 2) + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}
