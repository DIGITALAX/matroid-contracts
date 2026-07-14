// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IVerifier} from "./IVerifier.sol";
import {IdentityActionBase} from "./IdentityActionBase.sol";

interface IBlacklist {
    function isBanned(address who) external view returns (bool);
}

contract KitRegistry is ERC721, IdentityActionBase {
    enum Mode {
        Public,
        Anonymous
    }

    struct Kit {
        bytes32 ownerTag;
        bytes32 designHash;
        string contentUri;
        uint256 parentId;
        uint64 version;
        bool exists;
        bool revoked;
        Mode mode;
    }

    bytes4 public constant PUBLISH_TAG = bytes4(keccak256("kitRegistry.publish"));
    bytes4 public constant EDIT_TAG = bytes4(keccak256("kitRegistry.edit"));

    IVerifier public immutable editVerifier;
    IBlacklist public immutable blacklist;

    uint256 public kitCount;
    mapping(uint256 => Kit) public kits;

    event KitPublished(uint256 indexed id, uint256 indexed parentId, Mode mode, bytes32 designHash, bytes32 ownerTag, string contentUri);
    event KitVersioned(uint256 indexed id, bytes32 designHash, uint64 version, string contentUri);
    event KitRemoved(uint256 indexed id);
    event KitRetagged(uint256 indexed id, bytes32 newOwnerTag);
    event KitClaimed(uint256 indexed id, address indexed owner);

    error NoKit();
    error NotOwner();
    error AlreadyRevoked();
    error BadNonce();
    error NoParent();
    error WrongMode();
    error Banned();

    constructor(
        address editVerifierAddress,
        address actionVerifierAddress,
        address registryAddress,
        address blacklistAddress
    ) ERC721("dx.computer Kit", "DXKIT") IdentityActionBase(actionVerifierAddress, registryAddress) {
        editVerifier = IVerifier(editVerifierAddress);
        blacklist = IBlacklist(blacklistAddress);
    }

    function publishPublic(bytes32 designHash, string calldata contentUri) external returns (uint256 id) {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        id = _create(Mode.Public, bytes32(0), designHash, contentUri, 0);
        _mint(msg.sender, id);
    }

    function forkPublic(uint256 parentId, bytes32 designHash, string calldata contentUri)
        external
        returns (uint256 id)
    {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        if (!kits[parentId].exists) revert NoParent();
        id = _create(Mode.Public, bytes32(0), designHash, contentUri, parentId);
        _mint(msg.sender, id);
    }

    function pushVersionPublic(uint256 id, bytes32 newDesignHash, string calldata newContentUri) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Public) revert WrongMode();
        if (ownerOf(id) != msg.sender) revert NotOwner();
        k.designHash = newDesignHash;
        k.contentUri = newContentUri;
        k.version += 1;
        emit KitVersioned(id, newDesignHash, k.version, newContentUri);
    }

    function removePublic(uint256 id) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Public) revert WrongMode();
        if (ownerOf(id) != msg.sender) revert NotOwner();
        k.designHash = bytes32(0);
        k.contentUri = "";
        k.revoked = true;
        _burn(id);
        emit KitRemoved(id);
    }

    function publish(
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 designHash,
        bytes32 ownerTag,
        string calldata contentUri
    ) external returns (uint256 id) {
        id = _publishAnon(proof, merkleRoot, nullifier, designHash, ownerTag, contentUri, 0);
    }

    function fork(
        uint256 parentId,
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 designHash,
        bytes32 ownerTag,
        string calldata contentUri
    ) external returns (uint256 id) {
        if (!kits[parentId].exists) revert NoParent();
        id = _publishAnon(proof, merkleRoot, nullifier, designHash, ownerTag, contentUri, parentId);
    }

    function _publishAnon(
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 designHash,
        bytes32 ownerTag,
        string calldata contentUri,
        uint256 parentId
    ) internal returns (uint256 id) {
        bytes32 payloadHash = keccak256(
            abi.encode(designHash, ownerTag, keccak256(bytes(contentUri)), parentId)
        );
        _verifyAction(proof, PUBLISH_TAG, 0, payloadHash, nullifier, merkleRoot);
        id = _create(Mode.Anonymous, ownerTag, designHash, contentUri, parentId);
    }

    function pushVersion(
        uint256 id,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 newDesignHash,
        uint64 nonce,
        string calldata newContentUri
    ) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Anonymous) revert WrongMode();
        if (nonce != k.version) revert BadNonce();
        _verifyEdit(
            actionProof,
            merkleRoot,
            nullifier,
            keccak256(abi.encode(id, newDesignHash, nonce, keccak256(bytes(newContentUri))))
        );
        _verifyOwner(ownerProof, k.ownerTag, newDesignHash, nonce);
        k.designHash = newDesignHash;
        k.contentUri = newContentUri;
        k.version = nonce + 1;
        if (newDesignHash == bytes32(0)) k.revoked = true;
        emit KitVersioned(id, newDesignHash, k.version, newContentUri);
    }

    function remove(
        uint256 id,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        uint64 nonce
    ) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Anonymous) revert WrongMode();
        if (nonce != k.version) revert BadNonce();
        _verifyEdit(actionProof, merkleRoot, nullifier, keccak256(abi.encode(id, nonce)));
        _verifyOwner(ownerProof, k.ownerTag, bytes32(0), nonce);
        k.designHash = bytes32(0);
        k.contentUri = "";
        k.revoked = true;
        k.version = nonce + 1;
        emit KitRemoved(id);
    }

    function retag(
        uint256 id,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 newOwnerTag,
        uint64 nonce
    ) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Anonymous) revert WrongMode();
        if (nonce != k.version) revert BadNonce();
        _verifyEdit(actionProof, merkleRoot, nullifier, keccak256(abi.encode(id, newOwnerTag, nonce)));
        _verifyOwner(ownerProof, k.ownerTag, newOwnerTag, nonce);
        k.ownerTag = newOwnerTag;
        emit KitRetagged(id, newOwnerTag);
    }

    function claim(
        uint256 id,
        address to,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        uint64 nonce
    ) external {
        if (blacklist.isBanned(to)) revert Banned();
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Anonymous) revert WrongMode();
        if (nonce != k.version) revert BadNonce();
        _verifyEdit(actionProof, merkleRoot, nullifier, keccak256(abi.encode(id, to, nonce)));
        _verifyOwner(ownerProof, k.ownerTag, bytes32(uint256(uint160(to))), nonce);
        k.mode = Mode.Public;
        k.ownerTag = bytes32(0);
        k.version = nonce + 1;
        _mint(to, id);
        emit KitClaimed(id, to);
    }

    function _verifyEdit(
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 payloadHash
    ) internal view {
        _verifyAction(actionProof, EDIT_TAG, uint256(payloadHash), payloadHash, nullifier, merkleRoot);
    }

    function _verifyOwner(bytes calldata proof, bytes32 ownerTag, bytes32 newDesignHash, uint64 nonce) internal view {
        bytes32[] memory pubInputs = new bytes32[](3);
        pubInputs[0] = ownerTag;
        pubInputs[1] = newDesignHash;
        pubInputs[2] = bytes32(uint256(nonce));
        if (!editVerifier.verify(proof, pubInputs)) revert BadProof();
    }

    function _create(Mode mode, bytes32 ownerTag, bytes32 designHash, string calldata contentUri, uint256 parentId)
        internal
        returns (uint256 id)
    {
        id = kitCount + 1;
        kitCount = id;
        kits[id] = Kit({
            ownerTag: ownerTag,
            designHash: designHash,
            contentUri: contentUri,
            parentId: parentId,
            version: 0,
            exists: true,
            revoked: false,
            mode: mode
        });
        emit KitPublished(id, parentId, mode, designHash, ownerTag, contentUri);
    }
}
