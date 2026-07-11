// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

contract KitSignal {
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;

    mapping(uint256 => mapping(uint8 => uint256)) public tally;
    mapping(uint256 => mapping(uint256 => uint8)) public reactionChoice;
    mapping(uint256 => mapping(uint256 => uint256)) public reactionNonce;
    mapping(uint256 => mapping(address => uint8)) public publicChoice;

    event Signaled(uint256 indexed kitId, uint8 choice, uint256 nullifier);
    event SignaledPublic(uint256 indexed kitId, uint8 choice, address indexed signaler);

    error BadScope();
    error BadNonce();
    error StaleSignal();
    error InvalidChoice();
    error BadProof();

    constructor(address semaphoreAddress, uint256 groupId_) {
        semaphore = ISemaphore(semaphoreAddress);
        groupId = groupId_;
    }

    function signal(ISemaphore.SemaphoreProof calldata proof, uint256 kitId) external {
        if (proof.scope != kitId) revert BadScope();
        uint8 code = uint8(proof.message & 3);
        uint256 nonce = proof.message >> 2;
        if (code > 2) revert InvalidChoice();
        if (nonce == 0) revert BadNonce();
        if (!semaphore.verifyProof(groupId, proof)) revert BadProof();

        uint256 nul = proof.nullifier;
        if (nonce <= reactionNonce[kitId][nul]) revert StaleSignal();
        reactionNonce[kitId][nul] = nonce;

        reactionChoice[kitId][nul] = _retally(kitId, reactionChoice[kitId][nul], code);
        emit Signaled(kitId, code, nul);
    }

    function signalPublic(uint256 kitId, uint8 code) external {
        if (code > 2) revert InvalidChoice();
        publicChoice[kitId][msg.sender] = _retally(kitId, publicChoice[kitId][msg.sender], code);
        emit SignaledPublic(kitId, code, msg.sender);
    }

    /// Adjust the +/- tally for a reactor whose previous stored value is `prev`
    /// (0 = none, else choice+1) toward `code` (0 = down, 1 = up, 2 = retract),
    /// and return the new stored value.
    function _retally(uint256 kitId, uint8 prev, uint8 code) private returns (uint8) {
        if (code == 2) {
            if (prev != 0) tally[kitId][prev - 1] -= 1;
            return 0;
        }
        if (prev == 0) {
            tally[kitId][code] += 1;
        } else if (prev - 1 != code) {
            tally[kitId][prev - 1] -= 1;
            tally[kitId][code] += 1;
        }
        return code + 1;
    }
}
