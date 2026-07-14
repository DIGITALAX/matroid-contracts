// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/zk/IdentityRegistry.sol";
import {PoseidonHasher} from "../src/zk/PoseidonHasher.sol";
import {IVerifier} from "../src/zk/IVerifier.sol";
import {EnrollmentVerifier} from "../src/zk/verifiers/EnrollmentVerifier.sol";
import {IdentityAction} from "../src/zk/IdentityAction.sol";

contract MockEnrollVerifier is IVerifier {
    bool public result;

    constructor(bool r) {
        result = r;
    }

    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return result;
    }
}

contract IdentityRegistryTest is Test {
    bytes32 constant ACTION_ROOT = 0x2692d4547e528d8463ca98f764a2651a71fdc871eb745e646d21f359a8eb5068;

    PoseidonHasher hasher;
    bytes proof;
    bytes32 freshBind;
    bytes32 enrollNullifier;
    uint256 commitment;
    bytes32[20] zeroSiblings;

    function setUp() public {
        bytes memory poseidonCode = vm.getDeployedCode("PoseidonT3.sol:PoseidonT3");
        vm.etch(0x4B5DF730c2e6b28E17013A1485E5d9BC41Efe021, poseidonCode);
        hasher = new PoseidonHasher();
        proof = vm.readFileBinary("test/fixtures/enrollment.proof");
        bytes memory pi = vm.readFileBinary("test/fixtures/enrollment.public_inputs");
        assertEq(pi.length, 96);
        freshBind = _word(pi, 0);
        enrollNullifier = _word(pi, 1);
        commitment = uint256(_word(pi, 2));
    }

    function _word(bytes memory b, uint256 i) internal pure returns (bytes32 w) {
        assembly {
            w := mload(add(add(b, 32), mul(i, 32)))
        }
    }

    function test_tree_root_matches_action_circuit() public {
        MockEnrollVerifier mv = new MockEnrollVerifier(true);
        IdentityRegistry reg = new IdentityRegistry(address(mv), address(hasher));
        bytes32 root = reg.enroll(proof, freshBind, enrollNullifier, commitment, zeroSiblings);
        assertEq(root, ACTION_ROOT);
    }

    function test_real_enrollment_proof_verifies_and_inserts() public {
        EnrollmentVerifier v = new EnrollmentVerifier();
        IdentityRegistry reg = new IdentityRegistry(address(v), address(hasher));
        bytes32 root = reg.enroll(proof, freshBind, enrollNullifier, commitment, zeroSiblings);
        assertEq(root, ACTION_ROOT);
        assertTrue(reg.isKnownRoot(ACTION_ROOT));
        assertEq(reg.enrollmentCount(), 1);
        assertTrue(reg.usedEnrollNullifier(enrollNullifier));
    }

    function test_replay_enroll_nullifier_reverts() public {
        MockEnrollVerifier mv = new MockEnrollVerifier(true);
        IdentityRegistry reg = new IdentityRegistry(address(mv), address(hasher));
        reg.enroll(proof, freshBind, enrollNullifier, commitment, zeroSiblings);
        vm.expectRevert(IdentityRegistry.AlreadyEnrolled.selector);
        reg.enroll(proof, freshBind, enrollNullifier, commitment + 1, zeroSiblings);
    }

    function test_bad_proof_reverts() public {
        EnrollmentVerifier v = new EnrollmentVerifier();
        IdentityRegistry reg = new IdentityRegistry(address(v), address(hasher));
        bytes32 wrongCommitment = bytes32(commitment ^ 1);
        vm.expectRevert();
        reg.enroll(proof, freshBind, enrollNullifier, uint256(wrongCommitment), zeroSiblings);
    }

    function test_full_wiring_enroll_enables_action_root() public {
        EnrollmentVerifier ev = new EnrollmentVerifier();
        IdentityRegistry reg = new IdentityRegistry(address(ev), address(hasher));
        MockEnrollVerifier actionVerifier = new MockEnrollVerifier(true);
        IdentityAction action = new IdentityAction(address(actionVerifier), address(reg));

        assertFalse(action.identityRoots().isKnownRoot(ACTION_ROOT));
        reg.enroll(proof, freshBind, enrollNullifier, commitment, zeroSiblings);
        assertTrue(action.identityRoots().isKnownRoot(ACTION_ROOT));
    }

    function test_empty_root_is_known() public {
        MockEnrollVerifier mv = new MockEnrollVerifier(true);
        IdentityRegistry reg = new IdentityRegistry(address(mv), address(hasher));
        assertTrue(reg.isKnownRoot(reg.currentRoot()));
        assertFalse(reg.isKnownRoot(ACTION_ROOT));
    }
}
