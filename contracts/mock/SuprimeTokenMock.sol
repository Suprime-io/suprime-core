// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../tokens/SuprimeToken.sol";

contract SuprimeTokenMock is SuprimeToken {

    constructor() SuprimeToken(msg.sender) {}

    function mintArbitrary(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
