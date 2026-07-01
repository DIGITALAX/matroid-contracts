// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CyberswagmanRegistry {
    uint256 private constant ACC = 1e18;

    IERC20 public immutable mona;
    address public immutable weightSetter;

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

    mapping(uint256 => mapping(address => uint256)) public weight;
    mapping(uint256 => uint256) public totalWeight;
    mapping(uint256 => uint256) public accRewardPerWeight;
    mapping(uint256 => mapping(address => uint256)) public rewardDebt;
    mapping(uint256 => mapping(address => uint256)) public pending;

    event AgentRegistered(uint256 indexed agentId, address indexed owner, bytes32 modelHash, bytes32 hardwareHash, string contentUri);
    event AgentUpdated(uint256 indexed agentId, bytes32 modelHash, bytes32 hardwareHash);
    event SchemaChanged(uint256 indexed agentId, uint256 indexed kitId, bool included);
    event ResultPosted(uint256 indexed agentId, uint256 indexed projectId, bytes32 resultHash);
    event AgentDeleted(uint256 indexed agentId);
    event WeightSet(uint256 indexed projectId, address indexed swagman, uint256 weight);
    event RewardAdded(uint256 indexed projectId, uint256 amount);
    event Claimed(uint256 indexed projectId, address indexed swagman, uint256 amount);

    error NoAgent();
    error NotOwner();
    error NotSetter();
    error ZeroAmount();
    error NoWeight();
    error TransferFailed();

    constructor(address monaAddress, address weightSetterAddress) {
        mona = IERC20(monaAddress);
        weightSetter = weightSetterAddress;
    }

    function registerAgent(bytes32 modelHash, bytes32 hardwareHash, string calldata contentUri)
        external
        returns (uint256 agentId)
    {
        agentId = agentCount;
        agentCount = agentId + 1;
        agents[agentId] = Agent({
            owner: msg.sender,
            modelHash: modelHash,
            hardwareHash: hardwareHash,
            contentUri: contentUri,
            exists: true
        });
        emit AgentRegistered(agentId, msg.sender, modelHash, hardwareHash, contentUri);
    }

    function updateAgent(uint256 agentId, bytes32 modelHash, bytes32 hardwareHash) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        a.modelHash = modelHash;
        a.hardwareHash = hardwareHash;
        emit AgentUpdated(agentId, modelHash, hardwareHash);
    }

    function setSchema(uint256 agentId, uint256 kitId, bool included) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        inSchema[agentId][kitId] = included;
        emit SchemaChanged(agentId, kitId, included);
    }

    function postResult(uint256 agentId, uint256 projectId, bytes32 resultHash) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        result[agentId][projectId] = resultHash;
        emit ResultPosted(agentId, projectId, resultHash);
    }

    function deleteAgent(uint256 agentId) external {
        Agent storage a = agents[agentId];
        if (!a.exists) revert NoAgent();
        if (a.owner != msg.sender) revert NotOwner();
        delete agents[agentId];
        emit AgentDeleted(agentId);
    }

    function setWeight(uint256 projectId, address swagman, uint256 newWeight) external {
        if (msg.sender != weightSetter) revert NotSetter();
        _settle(projectId, swagman);
        uint256 old = weight[projectId][swagman];
        weight[projectId][swagman] = newWeight;
        totalWeight[projectId] = totalWeight[projectId] - old + newWeight;
        rewardDebt[projectId][swagman] = newWeight * accRewardPerWeight[projectId] / ACC;
        emit WeightSet(projectId, swagman, newWeight);
    }

    function notifyReward(uint256 projectId, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (totalWeight[projectId] == 0) revert NoWeight();
        if (!mona.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        accRewardPerWeight[projectId] += amount * ACC / totalWeight[projectId];
        emit RewardAdded(projectId, amount);
    }

    function pendingReward(uint256 projectId, address swagman) external view returns (uint256) {
        uint256 accrued = weight[projectId][swagman] * accRewardPerWeight[projectId] / ACC;
        return pending[projectId][swagman] + accrued - rewardDebt[projectId][swagman];
    }

    function claim(uint256 projectId) external {
        _settle(projectId, msg.sender);
        uint256 amount = pending[projectId][msg.sender];
        if (amount == 0) return;
        pending[projectId][msg.sender] = 0;
        if (!mona.transfer(msg.sender, amount)) revert TransferFailed();
        emit Claimed(projectId, msg.sender, amount);
    }

    function _settle(uint256 projectId, address swagman) internal {
        uint256 accrued = weight[projectId][swagman] * accRewardPerWeight[projectId] / ACC;
        pending[projectId][swagman] += accrued - rewardDebt[projectId][swagman];
        rewardDebt[projectId][swagman] = accrued;
    }
}
