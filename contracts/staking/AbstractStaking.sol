// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../staking/libraries/RewardCalculator.sol";
import "../staking/libraries/CustomErrors.sol";

import "../interfaces/IStaking.sol";


/**
 * @dev The abstract contract for the SUPRIME token staking.
 */

abstract contract AbstractStaking is
    IStaking,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSet for EnumerableSet.UintSet;
    using Math for uint256;

    uint256 internal constant PRECISION = 10 ** 25;
    uint256 internal constant DECIMALS18 = 10 ** 18;
    uint256 internal constant MAX_LENGTH_50 = 50;
    // staking position
    uint8 internal constant STAKING_POSITION_NEW = 0;
    uint8 internal constant STAKING_POSITION_CURRENT = 1;
    //lock durations
    uint8 internal constant LOCKING_3_MONTH = 3;
    uint8 internal constant LOCKING_6_MONTH = 6;
    uint8 internal constant LOCKING_12_MONTH = 12;
    uint8 internal constant LOCKING_24_MONTH = 24;
    uint8 internal constant LOCKING_36_MONTH = 36;
    uint256 internal constant PERIOD_DURATION = 30 days;

    //7200 for Ethereum, 43200 for Base
    uint256 public blocksPerDay;

    /// @notice SUPRIME token contract address
    IERC20 public suprimeToken;

    /// @notice amount of reward distributes each block
    uint256 public rewardPerBlock;
    /// @notice first block reward distribution is started
    uint256 public firstBlockWithReward;
    /// @notice last block reward distribution is ended
    uint256 public lastBlockWithReward;
    /// @notice the block of last update of reward distribution
    uint256 public lastUpdateBlock;
    /// @notice the rewards per token accumulated of passed blocks
    uint256 public rewardPerTokenStored;
    /// @notice number of reward tokens already distributed and not claimed
    uint256 public rewardTokensLocked;

    /// @notice the total token staked in the pool
    uint256 public totalPool; // use for liquidation
    /// @notice the total token staked in the pool multiply by the staking multiplier
    uint256 public totalPoolWithPower; // use for rewards

    uint256 internal _stakingIndex; // next nft mint id for staking
    /// @notice get staking info by stake index
    mapping(uint256 stakeIndex => StakingInfo stakingInfo) internal stakers; // staking index or nft id

    mapping(address staker => EnumerableSet.UintSet stakingIndexes) internal stakerStaking; // staking index or nft id
    /// @notice get staking multiplier by staking duration
    mapping(uint8 stakeDuration => uint8 stakeMultiplier) internal stakedMultipliers;

    modifier updateReward(uint256 stakingIndex) {
        _updateReward(stakingIndex);
        _;
    }

    modifier checkLockingPeriod(uint256 _lock) {
        /// @dev nested if instead of AND save gas
        if (_lock != LOCKING_3_MONTH) {
            if (_lock != LOCKING_6_MONTH) {
                if (_lock != LOCKING_12_MONTH) {
                    if (_lock != LOCKING_24_MONTH) {
                        if (_lock != LOCKING_36_MONTH) {
                            revert CustomErrors.InvalidInput(_lock);
                        }
                    }
                }
            }
        }
        _;
    }

    // solhint-disable-next-line
    function __Staking_init(address _suprimeToken, uint256 _blocksPerDay) internal onlyInitializing {
        __Ownable2Step_init();
        __ReentrancyGuard_init();

        _stakingIndex = 1;
        _setStakedMultiplier();
        suprimeToken = IERC20(_suprimeToken);
        blocksPerDay = _blocksPerDay;
    }

    function getTotalPool() external view returns (uint256) {
        return totalPool;
    }

    function getRewardPerBlock() external view returns (uint256) {
        return rewardPerBlock;
    }

    function getTotalPoolWithPower() external view returns (uint256) {
        return totalPoolWithPower;
    }

    /// @notice return total staked amount stored of given staking indexes
    /// @dev the function used by claim voting so there is no check for bounding array input lenght
    /// as it is already checked while lock nft
    /// @param _stakingIndexes the list of index of the nft/staking
    function getFullStakedAmounts(
        uint256[] calldata _stakingIndexes
    ) external view returns (uint256 totalStaked) {
        for (uint256 i = _stakingIndexes.length; i != 0; i = i - 1) {
            totalStaked = totalStaked + getFullStakedAmount(_stakingIndexes[i - 1]);
        }
    }

    /// @notice set rewards, reward per block access: reward pool
    /// @param _amount amount of SUPRIME token rewards to distribute
    /// @param _days DAYS for the reward distribution
    function setRewards(uint256 _amount, uint256 _days) external onlyOwner updateReward(0) {
        uint256 _firstBlockWithReward = firstBlockWithReward;
        uint256 _lastBlockWithReward = lastBlockWithReward;
        uint256 _oldRewardPerBlock = rewardPerBlock;
        uint256 _unlockedTokens = RewardCalculator.getFutureRewardTokens(
            _firstBlockWithReward,
            _lastBlockWithReward,
            _oldRewardPerBlock
        );

        uint256 _blocksLeft = RewardCalculator.calculateBlocksLeft(
            _firstBlockWithReward,
            _lastBlockWithReward
        );

        uint256 _blocksAmount = _days * blocksPerDay;

        // cover overlapping blocks
        _blocksAmount = _blocksAmount + _blocksLeft;

        uint256 _rewardPerBlock = (_amount + _unlockedTokens) /_blocksAmount;
        _firstBlockWithReward = block.number;
        _lastBlockWithReward = block.number + _blocksAmount - 1;

        firstBlockWithReward = _firstBlockWithReward;
        lastBlockWithReward = _lastBlockWithReward;
        rewardPerBlock = _rewardPerBlock;

        uint256 _lockedTokens = RewardCalculator.getFutureRewardTokens(
            _firstBlockWithReward,
            _lastBlockWithReward,
            _rewardPerBlock
        );

        uint256 _rewardTokensLocked = rewardTokensLocked;
        _rewardTokensLocked = _rewardTokensLocked - _unlockedTokens + _lockedTokens;

        rewardTokensLocked = _rewardTokensLocked;

        uint256 _totalStakedAmount = totalPool;

        if (_rewardTokensLocked > suprimeToken.balanceOf(address(this)) - _totalStakedAmount) {
            revert CustomErrors.InsufficientLiquidity(_rewardTokensLocked);
        }

        emit RewardsSet(
            _oldRewardPerBlock,
            _rewardPerBlock,
            _firstBlockWithReward,
            _lastBlockWithReward
        );
    }

    /// @notice transfer left token reward to the owner
    function recoverNonLockedRewardTokens() external onlyOwner {
        uint256 _totalStakedAmount = totalPool;
        IERC20 _suprimeToken = suprimeToken;
        uint256 nonLockedTokens = _suprimeToken.balanceOf(address(this)) - rewardTokensLocked - _totalStakedAmount;
        if (nonLockedTokens != 0) {
            _suprimeToken.transfer(msg.sender, nonLockedTokens);

            emit RewardTokensRecovered(nonLockedTokens);
        }
    }

    /// @notice return staking info of all staker nfts
    /// @dev use with balanceOf()
    /// @param staker the address of the staker
    /// @param offset pagination start up place
    /// @param limit size of the listing page
    /// @return _stakingInfo list of PublicStakingInfo struct
    function getStakingInfoByStaker(
        address staker,
        uint256 offset,
        uint256 limit
    ) external view returns (PublicStakingInfo[] memory _stakingInfo) {
        uint256 to = (offset + limit).min(stakerStaking[staker].length()).max(offset);
        _stakingInfo = new PublicStakingInfo[](to - offset);
        uint256 stakingIndex;
        for (uint256 i = offset; i < to; i = i + 1) {
            stakingIndex = tokenOfOwnerByIndex(staker, i);

            _stakingInfo[i - offset] = getStakingInfoByIndex(stakingIndex);
        }
    }

    /// @notice return staking info of given staking indexes
    /// @param _stakingIndexes list of index of nft/staking
    /// @return _stakingInfo list of PublicStakingInfo struct
    function getStakingInfoByIndexes(
        uint256[] calldata _stakingIndexes
    ) external view returns (PublicStakingInfo[] memory _stakingInfo) {
        _stakingInfo = new PublicStakingInfo[](_stakingIndexes.length);

        for (uint256 i; i < _stakingIndexes.length; i = i + 1) {
            _stakingInfo[i] = getStakingInfoByIndex(_stakingIndexes[i]);
        }
    }

    /// @notice check if staker can withdraw based in lock endtime
    /// @param stakingIndex the index of the nft/staking
    function canWithdraw(uint256 stakingIndex) public view returns (bool) {
        return _getEndTime(stakingIndex) < block.timestamp;
    }

    /// @notice return staked amount stored of given staking index
    /// @param stakingIndex the index of the nft/staking
    function getFullStakedAmount(uint256 stakingIndex) public view returns (uint256) {
        return stakers[stakingIndex].staked;
    }

    function blocksWithRewardsPassed() public view returns (uint256) {
        return
            RewardCalculator.blocksWithRewardsPassed(
                lastUpdateBlock,
                firstBlockWithReward,
                lastBlockWithReward
            );
    }

    function rewardPerToken() public view returns (uint256) {
        uint256 _totalPoolStaked = totalPoolWithPower;
        uint256 _rewardPerTokenStored = rewardPerTokenStored;

        if (_totalPoolStaked == 0) {
            return _rewardPerTokenStored;
        }

        uint256 accumulatedReward = blocksWithRewardsPassed() * rewardPerBlock * DECIMALS18 / _totalPoolStaked;

        return _rewardPerTokenStored + accumulatedReward;
    }

    /// @notice return the amount of rewards
    /// @param _tokenIndex index of the nft/staking
    function earned(uint256 _tokenIndex) public view returns (uint256) {
        uint256 rewardsDifference = rewardPerToken() - stakers[_tokenIndex].rewardPerTokenPaid;

        uint256 newlyAccumulated = stakers[_tokenIndex]
            .staked * stakedMultipliers[stakers[_tokenIndex].lockingPeriod] * rewardsDifference / DECIMALS18;

        return stakers[_tokenIndex].rewards + newlyAccumulated;
    }

    /// @notice returns number of staks/NFT on user's account
    function balanceOf(address user) public view returns (uint256) {
        return stakerStaking[user].length();
    }

    /// @notice return the owner of an index of nft/staking
    function ownerOf(uint256 stakingIndex) public view returns (address) {
        return stakers[stakingIndex].staker;
    }

    /// @notice return the index of nft/staking for a given user and given index
    function tokenOfOwnerByIndex(address user, uint256 index) public view returns (uint256) {
        return stakerStaking[user].at(index);
    }

    /// @notice Returns a StakingInfo for a given staking/nft index
    /// @param stakingIndex index of the nft/staking
    function getStakingInfoByIndex(
        uint256 stakingIndex
    ) public view returns (PublicStakingInfo memory) {
        StakingInfo memory info = stakers[stakingIndex];
        return
            PublicStakingInfo(
                stakingIndex,
                info.staked,
                info.startTime,
                _getEndTime(stakingIndex),
                earned(stakingIndex),
                info.rewardPerTokenPaid,
                info.staker,
                info.lockingPeriod,
                stakedMultipliers[info.lockingPeriod]
            );
    }

    function _setStakedMultiplier() internal {
        stakedMultipliers[LOCKING_3_MONTH] = 1;
        stakedMultipliers[LOCKING_6_MONTH] = 2;
        stakedMultipliers[LOCKING_12_MONTH] = 3;
        stakedMultipliers[LOCKING_24_MONTH] = 4;
        stakedMultipliers[LOCKING_36_MONTH] = 5;
    }

    function _withdraw(
        uint256 stakingIndex,
        uint256 _amount
    ) internal {
        // substract the full amount
        totalPool = totalPool - _amount;
        // substract the amount with staking multiplier
        totalPoolWithPower = totalPoolWithPower - (_amount * stakedMultipliers[stakers[stakingIndex].lockingPeriod]);
    }

    function _calculateReward(
        uint256[] calldata _stakingIndexes
    ) internal returns (uint256 reward) {
        uint256 _length = _stakingIndexes.length;
        if (_length > MAX_LENGTH_50) {
            revert CustomErrors.ExceedMaxLimit(_length);
        }
        uint256[] memory rewards = new uint256[](_length);
        uint256 index;
        uint256 stakingIndex;
        uint256 _reward;
        for (uint256 i = _length; i != 0; i = i - 1) {
            index = i - 1;
            stakingIndex = _stakingIndexes[index];
            /// @dev nested if instead of AND save gas
            if (ownerOf(stakingIndex) != msg.sender) {
                CustomErrors.unauthorizedRevert();
            }

            _updateReward(stakingIndex);

            _reward = _getReward(stakingIndex);
            reward = reward + _reward;
            rewards[index] = _reward;
        }
        emit RewardPaidMultiple(msg.sender, _stakingIndexes, rewards);
    }

    function _getReward(uint256 stakingIndex) internal returns (uint256 _reward) {
        _reward = stakers[stakingIndex].rewards;

        if (_reward != 0) {
            delete stakers[stakingIndex].rewards;
            rewardTokensLocked = rewardTokensLocked - _reward;
        }
    }

    function _getEndTime(uint256 stakingIndex) internal view returns (uint256) {
        uint256 _lockingPeriod = stakers[stakingIndex].lockingPeriod;
        return stakers[stakingIndex].startTime + (_lockingPeriod * PERIOD_DURATION);
    }

    function _updateReward(uint256 stakingIndex) internal {
        uint256 currentRewardPerToken = rewardPerToken();

        rewardPerTokenStored = currentRewardPerToken;
        lastUpdateBlock = block.number;
        /// @dev nested if save gas
        if (stakingIndex != 0) {
            stakers[stakingIndex].rewards = earned(stakingIndex);
            stakers[stakingIndex].rewardPerTokenPaid = currentRewardPerToken;
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
