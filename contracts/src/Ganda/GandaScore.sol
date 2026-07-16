// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaAccessControl.sol";
import "./GandaBlacklist.sol";
import "./GandaGames.sol";
import "./GandaHub.sol";
import {IVerifier} from "../zk/IVerifier.sol";
import {IdentityActionBase} from "../zk/IdentityActionBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GandaScore is IdentityActionBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant SCALE = 1e18;
    bytes4 public constant CLAIM_TAG = bytes4(keccak256("gandaScore.claim"));

    GandaAccessControl public immutable accessControl;
    GandaBlacklist public immutable blacklist;
    GandaGames public immutable games;
    GandaHub public immutable hub;
    IVerifier public immutable ownerVerifier;
    IERC20 public immutable mona;

    uint16 public gamesPotBps;
    uint256 public claimWindowEpochs;

    mapping(uint256 => uint256) public epochPot;
    mapping(uint256 => uint256) public epochPotRemaining;
    mapping(uint256 => mapping(uint256 => mapping(bytes32 => uint256)))
        public epochPlayerPoints;
    mapping(uint256 => mapping(uint256 => uint256)) public epochGameTotalPoints;
    mapping(uint256 => mapping(uint256 => uint256)) public epochGamePlayerCount;
    mapping(uint256 => mapping(bytes32 => uint256[])) private _playerGames;
    mapping(uint256 => uint256) public epochGamesWithPoints;
    mapping(uint256 => mapping(uint256 => bool)) public gameHasPoints;
    mapping(uint256 => uint256) public epochBannedWithPoints;
    mapping(uint256 => mapping(uint256 => bool)) public bannedCounted;
    mapping(uint256 => mapping(bytes32 => bool)) public playerClaimed;
    mapping(uint256 => mapping(uint256 => bool)) public gameClaimed;

    event ScoreSubmitted(uint256 indexed epoch, uint256 indexed gameId, bytes32 indexed playerKey, uint256 points, bool anonymous);
    event PotNotified(uint256 indexed epoch, uint256 indexed gameId, uint256 amount);
    event PlayerClaimed(uint256 indexed epoch, bytes32 indexed playerKey, address payout, uint256 amount);
    event GamePotClaimed(uint256 indexed epoch, uint256 indexed gameId, address payout, uint256 amount);
    event BanSynced(uint256 indexed epoch, uint256 indexed gameId, bool banned);
    event ExpiredRolled(uint256 indexed fromEpoch, uint256 indexed toEpoch, uint256 amount);
    event PlayerErased(uint256 indexed epoch, bytes32 indexed playerKey);
    event ParamsSet(uint16 gamesPotBps, uint256 claimWindowEpochs);

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
        address actionVerifierAddress,
        address rootsAddress,
        address ownerVerifierAddress,
        address accessControlAddress,
        address blacklistAddress,
        address gamesAddress,
        address hubAddress,
        uint16 gamesPotBpsValue,
        uint256 claimWindowEpochsValue
    ) IdentityActionBase(actionVerifierAddress, rootsAddress) {
        if (
            ownerVerifierAddress == address(0) ||
            accessControlAddress == address(0) ||
            blacklistAddress == address(0) ||
            gamesAddress == address(0) ||
            hubAddress == address(0)
        ) revert GandaErrors.ZeroAddress();
        if (gamesPotBpsValue > 10_000) revert GandaErrors.InvalidSplit();
        if (claimWindowEpochsValue == 0) revert GandaErrors.InvalidInput();
        ownerVerifier = IVerifier(ownerVerifierAddress);
        accessControl = GandaAccessControl(accessControlAddress);
        blacklist = GandaBlacklist(blacklistAddress);
        games = GandaGames(gamesAddress);
        hub = GandaHub(hubAddress);
        mona = GandaHub(hubAddress).mona();
        gamesPotBps = gamesPotBpsValue;
        claimWindowEpochs = claimWindowEpochsValue;
    }

    function setParams(uint16 gamesPotBpsValue, uint256 claimWindowEpochsValue) external onlyAdmin {
        if (gamesPotBpsValue > 10_000) revert GandaErrors.InvalidSplit();
        if (claimWindowEpochsValue == 0) revert GandaErrors.InvalidInput();
        gamesPotBps = gamesPotBpsValue;
        claimWindowEpochs = claimWindowEpochsValue;
        emit ParamsSet(gamesPotBpsValue, claimWindowEpochsValue);
    }

    function notifyPot(uint256 epoch, uint256 gameId, uint256 amount) external {
        if (msg.sender != address(hub)) revert GandaErrors.Unauthorized();
        epochPot[epoch] += amount;
        epochPotRemaining[epoch] += amount;
        emit PotNotified(epoch, gameId, amount);
    }

    function submitScore(
        uint256 gameId,
        address player,
        uint256 points
    ) external onlyScorer(gameId) {
        if (player == address(0)) revert GandaErrors.ZeroAddress();
        _record(gameId, bytes32(uint256(uint160(player))), points, false);
    }

    function submitScoreAnon(
        uint256 gameId,
        bytes32 playerNullifier,
        uint256 points
    ) external onlyScorer(gameId) {
        if (playerNullifier == bytes32(0)) revert GandaErrors.InvalidInput();
        _record(gameId, playerNullifier, points, true);
    }

    function claim(uint256 epoch, address payout) external nonReentrant {
        bytes32 playerKey = bytes32(uint256(uint160(msg.sender)));
        uint256 amount = _settlePlayerClaim(epoch, playerKey, payout);
        emit PlayerClaimed(epoch, playerKey, payout, amount);
    }

    function claimAnon(
        uint256 epoch,
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        address payout
    ) external nonReentrant {
        bytes32 payloadHash = keccak256(abi.encode(epoch, payout));
        _verifyAction(proof, CLAIM_TAG, epoch, payloadHash, nullifier, merkleRoot);
        uint256 amount = _settlePlayerClaim(epoch, nullifier, payout);
        emit PlayerClaimed(epoch, nullifier, payout, amount);
    }

    function claimGame(
        uint256 epoch,
        uint256 gameId,
        bytes calldata ownerProof,
        address payout
    ) external nonReentrant {
        if (payout == address(0)) revert GandaErrors.ZeroAddress();
        _checkClaimWindow(epoch);
        if (gameClaimed[epoch][gameId]) revert GandaErrors.AlreadyClaimed();
        if (!games.isActive(gameId)) revert GandaErrors.GameNotActive();

        GandaLibrary.Game memory game = games.getGame(gameId);
        bytes32 bound = keccak256(abi.encode(epoch, gameId, payout));
        _verifyOwner(ownerProof, game.ownerTag, bound, game.version);

        uint256 totalWeight = hub.epochTotalWeight(epoch);
        uint256 gameWeight = hub.gameEpochWeight(epoch, gameId);
        if (totalWeight == 0 || gameWeight == 0) revert GandaErrors.NothingToClaim();

        uint256 gamesPot = (epochPot[epoch] * gamesPotBps) / 10_000;
        uint256 amount = (gamesPot * gameWeight) / totalWeight;
        if (amount == 0) revert GandaErrors.NothingToClaim();

        gameClaimed[epoch][gameId] = true;
        epochPotRemaining[epoch] -= amount;
        mona.safeTransfer(payout, amount);
        emit GamePotClaimed(epoch, gameId, payout, amount);
    }

    function eraseMe(uint256 epoch) external {
        bytes32 playerKey = bytes32(uint256(uint160(msg.sender)));
        _erasePlayer(epoch, playerKey);
    }

    function eraseMeAnon(
        uint256 epoch,
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier
    ) external {
        bytes32 payloadHash = keccak256(abi.encode(epoch, "erase"));
        _verifyAction(proof, CLAIM_TAG, epoch, payloadHash, nullifier, merkleRoot);
        _erasePlayer(epoch, nullifier);
    }

    function syncBan(uint256 epoch, uint256 gameId) external {
        bool banned = blacklist.isGameBanned(gameId);
        if (!gameHasPoints[epoch][gameId]) revert GandaErrors.NotFound();
        if (banned && !bannedCounted[epoch][gameId]) {
            bannedCounted[epoch][gameId] = true;
            epochBannedWithPoints[epoch] += 1;
            emit BanSynced(epoch, gameId, true);
        } else if (!banned && bannedCounted[epoch][gameId]) {
            bannedCounted[epoch][gameId] = false;
            epochBannedWithPoints[epoch] -= 1;
            emit BanSynced(epoch, gameId, false);
        } else {
            revert GandaErrors.InvalidInput();
        }
    }

    function rollExpired(uint256 epoch) external {
        uint256 current = hub.currentEpoch();
        if (current <= epoch + claimWindowEpochs) revert GandaErrors.VotingOpen();
        uint256 remaining = epochPotRemaining[epoch];
        if (remaining == 0) revert GandaErrors.NothingToClaim();
        epochPotRemaining[epoch] = 0;
        epochPot[current] += remaining;
        epochPotRemaining[current] += remaining;
        emit ExpiredRolled(epoch, current, remaining);
    }

    function notaOf(uint256 epoch, bytes32 playerKey) public view returns (uint256 nota) {
        uint256[] storage gameIds = _playerGames[epoch][playerKey];
        for (uint256 i = 0; i < gameIds.length; i++) {
            uint256 gameId = gameIds[i];
            if (blacklist.isGameBanned(gameId)) continue;
            uint256 total = epochGameTotalPoints[epoch][gameId];
            if (total == 0) continue;
            nota += (epochPlayerPoints[epoch][gameId][playerKey] * SCALE) / total;
        }
    }

    function playerGamesOf(uint256 epoch, bytes32 playerKey) external view returns (uint256[] memory) {
        return _playerGames[epoch][playerKey];
    }

    function _record(uint256 gameId, bytes32 playerKey, uint256 points, bool anonymous) private {
        if (points == 0) revert GandaErrors.ZeroAmount();
        uint256 epoch = hub.currentEpoch();

        if (epochPlayerPoints[epoch][gameId][playerKey] == 0) {
            _playerGames[epoch][playerKey].push(gameId);
            epochGamePlayerCount[epoch][gameId] += 1;
        }
        epochPlayerPoints[epoch][gameId][playerKey] += points;
        epochGameTotalPoints[epoch][gameId] += points;

        if (!gameHasPoints[epoch][gameId]) {
            gameHasPoints[epoch][gameId] = true;
            epochGamesWithPoints[epoch] += 1;
        }
        emit ScoreSubmitted(epoch, gameId, playerKey, points, anonymous);
    }

    function _settlePlayerClaim(
        uint256 epoch,
        bytes32 playerKey,
        address payout
    ) private returns (uint256 amount) {
        if (payout == address(0)) revert GandaErrors.ZeroAddress();
        _checkClaimWindow(epoch);
        if (playerClaimed[epoch][playerKey]) revert GandaErrors.AlreadyClaimed();

        uint256 nota = notaOf(epoch, playerKey);
        if (nota == 0) revert GandaErrors.NothingToClaim();

        uint256 activeGames = epochGamesWithPoints[epoch] - epochBannedWithPoints[epoch];
        if (activeGames == 0) revert GandaErrors.NothingToClaim();

        uint256 playersPot = (epochPot[epoch] * (10_000 - gamesPotBps)) / 10_000;
        amount = (playersPot * nota) / (activeGames * SCALE);
        if (amount == 0) revert GandaErrors.NothingToClaim();

        playerClaimed[epoch][playerKey] = true;
        epochPotRemaining[epoch] -= amount;
        mona.safeTransfer(payout, amount);
    }

    function _erasePlayer(uint256 epoch, bytes32 playerKey) private {
        if (playerClaimed[epoch][playerKey]) revert GandaErrors.AlreadyClaimed();
        uint256[] storage gameIds = _playerGames[epoch][playerKey];
        if (gameIds.length == 0) revert GandaErrors.NothingToClaim();
        for (uint256 i = 0; i < gameIds.length; i++) {
            uint256 gameId = gameIds[i];
            uint256 points = epochPlayerPoints[epoch][gameId][playerKey];
            if (points == 0) continue;
            epochPlayerPoints[epoch][gameId][playerKey] = 0;
            epochGameTotalPoints[epoch][gameId] -= points;
            epochGamePlayerCount[epoch][gameId] -= 1;
        }
        delete _playerGames[epoch][playerKey];
        emit PlayerErased(epoch, playerKey);
    }

    function _checkClaimWindow(uint256 epoch) private view {
        uint256 current = hub.currentEpoch();
        if (current <= epoch) revert GandaErrors.EpochNotClosed();
        if (current > epoch + claimWindowEpochs) revert GandaErrors.ClaimWindowClosed();
    }

    function _verifyOwner(
        bytes calldata proof,
        bytes32 ownerTag,
        bytes32 bound,
        uint64 nonce
    ) private view {
        bytes32[] memory pubInputs = new bytes32[](3);
        pubInputs[0] = ownerTag;
        pubInputs[1] = bound;
        pubInputs[2] = bytes32(uint256(nonce));
        if (!ownerVerifier.verify(proof, pubInputs)) revert GandaErrors.BadProof();
    }
}
