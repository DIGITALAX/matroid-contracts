// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IdentityActionBase} from "./IdentityActionBase.sol";

contract KitSignal is IdentityActionBase {
    bytes4 public constant SIGNAL_TAG = bytes4(keccak256("kitSignal.signal"));

    mapping(uint256 => mapping(uint8 => uint256)) public tally;
    mapping(uint256 => mapping(bytes32 => uint8)) public reactionChoice;
    mapping(uint256 => mapping(bytes32 => uint256)) public reactionNonce;
    mapping(uint256 => mapping(address => uint8)) public publicChoice;

    event Signaled(uint256 indexed kitId, uint8 choice, bytes32 nullifier);
    event SignaledPublic(uint256 indexed kitId, uint8 choice, address indexed signaler);

    error BadNonce();
    error StaleSignal();
    error InvalidChoice();

    constructor(address verifierAddress, address rootsAddress)
        IdentityActionBase(verifierAddress, rootsAddress)
    {}

    function signal(
        bytes calldata proof,
        bytes32 merkleRoot,
        uint256 kitId,
        uint8 code,
        uint256 nonce,
        bytes32 nullifier
    ) external {
        if (code > 2) revert InvalidChoice();
        if (nonce == 0) revert BadNonce();

        bytes32 payloadHash = keccak256(abi.encode(code, nonce));
        _verifyAction(proof, SIGNAL_TAG, kitId, payloadHash, nullifier, merkleRoot);

        if (nonce <= reactionNonce[kitId][nullifier]) revert StaleSignal();
        reactionNonce[kitId][nullifier] = nonce;
        reactionChoice[kitId][nullifier] = _retally(kitId, reactionChoice[kitId][nullifier], code);
        emit Signaled(kitId, code, nullifier);
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
