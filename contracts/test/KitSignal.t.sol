// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {KitSignal} from "../src/zk/KitSignal.sol";
import {IdentityActionBase, IIdentityActionRoots} from "../src/zk/IdentityActionBase.sol";
import {IVerifier} from "../src/zk/IVerifier.sol";

contract KsMockVerifier is IVerifier {
    bool public result;

    constructor(bool r) {
        result = r;
    }

    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return result;
    }
}

contract KsMockRoots is IIdentityActionRoots {
    mapping(bytes32 => bool) public known;

    function setKnown(bytes32 root, bool ok) external {
        known[root] = ok;
    }

    function isKnownRoot(bytes32 root) external view returns (bool) {
        return known[root];
    }
}

contract KitSignalTest is Test {
    KsMockRoots roots;
    KitSignal kit;
    bytes32 root = keccak256("root");
    bytes proof = hex"00";
    uint256 constant KIT = 7;

    function setUp() public {
        roots = new KsMockRoots();
        roots.setKnown(root, true);
        kit = new KitSignal(address(new KsMockVerifier(true)), address(roots));
    }

    function _signal(uint8 code, uint256 nonce, bytes32 nul) internal {
        kit.signal(proof, root, KIT, code, nonce, nul);
    }

    function test_signal_tallies_up() public {
        bytes32 nul = keccak256("a");
        _signal(1, 1, nul);
        assertEq(kit.tally(KIT, 1), 1);
        assertEq(kit.reactionChoice(KIT, nul), 2);
        assertEq(kit.reactionNonce(KIT, nul), 1);
    }

    function test_change_reaction() public {
        bytes32 nul = keccak256("a");
        _signal(1, 1, nul);
        _signal(0, 2, nul);
        assertEq(kit.tally(KIT, 1), 0);
        assertEq(kit.tally(KIT, 0), 1);
        assertEq(kit.reactionChoice(KIT, nul), 1);
    }

    function test_retract() public {
        bytes32 nul = keccak256("a");
        _signal(1, 1, nul);
        _signal(2, 2, nul);
        assertEq(kit.tally(KIT, 1), 0);
        assertEq(kit.reactionChoice(KIT, nul), 0);
    }

    function test_stale_nonce_reverts() public {
        bytes32 nul = keccak256("a");
        _signal(1, 5, nul);
        vm.expectRevert(KitSignal.StaleSignal.selector);
        _signal(0, 5, nul);
    }

    function test_invalid_choice_reverts() public {
        vm.expectRevert(KitSignal.InvalidChoice.selector);
        _signal(3, 1, keccak256("a"));
    }

    function test_bad_nonce_reverts() public {
        vm.expectRevert(KitSignal.BadNonce.selector);
        _signal(1, 0, keccak256("a"));
    }

    function test_unknown_root_reverts() public {
        vm.expectRevert(IdentityActionBase.UnknownRoot.selector);
        kit.signal(proof, keccak256("nope"), KIT, 1, 1, keccak256("a"));
    }

    function test_bad_proof_reverts() public {
        KitSignal k2 = new KitSignal(address(new KsMockVerifier(false)), address(roots));
        vm.expectRevert(IdentityActionBase.BadProof.selector);
        k2.signal(proof, root, KIT, 1, 1, keccak256("a"));
    }

    function test_two_users_independent() public {
        _signal(1, 1, keccak256("a"));
        _signal(1, 1, keccak256("b"));
        assertEq(kit.tally(KIT, 1), 2);
    }
}
