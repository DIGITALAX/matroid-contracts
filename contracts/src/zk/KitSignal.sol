// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";

interface IIdentityRoots {
    function isKnownRoot(bytes32 root) external view returns (bool);
}

contract KitSignal {
    IVerifier public immutable signalVerifier;
    IIdentityRoots public immutable roots;

    mapping(uint256 => mapping(bytes32 => bool)) public usedNullifier;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event Signaled(uint256 indexed kitId, uint8 choice, bytes32 nullifier);

    error UnknownRoot();
    error BadProof();
    error AlreadySignaled();
    error InvalidChoice();

    constructor(address signalVerifierAddress, address rootsAddress) {
        signalVerifier = IVerifier(signalVerifierAddress);
        roots = IIdentityRoots(rootsAddress);
    }

    function signal(
        uint256 kitId,
        uint8 choice,
        bytes calldata proof,
        bytes32 root,
        bytes32 nullifier
    ) external {
        if (choice > 1) revert InvalidChoice();
        if (!roots.isKnownRoot(root)) revert UnknownRoot();
        if (usedNullifier[kitId][nullifier]) revert AlreadySignaled();

        bytes32[] memory pubInputs = new bytes32[](4);
        pubInputs[0] = root;
        pubInputs[1] = bytes32(kitId);
        pubInputs[2] = bytes32(uint256(choice));
        pubInputs[3] = nullifier;
        if (!signalVerifier.verify(proof, pubInputs)) revert BadProof();

        usedNullifier[kitId][nullifier] = true;
        tally[kitId][choice] += 1;
        emit Signaled(kitId, choice, nullifier);
    }
}
