// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

abstract contract FjordConstants {
    //-----------------------------------------------------------------------------------------------------------------------------------------
    // BASE POOL OFFSETS ONLY
    //-----------------------------------------------------------------------------------------------------------------------------------------

    uint256 internal constant OWNER_OFFSET = 0; // Increment offset by 20
    uint256 internal constant SHARE_TOKEN_OFFSET = 20; // Increment offset by 20
    uint256 internal constant ASSET_TOKEN_OFFSET = 40; // Increment offset by 20
    uint256 internal constant FEE_RECIPIENT_OFFSET = 60; // Increment offset by 20
    uint256 internal constant DELEGATE_SIGNER_OFFSET = 80; // Increment offset by 20
    uint256 internal constant SHARES_FOR_SALE_OFFSET = 100; // Increment offset by 32
    uint256 internal constant MINIMUM_TOKENS_FOR_SALE_OFFSET = 132; // Increment offset by 32
    uint256 internal constant MAXIMUM_TOKENS_PER_USER_OFFSET = 164; // Increment offset by 32
    uint256 internal constant MINIMUM_TOKENS_PER_USER_OFFSET = 196; // Increment offset by 32
    uint256 internal constant SWAP_FEE_WAD_OFFSET = 228; // Increment offset by 8
    uint256 internal constant PLATFORM_FEE_WAD_OFFSET = 236; // Increment offset by 8
    uint256 internal constant SALE_START_OFFSET = 244; // Increment offset by 5
    uint256 internal constant SALE_END_OFFSET = 249; // Increment offset by 5
    uint256 internal constant REDEMPTION_DELAY_OFFSET = 254; // Increment offset by 5
    uint256 internal constant VEST_END_OFFSET = 259; // Increment offset by 5
    uint256 internal constant VEST_CLIFF_OFFSET = 264; // Increment offset by 5
    uint256 internal constant SHARE_TOKEN_DECIMALS_OFFSET = 269; // Increment offset by 1
    uint256 internal constant ASSET_TOKEN_DECIMALS_OFFSET = 270; // Increment offset by 1
    uint256 internal constant ANTISNIPE_ENABLED_OFFSET = 271; // Increment offset by 1
    uint256 internal constant WHITELIST_MERKLE_ROOT_OFFSET = 272; // Increment offset by 32

    //-----------------------------------------------------------------------------------------------------------------------------------------
    // FIXED PRICE OFFSETS ONLY
    //-----------------------------------------------------------------------------------------------------------------------------------------

    uint256 internal constant ASSETS_PER_TOKEN_OFFSET = 304; // Increment offset by 32
    uint256 internal constant TIER_DATA_LENGTH_OFFSET = 336; // Increment offset by 32
    uint256 internal constant TIERS_OFFSET = 368; // Increment offset by 32

    uint256 internal constant EMPTY_TIER_ARRAY_OFFSET = 64; // Size of an empty encoded Tier[] struct
    uint256 internal constant TIER_BASE_OFFSET = 128; // Size of an encoded Tier struct (uint256,uint256,uint256,uint256)

    //-----------------------------------------------------------------------------------------------------------------------------------------
    //OVERFLOW OFFSETS ONLY
    //-----------------------------------------------------------------------------------------------------------------------------------------

    uint256 internal constant ASSET_HARD_CAP_OFFSET = 304; // Increment offset by 32
}
