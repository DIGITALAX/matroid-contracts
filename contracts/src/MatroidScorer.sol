// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {MatroidRegistry} from "./MatroidRegistry.sol";
import {MatroidLibrary} from "./MatroidLibrary.sol";
import "./MatroidErrors.sol";

contract MatroidScorer {
    uint256 public constant SCALE = 1e18;
    uint256 public immutable alpha;
    MatroidRegistry public immutable registry;

    constructor(address registryAddress, uint256 alphaScaled) {
        if (registryAddress == address(0)) revert MatroidErrors.ZeroAddress();
        registry = MatroidRegistry(registryAddress);
        alpha = alphaScaled;
    }

    function score(address project, uint256 epoch) external view returns (uint256) {
        MatroidLibrary.EpochStats memory stats = registry.getEpochStats(project, epoch);
        if (stats.monaUniqueUsers == 0 || stats.monaTotalVolume == 0) {
            return 0;
        }

        uint256 sqrtU = _sqrt(stats.monaUniqueUsers) * SCALE;
        uint256 retention = (stats.monaRecurringUsers * SCALE) / stats.monaUniqueUsers;
        if (retention < SCALE / 2) {
            retention = SCALE / 2;
        }
        uint256 activity = _log2(stats.monaCappedTxCount + 1) * SCALE;

        uint256 concentration = SCALE;
        if (stats.monaTotalVolume > 0) {
            uint256 cappedShare = (stats.monaCappedVolume * SCALE) / stats.monaTotalVolume;
            if (cappedShare > SCALE) cappedShare = SCALE;
            concentration = (SCALE / 2) + ((SCALE - cappedShare) / 2);
        }

        uint256 base = (sqrtU * retention) / SCALE;
        base = (base * activity) / SCALE;
        base = (base * concentration) / SCALE;

        uint256 otherIndex = _sqrt(stats.otherUniqueUsers)
            + _log2(stats.otherTxCount + 1)
            + stats.otherTokensUsed;
        uint256 otherBonus = SCALE + (alpha * otherIndex);

        return (base * otherBonus) / SCALE;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return 0;
        z = y;
        uint256 x = (y / 2) + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }

    function _log2(uint256 x) internal pure returns (uint256 y) {
        while (x > 1) {
            x >>= 1;
            y += 1;
        }
    }
}
