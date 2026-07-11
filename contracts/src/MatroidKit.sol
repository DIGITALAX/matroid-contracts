// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {MatroidRegistry} from "./MatroidRegistry.sol";
import {IVerifier} from "./zk/IVerifier.sol";
import "./MatroidErrors.sol";

interface IIdentityRoots {
    function isKnownRoot(bytes32 root) external view returns (bool);
}

contract MatroidKit {
    MatroidRegistry public immutable registry;
    address public owner;
    IVerifier public activityVerifier;
    IIdentityRoots public identityRoots;

    mapping(address => mapping(uint256 => mapping(bytes32 => bool)))
        public usedActivityNullifier;

    event ProjectRegistered(address indexed project, string metadata);
    event MatroidIn(
        address indexed project,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event MatroidOut(
        address indexed project,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event ChipActivity(address indexed project, bytes32 nullifier);
    event VerificationSet(address verifier, address roots);

    constructor(address registryAddress) {
        if (registryAddress == address(0)) revert MatroidErrors.ZeroAddress();
        registry = MatroidRegistry(registryAddress);
        owner = msg.sender;
    }

    function setVerification(address verifier, address roots) external {
        if (msg.sender != owner) revert MatroidErrors.NotOwner();
        if (address(activityVerifier) != address(0)) revert MatroidErrors.AlreadySet();
        if (verifier == address(0) || roots == address(0)) revert MatroidErrors.ZeroAddress();
        activityVerifier = IVerifier(verifier);
        identityRoots = IIdentityRoots(roots);
        emit VerificationSet(verifier, roots);
    }

    function registerProject(string calldata metadata, bool pool) external {
        registry.registerProject(msg.sender, metadata, pool);
        emit ProjectRegistered(msg.sender, metadata);
    }

    function matroidIn(address user, address token, uint256 amount) external {
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        registry.recordFlow(msg.sender, user, token, amount, true);
        emit MatroidIn(msg.sender, user, token, amount);
    }

    function matroidOut(address user, address token, uint256 amount) external {
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        registry.recordFlow(msg.sender, user, token, amount, false);
        emit MatroidOut(msg.sender, user, token, amount);
    }

    function matroidInVerified(
        address user,
        address token,
        uint256 amount,
        bytes32 merkleRoot,
        bytes calldata proof,
        bytes32 nullifier
    ) external {
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        _verifyChip(merkleRoot, proof, nullifier);
        registry.recordFlow(msg.sender, user, token, amount, true);
        registry.creditChipWeight(msg.sender);
        emit MatroidIn(msg.sender, user, token, amount);
        emit ChipActivity(msg.sender, nullifier);
    }

    function matroidOutVerified(
        address user,
        address token,
        uint256 amount,
        bytes32 merkleRoot,
        bytes calldata proof,
        bytes32 nullifier
    ) external {
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        _verifyChip(merkleRoot, proof, nullifier);
        registry.recordFlow(msg.sender, user, token, amount, false);
        registry.creditChipWeight(msg.sender);
        emit MatroidOut(msg.sender, user, token, amount);
        emit ChipActivity(msg.sender, nullifier);
    }

    function _verifyChip(bytes32 merkleRoot, bytes calldata proof, bytes32 nullifier) internal {
        if (address(activityVerifier) == address(0)) revert MatroidErrors.ZeroAddress();
        if (!identityRoots.isKnownRoot(merkleRoot)) revert MatroidErrors.UnknownRoot();
        uint256 epoch = registry.currentEpoch();
        if (usedActivityNullifier[msg.sender][epoch][nullifier]) revert MatroidErrors.NullifierUsed();
        usedActivityNullifier[msg.sender][epoch][nullifier] = true;

        bytes32[] memory pubInputs = new bytes32[](4);
        pubInputs[0] = merkleRoot;
        pubInputs[1] = bytes32(uint256(uint160(msg.sender)));
        pubInputs[2] = bytes32(epoch);
        pubInputs[3] = nullifier;
        if (!activityVerifier.verify(proof, pubInputs)) revert MatroidErrors.BadProof();
    }
}
