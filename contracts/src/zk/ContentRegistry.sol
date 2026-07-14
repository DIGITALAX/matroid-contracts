// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {IdentityActionBase} from "./IdentityActionBase.sol";

interface IBlacklist {
    function isBanned(address who) external view returns (bool);
}

contract ContentRegistry is IdentityActionBase {
    struct Content {
        address author;
        bytes32 ownerTag;
        bytes32 canonicalTag;
        bytes32 moderatorTag;
        bytes32 contentHash;
        string contentUri;
        uint64 version;
        bool exists;
        bool revoked;
        bool moderated;
    }

    bytes4 public constant POST_TAG = bytes4(keccak256("contentRegistry.post"));
    bytes4 public constant EDIT_TAG = bytes4(keccak256("contentRegistry.edit"));

    IVerifier public immutable editVerifier;
    IBlacklist public immutable blacklist;

    uint256 public contentCount;
    mapping(uint256 => Content) public contents;

    event Posted(uint256 indexed id, address author, bytes32 ownerTag, bytes32 canonicalTag, bytes32 moderatorTag, bytes32 contentHash, string contentUri);
    event Updated(uint256 indexed id, bytes32 contentHash, uint64 version, bool revoked);
    event Moderated(uint256 indexed id, bytes32 canonicalTag);

    error NoContent();
    error AlreadyRevoked();
    error BadNonce();
    error NoCanonical();
    error NotAuthor();
    error Banned();

    constructor(
        address editVerifierAddress,
        address actionVerifierAddress,
        address registryAddress,
        address blacklistAddress
    ) IdentityActionBase(actionVerifierAddress, registryAddress) {
        editVerifier = IVerifier(editVerifierAddress);
        blacklist = IBlacklist(blacklistAddress);
    }

    function post(
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 contentHash,
        bytes32 ownerTag,
        bytes32 canonicalTag,
        bytes32 moderatorTag,
        string calldata contentUri
    ) external returns (uint256 id) {
        bytes32 payloadHash = keccak256(
            abi.encode(contentHash, ownerTag, canonicalTag, moderatorTag, keccak256(bytes(contentUri)))
        );
        _verifyAction(proof, POST_TAG, 0, payloadHash, nullifier, merkleRoot);

        id = contentCount;
        contentCount = id + 1;
        contents[id] = Content({
            author: address(0),
            ownerTag: ownerTag,
            canonicalTag: canonicalTag,
            moderatorTag: moderatorTag,
            contentHash: contentHash,
            contentUri: contentUri,
            version: 0,
            exists: true,
            revoked: false,
            moderated: false
        });
        emit Posted(id, address(0), ownerTag, canonicalTag, moderatorTag, contentHash, contentUri);
    }

    function postPublic(bytes32 contentHash, bytes32 canonicalTag, bytes32 moderatorTag, string calldata contentUri)
        external
        returns (uint256 id)
    {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        id = contentCount;
        contentCount = id + 1;
        contents[id] = Content({
            author: msg.sender,
            ownerTag: bytes32(0),
            canonicalTag: canonicalTag,
            moderatorTag: moderatorTag,
            contentHash: contentHash,
            contentUri: contentUri,
            version: 0,
            exists: true,
            revoked: false,
            moderated: false
        });
        emit Posted(id, msg.sender, bytes32(0), canonicalTag, moderatorTag, contentHash, contentUri);
    }

    function removePublic(uint256 id) external {
        Content storage c = contents[id];
        if (!c.exists) revert NoContent();
        if (c.revoked) revert AlreadyRevoked();
        if (c.author != msg.sender) revert NotAuthor();
        c.contentHash = bytes32(0);
        c.revoked = true;
        emit Updated(id, bytes32(0), c.version, true);
    }

    function update(
        uint256 id,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 newContentHash,
        uint64 nonce
    ) external {
        Content storage c = contents[id];
        if (!c.exists) revert NoContent();
        if (c.revoked) revert AlreadyRevoked();
        if (nonce != c.version) revert BadNonce();

        bytes32 payloadHash = keccak256(abi.encode(id, newContentHash, nonce));
        _verifyAction(actionProof, EDIT_TAG, uint256(payloadHash), payloadHash, nullifier, merkleRoot);

        bytes32[] memory pubInputs = new bytes32[](3);
        pubInputs[0] = c.ownerTag;
        pubInputs[1] = newContentHash;
        pubInputs[2] = bytes32(uint256(nonce));
        if (!editVerifier.verify(ownerProof, pubInputs)) revert BadProof();

        c.contentHash = newContentHash;
        c.version = nonce + 1;
        if (newContentHash == bytes32(0)) {
            c.revoked = true;
        }
        emit Updated(id, newContentHash, c.version, c.revoked);
    }

    function moderate(
        uint256 id,
        bytes calldata ownerProof,
        bytes calldata actionProof,
        bytes32 merkleRoot,
        bytes32 nullifier
    ) external {
        Content storage c = contents[id];
        if (!c.exists) revert NoContent();
        if (c.revoked) revert AlreadyRevoked();
        if (c.moderatorTag == bytes32(0)) revert NoCanonical();

        bytes32 payloadHash = keccak256(abi.encode(id));
        _verifyAction(actionProof, EDIT_TAG, uint256(payloadHash), payloadHash, nullifier, merkleRoot);

        bytes32[] memory pubInputs = new bytes32[](3);
        pubInputs[0] = c.moderatorTag;
        pubInputs[1] = bytes32(uint256(id));
        pubInputs[2] = bytes32(0);
        if (!editVerifier.verify(ownerProof, pubInputs)) revert BadProof();

        c.contentHash = bytes32(0);
        c.revoked = true;
        c.moderated = true;
        emit Moderated(id, c.canonicalTag);
        emit Updated(id, bytes32(0), c.version, true);
    }
}
