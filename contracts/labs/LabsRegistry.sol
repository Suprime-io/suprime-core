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
    // proposalId => workflows => instances
    mapping(uint256 => mapping(address => uint256) workflows) public accelerationWorkflows;

    event NewAcceleration(uint256 proposal);
    event AddedSeedRaise(uint256 proposal, address raise);
    event AddedPublicRaise(uint256 proposal, address raise);
    event NewWorkflowForAcceleration(uint256 proposal, address workflow, uint256 workflowInstance);

    error NotAuthorized();

    constructor() Ownable(msg.sender){

    }

    modifier byProposalOwner(uint256 _proposalId) {
        //TODO Check if done by the proposal's owner
        _;
    }

    function addSeedRaise(uint256 _proposalId, address _raise) byProposalOwner(_proposalId) public {
        Acceleration storage _acceleration = accelerations[_proposalId];
        _acceleration.seedRaise = _raise;
        emit AddedSeedRaise(_proposalId, _raise);
    }

    function addPublicRaise(uint256 _proposalId, address _raise) byProposalOwner(_proposalId) public {
        Acceleration storage _acceleration = accelerations[_proposalId];
        _acceleration.publicRaise = _raise;
        emit AddedPublicRaise(_proposalId, _raise);
    }

    function addAcceleration(uint256 _proposalId) byProposalOwner(_proposalId) public {
        Acceleration storage _acceleration = accelerations[_proposalId];
        _acceleration.owner = msg.sender;
        emit NewAcceleration(_proposalId);
    }

    /// @dev Owner of Acceleration can add (and create) a new Workflow from config
    function addWorkflowsToAcceleration(uint256 _proposalId, address[] calldata _workflows, string[] calldata _names) byProposalOwner(_proposalId) public {
        Acceleration storage _acceleration = accelerations[_proposalId];
        if (_acceleration.owner != msg.sender)
            revert NotAuthorized();

        for (uint256 i; i < _workflows.length; i++) {
            address _workflow = _workflows[i];
            string memory _name = _names[i];
            IWorkflow _workflowConfig = IWorkflow(_workflow);
            uint256 _workflowInstance = _workflowConfig.instantiate(_name);
            accelerationWorkflows[_proposalId][_workflow] = _workflowInstance;
            emit NewWorkflowForAcceleration(_proposalId, _workflow, _workflowInstance);
        }
    }


}
