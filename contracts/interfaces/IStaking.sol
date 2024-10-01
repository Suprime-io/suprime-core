// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


/**
 * @title IStaking
 * @dev Interface for the DEINStaking and AbstractLiquidityMiningStaking contract.
 */
interface IStaking {

    // permit parameter for permit functions
    struct PermitParams {
        uint256 deadline; // must be a timestamp in the future
        uint8 v; // a valid secp256k1 signature from owner over the EIP712-formatted function arguments
        bytes32 r; // a valid secp256k1 signature from owner over the EIP712-formatted function arguments
        bytes32 s; // a valid secp256k1 signature from owner over the EIP712-formatted function arguments
    }

    /// @notice emitted when reward is set
    event RewardsSet(
        uint256 indexed oldRewardPerBlock,
        uint256 indexed newRewardPerBlock,
        uint256 firstBlockWithReward,
        uint256 lastBlockWithReward
    );
    /// @notice emitted when token recovered
    event RewardTokensRecovered(uint256 amount);
    /// @notice emitted when user stake an amount of token
    event Staked(
        address indexed user,
        uint256 indexed stakingIndex,
        uint256 amount,
        uint256 indexed lock
    );
    /// @notice emitted when user withdraw staked amount
    event Withdrawn(
        address indexed user,
        uint256 indexed stakingIndex,
        uint256 amountByLiquidation,
        uint256 reward
    );
    /// @notice emitted when staker claim rewards for multiple tokens ids
    event RewardPaidMultiple(address indexed user, uint256[] stakingIndexes, uint256[] rewards);
    /// @notice emitted when staker claim rewards for one token
    event RewardPaidSingle(address indexed user, uint256 indexed stakingIndex, uint256 reward);
    /// @notice emitted when user increase the staking position
    event AddedToStake(address indexed user, uint256 indexed stakingIndex, uint256 amount);

    struct StakingInfo {
        uint256 staked; // staked token amount
        uint256 startTime; // start time of the stgaking lock
        uint256 rewards; // accumulated reward of the staking
        uint256 rewardPerTokenPaid; // reward per token ratio that user claimed
        address staker; // address of the staker
        uint8 lockingPeriod; // locking period of the staking in months
    }

    struct PublicStakingInfo {
        uint256 stakingId; // token id / index of the stake
        uint256 staked; // staked token amount
        uint256 startTime; // start time of the stgaking lock
        uint256 endTime; // end time of the stgaking lock
        uint256 rewards; // accumulated reward of the staking
        uint256 rewardPerTokenPaid; // reward per token ratio that user claimed
        address staker; // address of the staker
        uint8 lockingPeriod; // locking period of the staking in months
        uint8 stakingMultiplier; // muliplier of the stakin based in locking period
    }

    function totalPool() external view returns (uint256);

    function rewardPerBlock() external view returns (uint256);

    function blocksPerDay() external view returns (uint256);

    function totalPoolWithPower() external view returns (uint256);


    function stakeWithPermit(
        uint256 _amount,
        uint8 _lock,
        PermitParams calldata _permitParams
    ) external;

    function stake(uint256 _amount, uint8 _lock) external;

    function withdraw(uint256 _stakingIndex) external;

    function claimReward(uint256[] calldata _tokenIds) external;

    function restakeReward(
        uint256[] calldata _tokenIds,
        uint256 _stakingPositionInput,
        uint8 _stakingPosition
    ) external;

    function setRewards(uint256 _amount, uint256 _durations) external;

    function getFullStakedAmount(uint256 _stakingIndex) external view returns (uint256);

    function getFullStakedAmounts(
        uint256[] calldata _stakingIndexes
    ) external view returns (uint256 totalStaked);

    function canWithdraw(uint256 _stakingIndex) external view returns (bool);

    function balanceOf(address user) external view returns (uint256);

    function ownerOf(uint256 _stakingIndex) external view returns (address);

    function tokenOfOwnerByIndex(address user, uint256 index) external view returns (uint256);

    function getStakingInfoByStaker(
        address staker,
        uint256 offset,
        uint256 limit
    ) external view returns (PublicStakingInfo[] memory _stakingInfo);

    function getStakingInfoByIndexes(
        uint256[] calldata _stakingIndexes
    ) external view returns (PublicStakingInfo[] memory _stakingInfo);

    function getStakingInfoByIndex(
        uint256 _stakingIndex
    ) external view returns (PublicStakingInfo memory);

    function earned(uint256 _nftId) external view returns (uint256);
}
