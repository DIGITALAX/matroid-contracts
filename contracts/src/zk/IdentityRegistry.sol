// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "@semaphore-protocol/contracts/interfaces/ISemaphoreGroups.sol";

contract IdentityRegistry {
    IVerifier public immutable enrollmentVerifier;
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;

    mapping(bytes32 => bool) public usedEnrollNullifier;

    event Enrolled(uint256 indexed identityCommitment, bytes32 enrollNullifier);

    error AlreadyEnrolled();
    error BadProof();

    constructor(address enrollmentVerifierAddress, address semaphoreAddress) {
        enrollmentVerifier = IVerifier(enrollmentVerifierAddress);
        semaphore = ISemaphore(semaphoreAddress);
        groupId = semaphore.createGroup(address(this));
    }

    function enroll(bytes calldata proof, uint256 identityCommitment, bytes32 enrollNullifier) external {
        if (usedEnrollNullifier[enrollNullifier]) revert AlreadyEnrolled();

        bytes32[] memory pubInputs = new bytes32[](2);
        pubInputs[0] = bytes32(identityCommitment);
        pubInputs[1] = enrollNullifier;
        if (!enrollmentVerifier.verify(proof, pubInputs)) revert BadProof();

        usedEnrollNullifier[enrollNullifier] = true;
        semaphore.addMember(groupId, identityCommitment);
        emit Enrolled(identityCommitment, enrollNullifier);
    }

    function currentRoot() external view returns (bytes32) {
        return bytes32(ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId));
    }

    function hasEnrolled(uint256 identityCommitment) external view returns (bool) {
        return ISemaphoreGroups(address(semaphore)).hasMember(groupId, identityCommitment);
    }

    function enrollmentCount() external view returns (uint256) {
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeSize(groupId);
    }

    function isKnownRoot(bytes32 root) external view returns (bool) {
        return uint256(root) == ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId);
    }
}
