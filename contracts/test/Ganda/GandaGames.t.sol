// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";
import {GandaLibrary} from "../../src/Ganda/GandaLibrary.sol";

contract GandaGamesTest is GandaTestBase {
    function testPublishGame() public {
        uint256 id = publishGame();
        assertEq(id, 1);
        GandaLibrary.Game memory game = games.getGame(id);
        assertEq(game.ownerTag, ownerTag);
        assertEq(game.scorer, scorer);
        assertEq(game.uri, "ipfs://game");
        assertEq(game.version, 0);
        assertTrue(game.exists);
        assertTrue(games.isActive(id));
    }

    function testPublishBannedTagReverts() public {
        blacklist.setTagBan(ownerTag, true);
        vm.expectRevert(GandaErrors.TagBanned.selector);
        publishGame();
    }

    function testPublishZeroScorerReverts() public {
        vm.expectRevert(GandaErrors.ZeroAddress.selector);
        games.publishGame(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            ownerTag,
            address(0),
            "ipfs://game"
        );
    }

    function testPushVersion() public {
        uint256 id = publishGame();
        games.pushVersion(
            id,
            hex"01",
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(4)),
            scorer2,
            0,
            "ipfs://game-v1"
        );
        GandaLibrary.Game memory game = games.getGame(id);
        assertEq(game.scorer, scorer2);
        assertEq(game.uri, "ipfs://game-v1");
        assertEq(game.version, 1);
    }

    function testPushVersionBadNonceReverts() public {
        uint256 id = publishGame();
        vm.expectRevert(GandaErrors.BadNonce.selector);
        games.pushVersion(
            id,
            hex"01",
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(4)),
            scorer2,
            5,
            "ipfs://game-v1"
        );
    }

    function testRetag() public {
        uint256 id = publishGame();
        games.retag(id, hex"01", hex"01", bytes32(uint256(1)), bytes32(uint256(6)), ownerTag2, 0);
        assertEq(games.ownerTagOf(id), ownerTag2);
    }

    function testRetagToBannedTagReverts() public {
        uint256 id = publishGame();
        blacklist.setTagBan(ownerTag2, true);
        vm.expectRevert(GandaErrors.TagBanned.selector);
        games.retag(id, hex"01", hex"01", bytes32(uint256(1)), bytes32(uint256(6)), ownerTag2, 0);
    }

    function testEraseGame() public {
        uint256 id = publishGame();
        games.eraseGame(id, hex"01", hex"01", bytes32(uint256(1)), bytes32(uint256(7)), 0);
        GandaLibrary.Game memory game = games.getGame(id);
        assertFalse(game.exists);
        assertEq(game.uri, "");
        assertEq(game.ownerTag, bytes32(0));
        assertFalse(games.isActive(id));
    }

    function testAdminEditGame() public {
        uint256 id = publishGame();
        games.adminEditGame(id, "ipfs://edited");
        assertEq(games.getGame(id).uri, "ipfs://edited");
    }

    function testBannedGameNotActive() public {
        uint256 id = publishGame();
        blacklist.setGameBan(id, true);
        assertFalse(games.isActive(id));
        blacklist.setGameBan(id, false);
        assertTrue(games.isActive(id));
    }
}
