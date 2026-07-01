// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

contract KitSignal {
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;

    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event Signaled(uint256 indexed kitId, uint8 choice, uint256 nullifier);

    error BadScope();
    error InvalidChoice();

    constructor(address semaphoreAddress, uint256 groupId_) {
        semaphore = ISemaphore(semaphoreAddress);
        groupId = groupId_;
    }

    function signal(ISemaphore.SemaphoreProof calldata proof, uint256 kitId) external {
        if (proof.scope != kitId) revert BadScope();
        uint8 choice = uint8(proof.message);
        if (choice > 1) revert InvalidChoice();

        semaphore.validateProof(groupId, proof);

        tally[kitId][choice] += 1;
        emit Signaled(kitId, choice, proof.nullifier);
    }
}
