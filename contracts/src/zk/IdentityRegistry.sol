// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {IPoseidon} from "./IPoseidon.sol";

contract IdentityRegistry {
    uint256 public constant DEPTH = 20;

    IVerifier public immutable enrollmentVerifier;
    IPoseidon public immutable hasher;

    bytes32 public root;
    uint32 public nextLeafIndex;

    mapping(bytes32 => bool) public usedEnrollNullifier;
    mapping(uint256 => bool) public enrolledCommitment;
    mapping(bytes32 => bool) public knownRoot;

    event Enrolled(uint256 indexed commitment, bytes32 enrollNullifier, uint32 leafIndex, bytes32 root);

    error AlreadyEnrolled();
    error CommitmentExists();
    error BadProof();
    error TreeFull();
    error StalePath();
    error ZeroCommitment();

    constructor(address enrollmentVerifierAddress, address hasherAddress) {
        enrollmentVerifier = IVerifier(enrollmentVerifierAddress);
        hasher = IPoseidon(hasherAddress);
        bytes32 node = bytes32(0);
        for (uint256 i = 0; i < DEPTH; i++) {
            node = hasher.poseidon([node, bytes32(0)]);
        }
        root = node;
        knownRoot[node] = true;
    }

    function enroll(
        bytes calldata proof,
        bytes32 freshBind,
        bytes32 enrollNullifier,
        uint256 commitment,
        bytes32[20] calldata siblings
    ) external returns (bytes32) {
        if (commitment == 0) revert ZeroCommitment();
        if (usedEnrollNullifier[enrollNullifier]) revert AlreadyEnrolled();
        if (enrolledCommitment[commitment]) revert CommitmentExists();

        bytes32[] memory pub = new bytes32[](3);
        pub[0] = freshBind;
        pub[1] = enrollNullifier;
        pub[2] = bytes32(commitment);
        if (!enrollmentVerifier.verify(proof, pub)) revert BadProof();

        uint32 index = nextLeafIndex;
        if (uint256(index) >= (uint256(1) << DEPTH)) revert TreeFull();
        bytes32 newRoot = _update(index, bytes32(commitment), siblings);

        usedEnrollNullifier[enrollNullifier] = true;
        enrolledCommitment[commitment] = true;
        nextLeafIndex = index + 1;
        root = newRoot;
        knownRoot[newRoot] = true;
        emit Enrolled(commitment, enrollNullifier, index, newRoot);
        return newRoot;
    }

    function _update(uint32 index, bytes32 newLeaf, bytes32[20] calldata siblings)
        internal
        view
        returns (bytes32)
    {
        bytes32 oldNode = bytes32(0);
        bytes32 newNode = newLeaf;
        uint32 cursor = index;
        for (uint256 i = 0; i < DEPTH; i++) {
            bytes32 s = siblings[i];
            if (cursor % 2 == 0) {
                oldNode = hasher.poseidon([oldNode, s]);
                newNode = hasher.poseidon([newNode, s]);
            } else {
                oldNode = hasher.poseidon([s, oldNode]);
                newNode = hasher.poseidon([s, newNode]);
            }
            cursor /= 2;
        }
        if (oldNode != root) revert StalePath();
        return newNode;
    }

    function isKnownRoot(bytes32 candidate) external view returns (bool) {
        return knownRoot[candidate];
    }

    function currentRoot() external view returns (bytes32) {
        return root;
    }

    function enrollmentCount() external view returns (uint32) {
        return nextLeafIndex;
    }
}
