// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISuprimeStaking {
    event NFTMinted(uint256 indexed nftMintId, address indexed recipient);
    event NFTBurned(uint256 indexed tokenId, address indexed recipient);

    struct VestingInfo {
        uint256 tokenId; // NFT Id
        uint256 locked; // token amount
        uint256 claimed; // tokens claimed from vesting
    }

    function claim(uint256 _tokenId, uint256 _amount) external;
}
