// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISuprimeStakingView {

    function getDefaultAPY() external view returns (uint256);

    function getPositionAPY(uint256 _tokenId) external view returns (uint256);

    function getExpectedAPY(uint256 _staked, uint256 _multiplier) external view returns (uint256);

    function getScore(address _user) external view returns (uint256 _totalScore);
}
