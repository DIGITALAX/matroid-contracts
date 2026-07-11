// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

interface IBlacklist {
    function isBanned(address who) external view returns (bool);
}

contract CyberswagmanRegistry {
    IBlacklist public immutable blacklist;

    struct Agent {
        address owner;
        bytes32 modelHash;
        bytes32 hardwareHash;
        string contentUri;
        bool exists;
    }

    mapping(uint256 => Agent) public agents;
    uint256 public agentCount;
    mapping(uint256 => mapping(uint256 => bool)) public inSchema;
    mapping(uint256 => mapping(uint256 => bytes32)) public result;

    event AgentRegistered(uint256 indexed agentId, address indexed owner, bytes32 modelHash, bytes32 hardwareHash, string contentUri);
    event AgentUpdated(uint256 indexed agentId, bytes32 modelHash, bytes32 hardwareHash, string contentUri);
    event SchemaChanged(uint256 indexed agentId, uint256 indexed kitId, bool included);
    event ResultPosted(uint256 indexed agentId, uint256 indexed projectId, bytes32 resultHash, string contentUri);
    event AgentDeleted(uint256 indexed agentId);

    error NoAgent();
    error NotOwner();
    error NoKits();
    error Banned();

    constructor(address blacklistAddress) {
        blacklist = IBlacklist(blacklistAddress);
    }

    function registerAgent(bytes32 modelHash, bytes32 hardwareHash, string calldata contentUri)
        external
        returns (uint256 agentId)
    {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        agentId = agentCount + 1;
        agentCount = agentId;
        agents[agentId] = Agent({
            owner: msg.sender,
            modelHash: modelHash,
            hardwareHash: hardwareHash,
            contentUri: contentUri,
            exists: true
        });
        emit AgentRegistered(agentId, msg.sender, modelHash, hardwareHash, contentUri);
    }

    function registerAgentWithKits(
        bytes32 modelHash,
        bytes32 hardwareHash,
        string calldata contentUri,
        uint256[] calldata kitIds
    ) external returns (uint256 agentId) {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        if (kitIds.length == 0) revert NoKits();
        agentId = agentCount + 1;
        agentCount = agentId;
        agents[agentId] = Agent({
            owner: msg.sender,
            modelHash: modelHash,
            hardwareHash: hardwareHash,
            contentUri: contentUri,
            exists: true
        });
        emit AgentRegistered(agentId, msg.sender, modelHash, hardwareHash, contentUri);
        for (uint256 i = 0; i < kitIds.length; i++) {
            inSchema[agentId][kitIds[i]] = true;
            emit SchemaChanged(agentId, kitIds[i], true);
        }
    }

    function updateAgent(
        uint256 agentId,
        bytes32 modelHash,
        bytes32 hardwareHash,
        string calldata contentUri,
        uint256[] calldata addKits,
        uint256[] calldata removeKits
    ) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        a.modelHash = modelHash;
        a.hardwareHash = hardwareHash;
        a.contentUri = contentUri;
        emit AgentUpdated(agentId, modelHash, hardwareHash, contentUri);
        for (uint256 i = 0; i < addKits.length; i++) {
            inSchema[agentId][addKits[i]] = true;
            emit SchemaChanged(agentId, addKits[i], true);
        }
        for (uint256 i = 0; i < removeKits.length; i++) {
            inSchema[agentId][removeKits[i]] = false;
            emit SchemaChanged(agentId, removeKits[i], false);
        }
    }

    function setSchema(uint256 agentId, uint256 kitId, bool included) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        inSchema[agentId][kitId] = included;
        emit SchemaChanged(agentId, kitId, included);
    }

    function postResult(uint256 agentId, uint256 projectId, bytes32 resultHash, string calldata contentUri) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        result[agentId][projectId] = resultHash;
        emit ResultPosted(agentId, projectId, resultHash, contentUri);
    }

    function deleteAgent(uint256 agentId) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        delete agents[agentId];
        emit AgentDeleted(agentId);
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        return agents[agentId].owner;
    }
}
