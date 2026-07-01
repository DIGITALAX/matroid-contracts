// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IPoseidon} from "./IPoseidon.sol";
import {ISnapshotRegistry} from "./ISnapshotRegistry.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}

contract MonaBalanceTree is ISnapshotRegistry {
    uint256 public constant DEPTH = 20;
    uint256 public constant ROOT_HISTORY = 30;
    uint256 public constant MAX_BALANCE = type(uint128).max;
    uint256 public constant BALANCE_LINK_SCOPE = uint256(keccak256("matroid.balance-link"));

    IPoseidon public immutable hasher;
    IERC20Balance public immutable mona;
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;

    bytes32[DEPTH] public zeros;
    bytes32[DEPTH] public filledSubtrees;
    bytes32[ROOT_HISTORY] public roots;
    uint32 public currentRootIndex;
    uint32 public nextLeafIndex;

    event Registered(uint256 indexed balanceKey, uint256 balance, uint32 leafIndex, bytes32 root);

    error NotAHolder();
    error BalanceTooLarge();
    error TreeFull();
    error BadScope();
    error BadProof();

    constructor(address hasherAddress, address monaAddress, address semaphoreAddress, uint256 groupId_) {
        hasher = IPoseidon(hasherAddress);
        mona = IERC20Balance(monaAddress);
        semaphore = ISemaphore(semaphoreAddress);
        groupId = groupId_;

        bytes32 zero = bytes32(0);
        for (uint256 i = 0; i < DEPTH; i++) {
            zeros[i] = zero;
            filledSubtrees[i] = zero;
            zero = hasher.poseidon([zero, zero]);
        }
        roots[0] = zero;
    }

    function register(ISemaphore.SemaphoreProof calldata linkProof) external returns (bytes32) {
        if (linkProof.scope != BALANCE_LINK_SCOPE) revert BadScope();
        if (!semaphore.verifyProof(groupId, linkProof)) revert BadProof();

        uint256 bal = mona.balanceOf(msg.sender);
        if (bal == 0) revert NotAHolder();
        if (bal > MAX_BALANCE) revert BalanceTooLarge();

        bytes32 leaf = hasher.poseidon([bytes32(linkProof.nullifier), bytes32(bal)]);
        uint32 leafIndex = nextLeafIndex;
        bytes32 root = _insert(leaf);
        emit Registered(linkProof.nullifier, bal, leafIndex, root);
        return root;
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

    function isKnownBalanceRoot(bytes32 root) external view returns (bool) {
        if (root == bytes32(0)) return false;
        for (uint256 i = 0; i < ROOT_HISTORY; i++) {
            if (roots[i] == root) return true;
        }
        return false;
    }
}
