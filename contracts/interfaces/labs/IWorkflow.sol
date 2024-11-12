// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IWorkflow {

    function instantiate(string memory _nameTag) external returns (uint256);

}
