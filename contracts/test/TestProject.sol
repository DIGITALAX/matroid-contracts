// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {ProjectNFTStakingPool} from "../src/ProjectNFTStakingPool.sol";

contract TestProject {
    IERC20 public immutable mona;
    MatroidKit public immutable matroidKit;
    MatroidRegistry public immutable registry;
    address public owner;

    error NotOwner();
    error ZeroAddress();

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);

    constructor(address monaToken, address matroidKitAddress) {
        if (monaToken == address(0) || matroidKitAddress == address(0)) revert ZeroAddress();
        owner = msg.sender;
        mona = IERC20(monaToken);
        matroidKit = MatroidKit(matroidKitAddress);
        registry = MatroidRegistry(matroidKit.registry());
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnerUpdated(oldOwner, newOwner);
    }

    function register(string calldata metadata, bool pool) external onlyOwner {
        matroidKit.registerProject(metadata, pool);
    }

    function payIn(uint256 amount) external {
        matroidKit.matroidIn(msg.sender, address(mona), amount);
    }

    function payOut(address user, uint256 amount) external onlyOwner {
        matroidKit.matroidOut(user, address(mona), amount);
    }

    function approveRegistry(
        address token,
        address registryAddress,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).approve(registryAddress, amount);
    }

    function setClaimer(address claimer, bool allowed) external onlyOwner {
        registry.setClaimer(claimer, allowed);
    }

    function updateMetadata(string calldata metadata) external onlyOwner {
        registry.updateMetadata(metadata);
    }

    function createProjectPool() external onlyOwner {
        registry.createProjectPool();
    }

    function setRewardSplits(
        uint16 globalSplitBps,
        uint16 projectErc20SplitBps,
        uint16 projectNftSplitBps
    ) external onlyOwner {
        registry.setRewardSplits(globalSplitBps, projectErc20SplitBps, projectNftSplitBps);
    }

    function setProjectNftWeight(address nft, uint256 weight) external onlyOwner {
        (, address nftPool,,,) = registry.projectRewards(address(this));
        if (nftPool == address(0)) revert ZeroAddress();
        ProjectNFTStakingPool(nftPool).setNftWeight(nft, weight);
    }
}
