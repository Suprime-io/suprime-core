// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library CustomErrors {
    // custom error
    error Unauthorized(address caller);

    error InvalidInput(uint256 value);

    error WithdrawNotReady(address user);

    error InvalidSignature();
    error ExceedMaxLimit(uint256 value);
    error InsufficientLiquidity(uint256 liquidity);

    error TransferNotAllowed();

    function unauthorizedRevert() internal view {
        revert Unauthorized(msg.sender);
    }

}
