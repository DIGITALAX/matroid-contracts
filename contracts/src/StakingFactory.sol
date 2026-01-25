// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ProjectStakingPool} from "./ProjectStakingPool.sol";
import {ProjectNFTStakingPool} from "./ProjectNFTStakingPool.sol";

contract StakingFactory {
    event ProjectPoolsCreated(address indexed project, address erc20Pool, address nftPool);
    uint256 public immutable rewardDuration;

    constructor(uint256 rewardDurationSeconds) {
        rewardDuration = rewardDurationSeconds;
    }

    function createProjectPools(address monaToken, address project) external returns (address erc20Pool, address nftPool) {
        erc20Pool = address(new ProjectStakingPool(monaToken, project, rewardDuration));
        nftPool = address(new ProjectNFTStakingPool(monaToken, project, rewardDuration));
        emit ProjectPoolsCreated(project, erc20Pool, nftPool);
    }
}
