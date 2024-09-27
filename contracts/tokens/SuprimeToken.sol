// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SuprimeToken is ERC20Permit {
    uint256 public constant TOTAL_SUPPLY = 1 * (10 ** 9) * (10 ** 18);

    constructor(
        address tokenReceiver
    ) ERC20Permit("Suprime") ERC20("Suprime", "SUPRIME") {
         _mint(tokenReceiver, TOTAL_SUPPLY);
    }
}
