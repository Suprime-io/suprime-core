// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/labs/IWorkflow.sol";

contract LabsRegistry is Ownable{

    using EnumerableSet for EnumerableSet.AddressSet;

    struct Acceleration {
        address owner;
        address seedRaise;
        address publicRaise;
    }

    // proposalId => Acceleration
    mapping(uint256 => Acceleration) public accelerations;
    // proposalId => workflows
    mapping(uint256 => mapping(address => uint256) workflows) public accelerationWorkflows;

    event NewAcceleration(uint256 proposal);
    event NewWorkflowForAcceleration(uint256 proposal, address workflow, uint256 workflowInstance);

    error NotAuthorized();

    constructor() Ownable(msg.sender){

    }

    modifier byProposalOwner(uint256 _proposalId) {
        //TODO Check if done by the proposal's owner
        _;
    }

    function addAcceleration(uint256 _proposalId) byProposalOwner(_proposalId) public {
        Acceleration storage _acceleration = accelerations[_proposalId];
        _acceleration.owner = msg.sender;
        emit NewAcceleration(_proposalId);
    }

    /// @dev Owner of Acceleration can add (and create) a new Workflow from config
    function addWorkflowToAcceleration(uint256 _proposalId, address _workflow) byProposalOwner(_proposalId) public {
        Acceleration storage _acceleration = accelerations[_proposalId];
        if (_acceleration.owner != msg.sender)
            revert NotAuthorized();

        IWorkflow _workflowConfig = IWorkflow(_workflow);
        uint256 _workflowInstance = _workflowConfig.instantiate();
        accelerationWorkflows[_proposalId][_workflow] = _workflowInstance;
        emit NewWorkflowForAcceleration(_proposalId, _workflow, _workflowInstance);
    }


}
