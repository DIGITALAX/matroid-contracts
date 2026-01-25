// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaAccessControl.sol";
import "./GandaLibrary.sol";

contract GandaDesigners {
    GandaAccessControl public accessControl;
    address public reactionPacks;
    uint256 private _designerCount;

    mapping(uint256 => GandaLibrary.Designer) private _designers;
    mapping(address => uint256) private _designerLookup;

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    modifier onlyReactionPacks() {
        if (msg.sender != reactionPacks) revert GandaErrors.Unauthorized();
        _;
    }

    event DesignerInvited(
        address indexed designer,
        address indexed inviter,
        uint256 indexed designerId
    );
    event DesignerURI(uint256 indexed designerId, string uri);
    event DesignerDeactivated(
        uint256 indexed designerId,
        address indexed inviter
    );
    event ReactionPacksUpdated(address indexed packs);

    constructor(address accessControlAddress) {
        accessControl = GandaAccessControl(accessControlAddress);
        _designerCount = 0;
    }

    function inviteDesigner(address designer) external {
        if (!accessControl.isWhitelistedHolder(msg.sender) && !accessControl.isAdmin(msg.sender)) {
            revert GandaErrors.NotWhitelistedHolder();
        }
        if (_designers[_designerLookup[designer]].active) {
            revert GandaErrors.AlreadyExists();
        }
        if (designer == address(0)) revert GandaErrors.InvalidInput();

        uint256 designerId = _designerLookup[designer];
        if (designerId == 0) {
            _designerCount++;
            designerId = _designerCount;
            _designers[designerId] = GandaLibrary.Designer({
                wallet: designer,
                invitedBy: msg.sender,
                active: true,
                designerId: designerId,
                inviteTimestamp: block.timestamp,
                packCount: 0,
                reactionPackIds: new uint256[](0),
                uri: ""
            });
            _designerLookup[designer] = designerId;
        } else {
            _designers[designerId].invitedBy = msg.sender;
            _designers[designerId].inviteTimestamp = block.timestamp;
            _designers[designerId].active = true;
        }

        emit DesignerInvited(designer, msg.sender, designerId);
    }

    function setDesignerURI(uint256 designerId, string memory uri) public {
        if (_designers[designerId].wallet != msg.sender) {
            revert GandaErrors.Unauthorized();
        }
        _designers[designerId].uri = uri;
        emit DesignerURI(designerId, uri);
    }

    function deactivateDesigner(uint256 designerId) external {
        GandaLibrary.Designer storage designer = _designers[designerId];
        if (designer.designerId == 0) revert GandaErrors.DesignerNotFound();
        if (!designer.active) revert GandaErrors.DesignerNotActive();
        if (designer.invitedBy != msg.sender && !accessControl.isAdmin(msg.sender)) {
            revert GandaErrors.OnlyInviter();
        }
        designer.active = false;
        emit DesignerDeactivated(designerId, msg.sender);
    }

    function recordPack(address designer, uint256 packId) external onlyReactionPacks {
        uint256 designerId = _designerLookup[designer];
        if (designerId == 0) revert GandaErrors.DesignerNotFound();
        GandaLibrary.Designer storage info = _designers[designerId];
        info.packCount++;
        info.reactionPackIds.push(packId);
    }

    function getDesigner(uint256 designerId) external view returns (GandaLibrary.Designer memory) {
        return _designers[designerId];
    }

    function getDesignerByWallet(address wallet) external view returns (GandaLibrary.Designer memory) {
        uint256 designerId = _designerLookup[wallet];
        if (designerId == 0) revert GandaErrors.DesignerNotFound();
        return _designers[designerId];
    }

    function isDesigner(address wallet) external view returns (bool) {
        uint256 designerId = _designerLookup[wallet];
        return designerId != 0 && _designers[designerId].active;
    }

    function getDesignerCount() external view returns (uint256) {
        return _designerCount;
    }

    function setAccessControl(address accessControlAddress) external onlyAdmin {
        accessControl = GandaAccessControl(accessControlAddress);
    }

    function setReactionPacks(address packs) external onlyAdmin {
        reactionPacks = packs;
        emit ReactionPacksUpdated(packs);
    }
}
