// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

import "../interfaces/ISuprimeStaking.sol";
import "../interfaces/tokens/erc20permit-upgradeable/IERC20PermitUpgradeable.sol";

import "../staking/AbstractStaking.sol";

/**
 * @dev Staking pool keeps staked SUPRIME tokens, in exchange users will get an nft.
 * The staking is locked for a certain period (3,6,12,24,36) months. Each duration multiplies the rewards.
 * Rewards are set in a form of SUPRIME tokens and can be claimed at any time.
 * The staker can't withdraw staked tokens before the locking period ends.
 */

contract SuprimeStaking is ISuprimeStaking, ERC1155Upgradeable, AbstractStaking {
    using EnumerableSet for EnumerableSet.UintSet;

    // solhint-disable-next-line
    function __SuprimeStaking_init(address _suprimeToken, uint256 _blocksPerDay) external initializer {
        __Staking_init(_suprimeToken, _blocksPerDay);
        __ERC1155_init("");
    }

    /// @dev this is a correct URI: "https://token-cdn-domain/"
    function setBaseURI(string calldata newURI) external onlyOwner {
        if (bytes(newURI).length == 0) {
            revert CustomErrors.InvalidInput(0);
        }
        _setURI(newURI);
    }

    /// @notice stake token without approve, minting new nft to the sender
    /// @param _amountSuprime the amount of SUPRIME tokens to stake
    /// @param _lock locking period of the stake, should be 1,3,6,12,24 month
    /// @param _permitParams permit function parameters
    function stakeWithPermit(
        uint256 _amountSuprime,
        uint8 _lock,
        PermitParams calldata _permitParams
    ) external nonReentrant {
        address thisAddress = address(this);
        try
            IERC20PermitUpgradeable(address(suprimeToken)).permit(
                msg.sender,
                thisAddress,
                _amountSuprime,
                _permitParams.deadline,
                _permitParams.v,
                _permitParams.r,
                _permitParams.s
            )
        {} catch {
            if (suprimeToken.allowance(msg.sender, thisAddress) < _amountSuprime) {
                revert CustomErrors.InvalidSignature();
            }
        }

        _stake(msg.sender, _amountSuprime, _lock, true);
    }

    /// @notice stake the token, approve is required before that, minting new nft to the sender
    /// @param _amountSuprime amount of SUPRIME token to stake
    /// @param _lock locking period of the stake, should be 1,3,6,12,24 month
    function stake(uint256 _amountSuprime, uint8 _lock) external nonReentrant {
        _stake(msg.sender, _amountSuprime, _lock, true);
    }

    /// @notice withdraw the token + rewards of the given nft, access: nft owner
    /// The locking period must pass
    /// Burns the nft
    /// @param _tokenId nft id
    function withdraw(uint256 _tokenId) external updateReward(_tokenId) {
        if (ownerOf(_tokenId) != msg.sender) {
            CustomErrors.unauthorizedRevert();
        }
        if (!canWithdraw(_tokenId)) {
            revert CustomErrors.ClaimNotReady(msg.sender);
        }

        uint256 _stakedAmount = stakers[_tokenId].staked;

        _withdraw(_tokenId, _stakedAmount);

        _removeTokenPosition(_tokenId, _stakedAmount);
    }

    /// @notice claim rewards, by the nft owner
    /// @dev claim rewards for one or more position
    /// @param _tokenIds list of token ids to claim its rewards
    function claimReward(uint256[] calldata _tokenIds) external {
        uint256 reward = _calculateReward(_tokenIds);

        if (reward != 0) {
            suprimeToken.transfer(msg.sender, reward);
        }
    }

    /// @notice restake rewards of given nft/nfts access: by nft owner
    /// @dev user restake the rewards of one or more position to a new position or an existence position
    /// @param _tokenIds list of token ids to restake its rewards
    /// @param _stakingPositionInput if _stakingPosition new , the _stakingPositionInput should be locking period
    /// otherwise should be an existence tokenId
    /// @param _stakingPosition new native staking pool staker, or has an existence nft
    function restakeReward(
        uint256[] calldata _tokenIds,
        uint256 _stakingPositionInput,
        uint8 _stakingPosition
    ) external nonReentrant {
        uint256 reward = _calculateReward(_tokenIds);

        if (reward != 0) {
            _validateStakePosition(_stakingPosition);
            StakeForParams memory _stakeForParameters = StakeForParams(
                reward,
                _stakingPositionInput,
                msg.sender,
                _stakingPosition
            );

            _stakeRouting(_stakeForParameters, false);
        }
    }

    /// @dev the output URI will be: "https://token-cdn-domain/<tokenId>"
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(super.uri(0), Strings.toString(tokenId)));
    }

    /// @notice claim the original staking
    /// @param _tokenId the nft id
    /// @param _amount the amount user wants to claim
    function claim(uint256 _tokenId, uint256 _amount) public updateReward(_tokenId) {
        if (ownerOf(_tokenId) != msg.sender) {
            CustomErrors.unauthorizedRevert();
        }

        // vesitng allowed in case locking period not ended,otherwise user can withdraw all
        if (canWithdraw(_tokenId)) {
            revert CustomErrors.CannotClaim();
        }
        if (_amount == 0 ) {
            revert CustomErrors.InvalidInput(_amount);
        }

        _withdraw(_tokenId, _amount);
        uint256 _staked = stakers[_tokenId].staked;
        if (_amount == _staked) {
            //withdraw full position
            _removeTokenPosition(_tokenId, _amount);
        } else {
            stakers[_tokenId].staked = _staked - _amount;
            suprimeToken.transfer(msg.sender, _amount);
            emit Withdrawn(msg.sender, _tokenId, _amount, 0);
        }
    }

    function _validateStakePosition(uint8 stakingPosition) internal pure {
        if (
            stakingPosition != STAKING_POSITION_NEW && stakingPosition != STAKING_POSITION_CURRENT
        ) {
            revert CustomErrors.InvalidInput(stakingPosition);
        }
    }

    /// @dev update state(holder,owner of the nft) with any nft transfer
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        for (uint256 i; i < ids.length; i = i + 1) {
            if (values[i] != 1) {
                // not an NFT
                continue;
            }
            if (from == address(0)) {
                // minting
                stakerStaking[to].add(ids[i]);
            } else if (to == address(0)) {
                // burning
                stakerStaking[from].remove(ids[i]);
            } else {
                // transferring, NOT allowed
                revert CustomErrors.TransferNotAllowed();
            }
        }
        super._update(from, to, ids, values);
    }

    function _removeTokenPosition(uint256 _tokenId, uint256 _amount) internal {
        // claim rewards of NFT before burning
        uint256 reward = _getReward(_tokenId);

        _burnNFT(msg.sender, _tokenId);
        uint256 _totalAmount = _amount + reward;
        if (_totalAmount != 0) {
            suprimeToken.transfer(msg.sender, _totalAmount);
            if (reward != 0) {
                emit RewardPaidSingle(msg.sender, _tokenId, reward);
            }
        }

        emit Withdrawn(msg.sender, _tokenId, _amount, reward);
    }

    function _stakeRouting(StakeForParams memory _stakeForParams, bool _withTransfer) internal {
        _stakeForParams.stakingPosition == STAKING_POSITION_NEW
            ? _stake(
                _stakeForParams.user,
                _stakeForParams.amountSuprime,
                uint8(_stakeForParams.stakingPositionInput),
                _withTransfer
            )
            : _addToStake(
                _stakeForParams.user,
                _stakeForParams.stakingPositionInput,
                _stakeForParams.amountSuprime
            );
    }

    function _addToStake(
        address _staker,
        uint256 _tokenId,
        uint256 _amountSuprime
    ) internal updateReward(_tokenId) {
        if (ownerOf(_tokenId) != _staker) {
            CustomErrors.unauthorizedRevert();
        }

        totalPool = totalPool + _amountSuprime;
        uint8 _lockingPeriod = stakers[_tokenId].lockingPeriod;
        totalPoolWithPower = totalPoolWithPower + (_amountSuprime * stakedMultipliers[_lockingPeriod]);
        stakers[_tokenId].staked = stakers[_tokenId].staked + _amountSuprime;

        emit AddedToStake(_staker, _tokenId, _amountSuprime);
    }

    function _stake(
        address _staker,
        uint256 _amountSuprime,
        uint8 _lock,
        bool _withTransfer
    ) internal updateReward(_stakingIndex) checkLockingPeriod(_lock) {
        if (_amountSuprime == 0) {
            revert CustomErrors.InvalidInput(_amountSuprime);
        }

        totalPool = totalPool + _amountSuprime;

        uint8 multiplier = stakedMultipliers[_lock];
        totalPoolWithPower = totalPoolWithPower + (_amountSuprime * multiplier);
        uint256 stakingIndex = _stakingIndex;

        stakers[stakingIndex].staker = _staker;
        stakers[stakingIndex].staked = _amountSuprime;
        stakers[stakingIndex].startTime = block.timestamp;
        stakers[stakingIndex].lockingPeriod = _lock;

        if (_withTransfer) {
            suprimeToken.transferFrom(msg.sender, address(this), _amountSuprime);
        }

        emit Staked(_staker, stakingIndex, _amountSuprime, _lock);

        _mintNewNFT(stakingIndex, _staker);
    }

    function _mintNewNFT(uint256 stakingIndex, address _staker) internal {
        _mint(_staker, stakingIndex, 1, ""); // mint NFT

        emit NFTMinted(stakingIndex, _staker);

        _stakingIndex = stakingIndex + 1;
    }

    function _burnNFT(address staker, uint256 id) internal {
        _burn(staker, id, 1); // burn NFT
        delete stakers[id];
        emit NFTBurned(id, staker);
    }
}