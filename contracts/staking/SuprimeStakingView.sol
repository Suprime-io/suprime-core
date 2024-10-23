// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IStaking.sol";
import "../interfaces/ISuprimeStakingView.sol";

import "./libraries/SafeMath.sol";
import "./libraries/CustomErrors.sol";


/**
 * @dev SUPRIME staking view contract, read-only methods to read the staking states.
 */

contract SuprimeStakingView is ISuprimeStakingView, Initializable {
    using SafeMath for uint256;
    using Math for uint256;

    IStaking public suprimeStaking;

    // solhint-disable-next-line
    function __SuprimeStakingView_init(address _suprimeStaking) external initializer {
        suprimeStaking = IStaking(_suprimeStaking);
    }

    //// @notice Retunrs the Max APY
    /// @return uint256 apy amount in 10**7 precision
    function getDefaultAPY() external view returns (uint256) {
        return _getAPY(100 ether, 5, true);
    }

    /// @notice Retunrs the expected APY of a given position
    /// @dev return expected apy for given staked amount and given multiplier
    /// @return uint256 apy amount in 10**7 precision
    function getExpectedAPY(uint256 _staked, uint256 _multiplier) external view returns (uint256) {
        return _getAPY(_staked, _multiplier, true);
    }

    /// @notice Retunrs the APY of a given nft id
    /// @dev return current apy
    /// @param _tokenId nft id
    /// @return _apy uint256 apy amount in 10**7 precision
    function getPositionAPY(uint256 _tokenId) external view returns (uint256 _apy) {
        IStaking.PublicStakingInfo memory _stakingInfo = suprimeStaking.getStakingInfoByIndex(
            _tokenId
        );
        uint256 _staked = _stakingInfo.staked;
        uint256 _multiplier = _stakingInfo.stakingMultiplier;
        _apy = _getAPY(_staked, _multiplier, false);
    }

    /// @notice get the total score (staking plus XP) of the user
    /// @dev aggregates all user's nfts and adds the XP
    /// @param  _user the address of the user
    /// @return _totalScore score of the user
    function getScore(
        address _user
    ) external view returns (uint256 _totalScore) {
        IStaking _suprimeStaking = suprimeStaking;
        uint256 stakedNFTCount = _suprimeStaking.balanceOf(_user);

        uint256 tokenId;
        for (uint256 i; i < stakedNFTCount; i = i.uncheckedInc()) {
            tokenId = suprimeStaking.tokenOfOwnerByIndex(_user, i);
            _totalScore = _totalScore.add(_getTokenStakingPower(tokenId));
            //TODO Add the score from XP
        }
    }

    function _getAPY(
        uint256 _staked,
        uint256 _multiplier,
        bool isExpected
    ) internal view returns (uint256) {
        IStaking _suprimeStaking = suprimeStaking;
        uint256 _stakedByM = _staked * _multiplier;

        uint256 _totalPoolWithPower = _suprimeStaking.totalPoolWithPower();

        _totalPoolWithPower = isExpected
            ? _totalPoolWithPower.add(_stakedByM)
            : _totalPoolWithPower;

        return
            _suprimeStaking
                .rewardPerBlock() * (_suprimeStaking.blocksPerDay() * 365)
                * (10 ** 7)                            //precision
                * _stakedByM / _totalPoolWithPower / _staked;
    }

    function _getTokenStakingPower(
        uint256 _tokenId
    ) internal view returns (uint256 _stakingPower) {
        IStaking.PublicStakingInfo memory _stakingInfo = suprimeStaking.getStakingInfoByIndex(
            _tokenId
        );
        uint256 _staked = _stakingInfo.staked;
        uint256 _multiplier = _stakingInfo.stakingMultiplier;
        _stakingPower = _staked * _multiplier;
    }
}
