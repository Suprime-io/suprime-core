// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./SafeMath.sol";

library RewardCalculator {
    using SafeMath for uint256;

    function blocksWithRewardsPassed(
        uint256 lastUpdateBlock,
        uint256 firstBlockWithReward,
        uint256 lastBlockWithReward
    ) internal view returns (uint256) {
        uint256 from = Math.max(lastUpdateBlock, firstBlockWithReward);
        uint256 to = Math.min(block.number, lastBlockWithReward);
        return to.trySub(from);
    }

    function getFutureRewardTokens(
        uint256 firstBlockWithReward,
        uint256 lastBlockWithReward,
        uint256 rewardPerBlock
    ) internal view returns (uint256) {
        uint256 blocksLeft = calculateBlocksLeft(firstBlockWithReward, lastBlockWithReward);
        return blocksLeft.mul(rewardPerBlock);
    }

    function calculateBlocksLeft(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (block.number >= _to) return 0;

        if (block.number < _from) return _to.sub(_from).tryAdd(1);

        return _to.uncheckedSub(block.number);
    }
}
