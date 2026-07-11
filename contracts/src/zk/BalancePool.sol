// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IPoseidon} from "./IPoseidon.sol";
import {IBalancePool} from "./IBalancePool.sol";

interface IERC20Pool {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract BalancePool is IBalancePool {
    uint256 public constant DEPTH = 20;
    uint8 public constant BUCKETS = 9;

    IPoseidon public immutable hasher;
    IERC20Pool public immutable mona;
    address public immutable deployer;

    uint256[BUCKETS] public denominations;
    uint8 public activeBucket;

    mapping(uint8 => bytes32) public roots;
    mapping(uint8 => uint32) public nextLeafIndex;

    struct DepositRecord {
        address depositor;
        bytes32 commitment;
        bool withdrawn;
    }

    mapping(uint8 => mapping(uint32 => DepositRecord)) public deposits;

    mapping(address => bool) public governance;
    bool public governanceLocked;

    event Deposited(uint8 indexed bucket, bytes32 commitment, uint32 leafIndex, bytes32 root);
    event Withdrawn(uint8 indexed bucket, uint32 leafIndex, bytes32 root);
    event ActiveBucketChanged(uint8 bucket);

    error BadBucket();
    error TreeFull();
    error StalePath();
    error NotDepositor();
    error AlreadyWithdrawn();
    error TransferFailed();
    error NotGovernance();
    error Locked();
    error ZeroCommitment();

    constructor(address hasherAddress, address monaAddress, uint8 initialBucket) {
        if (initialBucket >= BUCKETS) revert BadBucket();
        hasher = IPoseidon(hasherAddress);
        mona = IERC20Pool(monaAddress);
        deployer = msg.sender;
        activeBucket = initialBucket;

        denominations[0] = 0.01 ether;
        denominations[1] = 0.1 ether;
        denominations[2] = 0.25 ether;
        denominations[3] = 0.5 ether;
        denominations[4] = 0.75 ether;
        denominations[5] = 1 ether;
        denominations[6] = 5 ether;
        denominations[7] = 7 ether;
        denominations[8] = 10 ether;

        bytes32 zero = bytes32(0);
        for (uint256 i = 0; i < DEPTH; i++) {
            zero = hasher.poseidon([zero, zero]);
        }
        for (uint8 b = 0; b < BUCKETS; b++) {
            roots[b] = zero;
        }
    }

    function setGovernance(address[] calldata councils) external {
        if (msg.sender != deployer) revert NotGovernance();
        if (governanceLocked) revert Locked();
        governanceLocked = true;
        for (uint256 i = 0; i < councils.length; i++) {
            governance[councils[i]] = true;
        }
    }

    function setActiveBucket(uint8 bucket) external {
        if (!governance[msg.sender]) revert NotGovernance();
        if (bucket >= BUCKETS) revert BadBucket();
        activeBucket = bucket;
        emit ActiveBucketChanged(bucket);
    }

    function deposit(uint8 bucket, bytes32 commitment, bytes32[20] calldata siblings) external returns (bytes32) {
        if (bucket >= BUCKETS) revert BadBucket();
        if (commitment == bytes32(0)) revert ZeroCommitment();
        uint32 index = nextLeafIndex[bucket];
        if (uint256(index) >= (uint256(1) << DEPTH)) revert TreeFull();

        if (!mona.transferFrom(msg.sender, address(this), denominations[bucket])) revert TransferFailed();

        bytes32 root = _update(bucket, index, bytes32(0), commitment, siblings);
        deposits[bucket][index] = DepositRecord(msg.sender, commitment, false);
        nextLeafIndex[bucket] = index + 1;
        emit Deposited(bucket, commitment, index, root);
        return root;
    }

    function withdraw(uint8 bucket, uint32 index, bytes32[20] calldata siblings) external returns (bytes32) {
        if (bucket >= BUCKETS) revert BadBucket();
        DepositRecord storage d = deposits[bucket][index];
        if (d.depositor != msg.sender) revert NotDepositor();
        if (d.withdrawn) revert AlreadyWithdrawn();

        d.withdrawn = true;
        bytes32 root = _update(bucket, index, d.commitment, bytes32(0), siblings);
        if (!mona.transfer(msg.sender, denominations[bucket])) revert TransferFailed();
        emit Withdrawn(bucket, index, root);
        return root;
    }

    function _update(
        uint8 bucket,
        uint32 index,
        bytes32 oldLeaf,
        bytes32 newLeaf,
        bytes32[20] calldata siblings
    ) internal returns (bytes32) {
        bytes32 oldNode = oldLeaf;
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
        if (oldNode != roots[bucket]) revert StalePath();
        roots[bucket] = newNode;
        return newNode;
    }

    function bucketCount() external pure returns (uint8) {
        return BUCKETS;
    }

    function denomination(uint8 bucket) external view returns (uint256) {
        if (bucket >= BUCKETS) revert BadBucket();
        return denominations[bucket];
    }

    function currentRoot(uint8 bucket) external view returns (bytes32) {
        if (bucket >= BUCKETS) revert BadBucket();
        return roots[bucket];
    }
}
