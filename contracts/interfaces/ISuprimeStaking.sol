// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IStaking.sol";

interface ISuprimeStaking {
    event NFTMinted(uint256 indexed nftMintId, address indexed recipient);
    event NFTBurned(uint256 indexed tokenId, address indexed recipient);

    struct VestingInfo {
        uint256 tokenId; // NFT Id
        uint256 locked; // token amount
        uint256 claimed; // tokens claimed from vesting
    }

    struct StakeForParams {
        uint256 amountSuprime; // amount of SUPRIME token to stake
        uint256 stakingPositionInput; // locking period or tokenid of an existnece nft
        address user; // given user of stake
        uint8 stakingPosition; // new native staking pool staker, or has an existence nft
    }

    function claim(uint256 _tokenId, uint256 _amount) external;
}
