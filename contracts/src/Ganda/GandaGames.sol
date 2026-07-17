// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaLibrary.sol";
import "./GandaAccessControl.sol";
import "./GandaBlacklist.sol";
import {IVerifier} from "../zk/IVerifier.sol";
import {IdentityActionBase} from "../zk/IdentityActionBase.sol";

contract GandaGames is IdentityActionBase {
    bytes4 public constant PUBLISH_TAG = bytes4(keccak256("gandaGames.publish"));
    bytes4 public constant EDIT_TAG = bytes4(keccak256("gandaGames.edit"));
    uint256 private constant SNARK_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    IVerifier public immutable ownerVerifier;
    GandaAccessControl public immutable accessControl;
    GandaBlacklist public immutable blacklist;

    uint256 public gameCount;
    mapping(uint256 => GandaLibrary.Game) public games;

    event GamePublished(uint256 indexed gameId, bytes32 indexed ownerTag, address scorer, string uri);
    event GameVersioned(uint256 indexed gameId, address scorer, uint64 version, string uri);
    event GameRetagged(uint256 indexed gameId, bytes32 newOwnerTag);
    event GameErased(uint256 indexed gameId);
    event GameAdminEdited(uint256 indexed gameId, string uri);

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    constructor(
        address actionVerifierAddress,
        address rootsAddress,
        address ownerVerifierAddress,
        address accessControlAddress,
        address blacklistAddress
    ) IdentityActionBase(actionVerifierAddress, rootsAddress) {
        if (
            ownerVerifierAddress == address(0) ||
            accessControlAddress == address(0) ||
            blacklistAddress == address(0)
        ) revert GandaErrors.ZeroAddress();
        ownerVerifier = IVerifier(ownerVerifierAddress);
        accessControl = GandaAccessControl(accessControlAddress);
        blacklist = GandaBlacklist(blacklistAddress);
    }

    function publishGame(
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 ownerTag,
        address scorer,
        string calldata uri
    ) external returns (uint256 gameId) {
        if (scorer == address(0)) revert GandaErrors.ZeroAddress();
        if (blacklist.isTagBanned(ownerTag)) revert GandaErrors.TagBanned();
        bytes32 payloadHash = keccak256(
            abi.encode(ownerTag, scorer, keccak256(bytes(uri)))
        );
        _verifyAction(proof, PUBLISH_TAG, 0, payloadHash, nullifier, merkleRoot);

        gameId = ++gameCount;
        games[gameId] = GandaLibrary.Game({
            ownerTag: ownerTag,
            scorer: scorer,
            uri: uri,
            version: 0,
            publishedAt: uint64(block.timestamp),
            exists: true
        });
        emit GamePublished(gameId, ownerTag, scorer, uri);
    }

    function pushVersion(
        uint256 gameId,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        address newScorer,
        uint64 nonce,
        string calldata newUri
    ) external {
        if (newScorer == address(0)) revert GandaErrors.ZeroAddress();
        GandaLibrary.Game storage game = _liveGame(gameId);
        if (blacklist.isGameBanned(gameId)) revert GandaErrors.GameBanned();
        if (nonce != game.version) revert GandaErrors.BadNonce();
        bytes32 bound = keccak256(abi.encode(newScorer, keccak256(bytes(newUri))));
        _verifyEdit(
            actionProof,
            merkleRoot,
            nullifier,
            keccak256(abi.encode(gameId, newScorer, nonce, keccak256(bytes(newUri))))
        );
        _verifyOwner(ownerProof, game.ownerTag, bound, nonce);
        game.scorer = newScorer;
        game.uri = newUri;
        game.version = nonce + 1;
        emit GameVersioned(gameId, newScorer, game.version, newUri);
    }

    function retag(
        uint256 gameId,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 newOwnerTag,
        uint64 nonce
    ) external {
        if (blacklist.isTagBanned(newOwnerTag)) revert GandaErrors.TagBanned();
        GandaLibrary.Game storage game = _liveGame(gameId);
        if (blacklist.isGameBanned(gameId)) revert GandaErrors.GameBanned();
        if (nonce != game.version) revert GandaErrors.BadNonce();
        _verifyEdit(
            actionProof,
            merkleRoot,
            nullifier,
            keccak256(abi.encode(gameId, newOwnerTag, nonce))
        );
        _verifyOwner(ownerProof, game.ownerTag, newOwnerTag, nonce);
        game.ownerTag = newOwnerTag;
        game.version = nonce + 1;
        emit GameRetagged(gameId, newOwnerTag);
    }

    function eraseGame(
        uint256 gameId,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        uint64 nonce
    ) external {
        GandaLibrary.Game storage game = games[gameId];
        if (!game.exists) revert GandaErrors.NotFound();
        if (nonce != game.version) revert GandaErrors.BadNonce();
        _verifyEdit(
            actionProof,
            merkleRoot,
            nullifier,
            keccak256(abi.encode(gameId, "erase", nonce))
        );
        _verifyOwner(ownerProof, game.ownerTag, keccak256(abi.encode(gameId, "erase")), nonce);
        delete games[gameId];
        emit GameErased(gameId);
    }

    function adminEditGame(uint256 gameId, string calldata uri) external onlyAdmin {
        GandaLibrary.Game storage game = _liveGame(gameId);
        game.uri = uri;
        emit GameAdminEdited(gameId, uri);
    }

    function isActive(uint256 gameId) public view returns (bool) {
        GandaLibrary.Game storage game = games[gameId];
        return game.exists && !blacklist.isGameBanned(gameId);
    }

    function scorerOf(uint256 gameId) external view returns (address) {
        return games[gameId].scorer;
    }

    function ownerTagOf(uint256 gameId) external view returns (bytes32) {
        return games[gameId].ownerTag;
    }

    function getGame(uint256 gameId) external view returns (GandaLibrary.Game memory) {
        return games[gameId];
    }

    function _liveGame(uint256 gameId) private view returns (GandaLibrary.Game storage game) {
        game = games[gameId];
        if (!game.exists) revert GandaErrors.NotFound();
    }

    function _verifyEdit(
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 payloadHash
    ) private view {
        _verifyAction(actionProof, EDIT_TAG, uint256(payloadHash), payloadHash, nullifier, merkleRoot);
    }

    function _verifyOwner(
        bytes calldata proof,
        bytes32 ownerTag,
        bytes32 bound,
        uint64 nonce
    ) private view {
        bytes32[] memory pubInputs = new bytes32[](3);
        pubInputs[0] = ownerTag;
        pubInputs[1] = bytes32(uint256(bound) % SNARK_FIELD);
        pubInputs[2] = bytes32(uint256(nonce));
        if (!ownerVerifier.verify(proof, pubInputs)) revert GandaErrors.BadProof();
    }
}
