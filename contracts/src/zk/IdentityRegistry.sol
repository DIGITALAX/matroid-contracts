// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {IPoseidon} from "./IPoseidon.sol";

contract IdentityRegistry {
    uint256 public constant DEPTH = 20;
    uint256 public constant ROOT_HISTORY = 30;

    IVerifier public immutable enrollmentVerifier;
    IPoseidon public immutable hasher;

    bytes32[DEPTH] public zeros;
    bytes32[DEPTH] public filledSubtrees;
    bytes32[ROOT_HISTORY] public roots;
    uint32 public currentRootIndex;
    uint32 public nextLeafIndex;

    mapping(bytes32 => bool) public usedEnrollNullifier;
    mapping(bytes32 => bool) public commitments;

    event Enrolled(bytes32 indexed commitment, uint32 leafIndex, bytes32 root);

    error AlreadyEnrolled();
    error BadProof();
    error TreeFull();
    error CommitmentExists();

    constructor(address enrollmentVerifierAddress, address hasherAddress) {
        enrollmentVerifier = IVerifier(enrollmentVerifierAddress);
        hasher = IPoseidon(hasherAddress);

        bytes32 zero = bytes32(0);
        for (uint256 i = 0; i < DEPTH; i++) {
            zeros[i] = zero;
            filledSubtrees[i] = zero;
            zero = hasher.poseidon([zero, zero]);
        }
        roots[0] = zero;
    }

    function enroll(bytes calldata proof, bytes32 commitment, bytes32 enrollNullifier) external {
        if (usedEnrollNullifier[enrollNullifier]) revert AlreadyEnrolled();
        if (commitments[commitment]) revert CommitmentExists();

        bytes32[] memory pubInputs = new bytes32[](2);
        pubInputs[0] = commitment;
        pubInputs[1] = enrollNullifier;
        if (!enrollmentVerifier.verify(proof, pubInputs)) revert BadProof();

        usedEnrollNullifier[enrollNullifier] = true;
        commitments[commitment] = true;
        uint32 leafIndex = nextLeafIndex;
        bytes32 root = _insert(commitment);
        emit Enrolled(commitment, leafIndex, root);
    }

    function _insert(bytes32 leaf) internal returns (bytes32) {
        uint32 idx = nextLeafIndex;
        if (uint256(idx) >= (uint256(1) << DEPTH)) revert TreeFull();

        bytes32 current = leaf;
        uint32 cursor = idx;
        for (uint256 i = 0; i < DEPTH; i++) {
            bytes32 left;
            bytes32 right;
            if (cursor % 2 == 0) {
                left = current;
                right = zeros[i];
                filledSubtrees[i] = current;
            } else {
                left = filledSubtrees[i];
                right = current;
            }
            current = hasher.poseidon([left, right]);
            cursor /= 2;
        }

        currentRootIndex = (currentRootIndex + 1) % uint32(ROOT_HISTORY);
        roots[currentRootIndex] = current;
        nextLeafIndex = idx + 1;
        return current;
    }

    function currentRoot() external view returns (bytes32) {
        return roots[currentRootIndex];
    }

    function isKnownRoot(bytes32 root) external view returns (bool) {
        if (root == bytes32(0)) return false;
        for (uint256 i = 0; i < ROOT_HISTORY; i++) {
            if (roots[i] == root) return true;
        }
        return false;
    }
}
