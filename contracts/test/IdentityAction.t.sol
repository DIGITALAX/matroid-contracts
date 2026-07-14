// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IdentityAction} from "../src/zk/IdentityAction.sol";
import {IdentityActionBase, IIdentityActionRoots} from "../src/zk/IdentityActionBase.sol";
import {IVerifier} from "../src/zk/IVerifier.sol";
import {IdentityActionVerifier} from "../src/zk/verifiers/IdentityActionVerifier.sol";

contract MockRoots is IIdentityActionRoots {
    mapping(bytes32 => bool) public known;

    function setKnown(bytes32 root, bool ok) external {
        known[root] = ok;
    }

    function isKnownRoot(bytes32 root) external view returns (bool) {
        return known[root];
    }
}

contract MockVerifier is IVerifier {
    bool public result;

    constructor(bool r) {
        result = r;
    }

    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return result;
    }
}

contract IdentityActionTest is Test {
    bytes proof;
    bytes32[] pub;

    function setUp() public {
        proof = vm.readFileBinary("test/fixtures/identity_action.proof");
        bytes memory piBytes = vm.readFileBinary("test/fixtures/identity_action.public_inputs");
        uint256 n = piBytes.length / 32;
        pub = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            bytes32 word;
            assembly {
                word := mload(add(add(piBytes, 32), mul(i, 32)))
            }
            pub[i] = word;
        }
    }

    function test_public_inputs_are_five() public view {
        assertEq(pub.length, 5);
    }

    function test_verifier_accepts_real_proof() public {
        IdentityActionVerifier v = new IdentityActionVerifier();
        assertTrue(v.verify(proof, pub));
    }

    function test_verifier_rejects_tampered_nullifier() public {
        IdentityActionVerifier v = new IdentityActionVerifier();
        bytes32[] memory bad = pub;
        bad[4] = bytes32(uint256(bad[4]) ^ 1);
        vm.expectRevert();
        v.verify(proof, bad);
    }

    function test_digest_packing_matches_circuit() public view {
        bytes32 actionDigest = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
        bytes32 hi = bytes32(uint256(uint128(bytes16(actionDigest))));
        bytes32 lo = bytes32(uint256(uint128(uint256(actionDigest))));
        assertEq(hi, pub[0]);
        assertEq(lo, pub[1]);
    }

    function _consumer(bool verifierResult) internal returns (IdentityAction ia, MockRoots roots, bytes32 root) {
        roots = new MockRoots();
        MockVerifier mv = new MockVerifier(verifierResult);
        ia = new IdentityAction(address(mv), address(roots));
        root = keccak256("root-v2");
        roots.setKnown(root, true);
    }

    function test_consumer_happy_path_and_replay() public {
        (IdentityAction ia,, bytes32 root) = _consumer(true);
        bytes4 tag = bytes4(keccak256("vote"));
        bytes32 nul = keccak256("nullifier-a");
        ia.act(proof, root, tag, 7, keccak256("choice-yes"), nul);
        vm.expectRevert(IdentityAction.NullifierUsed.selector);
        ia.act(proof, root, tag, 7, keccak256("choice-yes"), nul);
    }

    function test_consumer_rejects_unknown_root() public {
        (IdentityAction ia,,) = _consumer(true);
        vm.expectRevert(IdentityActionBase.UnknownRoot.selector);
        ia.act(proof, keccak256("unknown"), bytes4(keccak256("vote")), 7, bytes32(0), keccak256("n"));
    }

    function test_consumer_rejects_bad_proof() public {
        (IdentityAction ia,, bytes32 root) = _consumer(false);
        vm.expectRevert(IdentityActionBase.BadProof.selector);
        ia.act(proof, root, bytes4(keccak256("vote")), 7, bytes32(0), keccak256("n"));
    }

    function test_consumer_different_scope_not_blocked() public {
        (IdentityAction ia,, bytes32 root) = _consumer(true);
        bytes4 tag = bytes4(keccak256("vote"));
        bytes32 nul = keccak256("nullifier-b");
        ia.act(proof, root, tag, 1, bytes32(0), nul);
        ia.act(proof, root, tag, 2, bytes32(0), nul);
    }
}
