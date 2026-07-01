// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IVerifier} from "./IVerifier.sol";

interface IIdentityRoots {
    function isKnownRoot(bytes32 root) external view returns (bool);
}

contract KitRegistry is ERC721 {
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

    IVerifier public immutable publishVerifier;
    IVerifier public immutable editVerifier;
    IIdentityRoots public immutable roots;

    uint256 public kitCount;
    mapping(uint256 => Kit) public kits;

    event KitPublished(uint256 indexed id, uint256 indexed parentId, Mode mode, bytes32 designHash, string contentUri);
    event KitVersioned(uint256 indexed id, bytes32 designHash, uint64 version, string contentUri);
    event KitRemoved(uint256 indexed id);

    error UnknownRoot();
    error BadProof();
    error NoKit();
    error NotOwner();
    error AlreadyRevoked();
    error BadNonce();
    error NoParent();
    error WrongMode();

    constructor(address publishVerifierAddress, address editVerifierAddress, address rootsAddress)
        ERC721("dx.computer Kit", "DXKIT")
    {
        publishVerifier = IVerifier(publishVerifierAddress);
        editVerifier = IVerifier(editVerifierAddress);
        roots = IIdentityRoots(rootsAddress);
    }

    function publishPublic(bytes32 designHash, string calldata contentUri) external returns (uint256 id) {
        id = _create(Mode.Public, bytes32(0), designHash, contentUri, 0);
        _mint(msg.sender, id);
    }

    function forkPublic(uint256 parentId, bytes32 designHash, string calldata contentUri)
        external
        returns (uint256 id)
    {
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

    function publish(bytes calldata proof, bytes32 root, bytes32 designHash, bytes32 ownerTag, string calldata contentUri)
        external
        returns (uint256 id)
    {
        id = _publishAnon(proof, root, designHash, ownerTag, contentUri, 0);
    }

    function fork(
        uint256 parentId,
        bytes calldata proof,
        bytes32 root,
        bytes32 designHash,
        bytes32 ownerTag,
        string calldata contentUri
    ) external returns (uint256 id) {
        if (!kits[parentId].exists) revert NoParent();
        id = _publishAnon(proof, root, designHash, ownerTag, contentUri, parentId);
    }

    function _publishAnon(
        bytes calldata proof,
        bytes32 root,
        bytes32 designHash,
        bytes32 ownerTag,
        string calldata contentUri,
        uint256 parentId
    ) internal returns (uint256 id) {
        if (!roots.isKnownRoot(root)) revert UnknownRoot();
        bytes32[] memory pubInputs = new bytes32[](3);
        pubInputs[0] = root;
        pubInputs[1] = designHash;
        pubInputs[2] = ownerTag;
        if (!publishVerifier.verify(proof, pubInputs)) revert BadProof();
        id = _create(Mode.Anonymous, ownerTag, designHash, contentUri, parentId);
    }

    function pushVersion(
        uint256 id,
        bytes calldata proof,
        bytes32 newDesignHash,
        uint64 nonce,
        string calldata newContentUri
    ) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Anonymous) revert WrongMode();
        if (nonce != k.version) revert BadNonce();
        _verifyOwner(proof, k.ownerTag, newDesignHash, nonce);
        k.designHash = newDesignHash;
        k.contentUri = newContentUri;
        k.version = nonce + 1;
        if (newDesignHash == bytes32(0)) k.revoked = true;
        emit KitVersioned(id, newDesignHash, k.version, newContentUri);
    }

    function remove(uint256 id, bytes calldata proof, uint64 nonce) external {
        Kit storage k = kits[id];
        if (!k.exists) revert NoKit();
        if (k.revoked) revert AlreadyRevoked();
        if (k.mode != Mode.Anonymous) revert WrongMode();
        if (nonce != k.version) revert BadNonce();
        _verifyOwner(proof, k.ownerTag, bytes32(0), nonce);
        k.designHash = bytes32(0);
        k.contentUri = "";
        k.revoked = true;
        k.version = nonce + 1;
        emit KitRemoved(id);
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
        id = kitCount;
        kitCount = id + 1;
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
        emit KitPublished(id, parentId, mode, designHash, contentUri);
    }
}
