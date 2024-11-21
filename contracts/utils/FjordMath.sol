// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import  "solady/src/utils/FixedPointMathLib.sol";

library FjordMath {
    using FixedPointMathLib for uint256;

    /// @notice The scaling factor for all normalization/denormalization operations
    uint256 private constant SCALING_FACTOR = 18;

    /// @notice Normalize a value to the scaling factor
    /// @param value The value to normalize
    /// @param decimals The number of decimals of the value
    /// @dev No greater than check is required as > 18 decimals are not supported
    function normalize(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals < SCALING_FACTOR) {
            return value * (10 ** (SCALING_FACTOR - decimals));
        }
        return value;
    }

    /// @notice Denormalizes a value back to its original value
    /// @param value The value to denormalize
    /// @param decimals The number of decimals of the value
    /// @dev No greater than check is required as > 18 decimals are not supported. This function rounds up post division.
    function denormalizeUp(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals < SCALING_FACTOR) {
            return value.divUp(10 ** (SCALING_FACTOR - decimals));
        }
        return value;
    }

    /// @notice Denormalizes a value back to its original value
    /// @param value The value to denormalize
    /// @param decimals The number of decimals of the value
    /// @dev No greater than check is required as > 18 decimals are not supported. This function rounds down post division.
    function denormalizeDown(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals < SCALING_FACTOR) {
            return value / (10 ** (SCALING_FACTOR - decimals));
        }
        return value;
    }

    ///@notice Returns the minimum swap threshold required for a purchase to be valid.
    ///@dev This is used to prevent rounding errors when making swaps between tokens of varying decimals.
    function mandatoryMinimumSwapIn(
        uint8 shareDecimals,
        uint8 assetDecimals
    )
    public
    pure
    returns (uint256)
    {
        if (shareDecimals > assetDecimals) {
            return 10 ** (shareDecimals - assetDecimals + 2);
        } else {
            return 0;
        }
    }
}
