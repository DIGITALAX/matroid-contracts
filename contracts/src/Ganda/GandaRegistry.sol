// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaAccessControl.sol";
import "./GandaLibrary.sol";
import "./GandaReactionPacks.sol";

contract GandaRegistry {
    GandaAccessControl public accessControl;
    GandaReactionPacks public reactionPacks;
    uint256 private _ganadaCount;
    uint256 private _reactionCount;

    mapping(uint256 => GandaLibrary.Ganda) private _ganadas;
    mapping(uint256 => GandaLibrary.GandaReaction) private _reactions;

    event GandaRegistered(uint256 indexed ganadaId, address indexed creator, string uri);
    event GandaUpdated(uint256 indexed ganadaId, string uri);
    event GandaDeactivated(uint256 indexed ganadaId);
    event ReactionSubmitted(
        uint256 indexed ganadaId,
        uint256 indexed reactionId,
        address indexed reviewer
    );

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    constructor(address accessControlAddress, address reactionPacksAddress) {
        accessControl = GandaAccessControl(accessControlAddress);
        reactionPacks = GandaReactionPacks(reactionPacksAddress);
        _ganadaCount = 0;
        _reactionCount = 0;
    }

    function registerGanda(address creator, string calldata uri) external onlyAdmin returns (uint256) {
        if (creator == address(0)) revert GandaErrors.InvalidInput();
        _ganadaCount++;
        _ganadas[_ganadaCount] = GandaLibrary.Ganda({
            ganadaId: _ganadaCount,
            creator: creator,
            uri: uri,
            createdAt: uint64(block.timestamp),
            active: true,
            reactionCount: 0
        });
        emit GandaRegistered(_ganadaCount, creator, uri);
        return _ganadaCount;
    }

    function updateGanda(uint256 ganadaId, string calldata uri) external onlyAdmin {
        GandaLibrary.Ganda storage ganada = _ganadas[ganadaId];
        if (ganada.ganadaId == 0) revert GandaErrors.NotFound();
        ganada.uri = uri;
        emit GandaUpdated(ganadaId, uri);
    }

    function deactivateGanda(uint256 ganadaId) external onlyAdmin {
        GandaLibrary.Ganda storage ganada = _ganadas[ganadaId];
        if (ganada.ganadaId == 0) revert GandaErrors.NotFound();
        ganada.active = false;
        emit GandaDeactivated(ganadaId);
    }

    function submitReaction(
        uint256 ganadaId,
        string calldata uri,
        GandaLibrary.ReactionUsage[] calldata reactions
    ) external {
        GandaLibrary.Ganda storage ganada = _ganadas[ganadaId];
        if (ganada.ganadaId == 0) revert GandaErrors.NotFound();
        if (!ganada.active) revert GandaErrors.NotActive();
        _validateReactions(msg.sender, reactions);

        _reactionCount++;
        GandaLibrary.GandaReaction storage reaction = _reactions[_reactionCount];
        reaction.reviewer = msg.sender;
        reaction.reactionId = _reactionCount;
        reaction.ganadaId = ganadaId;
        reaction.timestamp = block.timestamp;
        reaction.uri = uri;
        for (uint256 i = 0; i < reactions.length; i++) {
            reaction.reactions.push(reactions[i]);
        }
        ganada.reactionCount++;
        emit ReactionSubmitted(ganadaId, _reactionCount, msg.sender);
    }

    function _validateReactions(
        address user,
        GandaLibrary.ReactionUsage[] calldata reactions
    ) private view {
        for (uint256 i = 0; i < reactions.length; i++) {
            if (reactions[i].count == 0) revert GandaErrors.InvalidInput();
            GandaLibrary.Reaction memory reaction = reactionPacks.getReaction(reactions[i].reactionId);
            if (reaction.reactionId == 0) revert GandaErrors.ReactionPackNotFound();
            uint256 userBalance = 0;
            for (uint256 j = 0; j < reaction.tokenIds.length; j++) {
                try reactionPacks.ownerOf(reaction.tokenIds[j]) returns (address owner) {
                    if (owner == user) {
                        userBalance++;
                    }
                } catch {
                    continue;
                }
            }
            if (userBalance < reactions[i].count) {
                revert GandaErrors.InsufficientBalance();
            }
        }
    }

    function getGanda(uint256 ganadaId) external view returns (GandaLibrary.Ganda memory) {
        return _ganadas[ganadaId];
    }

    function getReaction(uint256 reactionId) external view returns (GandaLibrary.GandaReaction memory) {
        return _reactions[reactionId];
    }

    function getGandaCount() external view returns (uint256) {
        return _ganadaCount;
    }

    function getReactionCount() external view returns (uint256) {
        return _reactionCount;
    }

    function setAccessControl(address accessControlAddress) external onlyAdmin {
        accessControl = GandaAccessControl(accessControlAddress);
    }

    function setReactionPacks(address reactionPacksAddress) external onlyAdmin {
        reactionPacks = GandaReactionPacks(reactionPacksAddress);
    }
}
