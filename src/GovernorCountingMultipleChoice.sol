// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TODO: Verify NatSpec documentation accurately reflects implementation and tested behaviors.

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorProposalMultipleChoiceOptions} from "./GovernorProposalMultipleChoiceOptions.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernorCountingMultipleChoice
 * @dev Extension of {Governor} for multiple choice voting.
 * Integrates functionalities from:
 * - GovernorSettings: Manages voting delay, period, and proposal threshold.
 * - GovernorCountingSimple: Standard vote counting (For, Against, Abstain).
 * - GovernorVotes: Integrates with ERC20Votes or ERC721Votes.
 * - GovernorVotesQuorumFraction: Standard quorum calculation.
 * - GovernorTimelockControl: Integrates with TimelockController for execution.
 * - GovernorProposalMultipleChoiceOptions: Adds storage for proposal options.
 * - Ownable: Adds ownership functionality.
 */
contract GovernorCountingMultipleChoice is
    Context,
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    GovernorProposalMultipleChoiceOptions,
    Ownable
{
    using SafeCast for uint256;

    // Mapping to store votes per option for each proposal
    mapping(uint256 => mapping(uint8 => uint256)) internal _proposalOptionVotesCount; // Store just the vote count per option

    // Address of the evaluator contract
    address public evaluator; // Public state variable for evaluator address

    /**
     * @dev Emitted when the evaluator address is set or updated.
     * @param newEvaluator Address of the new evaluator contract
     */
    event EvaluatorSet(address newEvaluator);

    /**
     * @dev Constructor for the GovernorCountingMultipleChoice contract.
     * @param _token The token used for voting (ERC20Votes or ERC721Votes)
     * @param _timelock The timelock controller for proposal execution
     * @param _name The name of the governor instance
     */
    constructor(
        IVotes _token,
        TimelockController _timelock,
        string memory _name
    ) 
        Governor(_name) 
        GovernorSettings(1, 4, 0) 
        GovernorVotes(_token) 
        GovernorVotesQuorumFraction(4) 
        GovernorTimelockControl(_timelock) 
        Ownable(msg.sender) // Call Ownable constructor
    {}

    /**
     * @dev Sets or updates the address of the evaluator contract.
     * Only callable by the owner.
     * @param _newEvaluator The address of the new evaluator contract
     */
    function setEvaluator(address _newEvaluator) public onlyOwner {
        evaluator = _newEvaluator;
        emit EvaluatorSet(_newEvaluator);
    }

    // --- Diamond Inheritance Resolution ---

    /**
     * @dev Returns the executor address used for proposal execution.
     * Resolves the diamond inheritance between Governor and GovernorTimelockControl.
     * @return The executor address (the timelock controller)
     */
    function _executor() internal view virtual override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor(); // Use Timelock's executor by default
    }

    /**
     * @dev Returns the proposal threshold required for creating new proposals.
     * Resolves the diamond inheritance between Governor and GovernorSettings.
     * @return The proposal threshold (minimum votes required to create a proposal)
     */
    function proposalThreshold() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold(); // Use GovernorSettings' threshold
    }

    // --- Overridden Governor Core Functions ---

    /**
     * @dev See {IGovernor-propose}.
     * Standard proposal creation without multiple choice options.
     * @param targets The addresses of the contracts to call
     * @param values The ETH values to send with each call
     * @param calldatas The calldata to send with each call
     * @param description A description of the proposal
     * @return proposalId The ID of the newly created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(Governor) returns (uint256 proposalId) {
        proposalId = super.propose(targets, values, calldatas, description);
    }

    /**
     * @dev Overload for proposing with multiple choice options.
     * @param targets The addresses of the contracts to call
     * @param values The ETH values to send with each call
     * @param calldatas The calldata to send with each call
     * @param description A description of the proposal
     * @param options The array of option descriptions for the multiple choice proposal
     * @return proposalId The ID of the newly created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        string[] memory options
    ) public virtual returns (uint256 proposalId) {
        uint256 numOptions = options.length;
        require(numOptions >= MIN_OPTIONS, "Governor: invalid option count (too few)");
        require(numOptions <= MAX_OPTIONS, "Governor: invalid option count (too many)");
        proposalId = this.propose(targets, values, calldatas, description);
        _storeProposalOptions(proposalId, options);
    }

    /**
     * @dev See {IGovernor-state}.
     * Returns the current state of a proposal.
     * @param proposalId The ID of the proposal
     * @return The current ProposalState
     */
    function state(uint256 proposalId) public view virtual override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     * Returns the delay before voting on a proposal may start.
     * @return The voting delay in blocks
     */
    function votingDelay() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     * Returns the period during which votes can be cast.
     * @return The voting period in blocks
     */
    function votingPeriod() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @dev See {IGovernor-quorum}.
     * Returns the minimum number of votes required for a proposal to succeed.
     * @param blockNumber The block number to get the quorum at
     * @return The minimum number of votes required for quorum
     */
    function quorum(uint256 blockNumber) public view virtual override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    /**
     * @dev See {IGovernor-getVotes}.
     * Returns the voting power of an account at a specific block number.
     * @param account The address to get voting power for
     * @param blockNumber The block number to get the votes at
     * @return The voting power of the account at the given block
     */
    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return super.getVotes(account, blockNumber);
    }

    // --- Overridden Timelock Control Functions ---

    /**
     * @dev Returns whether a proposal needs to be queued through the timelock.
     * @param proposalId The ID of the proposal
     * @return True if the proposal needs queuing, false otherwise
     */
    function proposalNeedsQueuing(uint256 proposalId) public view virtual override(Governor, GovernorTimelockControl) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @dev Queues a proposal's operations through the timelock controller.
     * @param proposalId The ID of the proposal
     * @param targets The addresses of the contracts to call
     * @param values The ETH values to send with each call
     * @param calldatas The calldata to send with each call
     * @param descriptionHash The hash of the proposal description
     * @return The timestamp at which the proposal will be ready for execution
     */
    function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal virtual override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Executes a proposal's operations through the timelock controller.
     * @param proposalId The ID of the proposal
     * @param targets The addresses of the contracts to call
     * @param values The ETH values to send with each call
     * @param calldatas The calldata to send with each call
     * @param descriptionHash The hash of the proposal description
     */
    function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal virtual override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Cancels a proposal and its queued operations.
     * @param targets The addresses of the contracts to call
     * @param values The ETH values to send with each call
     * @param calldatas The calldata to send with each call
     * @param descriptionHash The hash of the proposal description
     * @return The ID of the canceled proposal
     */
    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal virtual override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    // --- Overridden Counting Functions ---

    /**
     * @dev Counts a vote on a proposal.
     * Overrides the standard counting method to add support for multiple choice options.
     * @param proposalId The ID of the proposal
     * @param account The address of the voter
     * @param support The standard support value (0=Against, 1=For, 2=Abstain)
     * @param weight The voting weight (typically token balance at snapshot)
     * @param params Additional parameters, used for option index in multiple choice votes
     * @return The weight that was counted
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual override(Governor, GovernorCountingSimple) returns (uint256) {
        // Call GovernorCountingSimple implementation first
        uint256 countedWeight = super._countVote(proposalId, account, support, weight, params);

        uint8 optionIndex = type(uint8).max;
        if (params.length == 1) {
            optionIndex = uint8(params[0]);
        }
        (, uint8 optionCount) = proposalOptions(proposalId);
        if (optionIndex < optionCount) {
            require(optionCount > 0, "Governor: Cannot vote for option on std proposal");
            require(support == 1, "Governor: Invalid support for option vote (must be 1)");
            _proposalOptionVotesCount[proposalId][optionIndex] += weight;
        }
        return countedWeight; // Return value from super call
    }

    /**
     * @dev Casts a vote on a proposal.
     * Overridden to pass empty params by default for standard votes.
     * @param proposalId The ID of the proposal
     * @param account The address of the voter
     * @param support The support value (0=Against, 1=For, 2=Abstain)
     * @param reason The reason for the vote (optional)
     * @return The weight of the cast vote
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual override returns (uint256) {
         return _internalCastVote(proposalId, account, support, reason, "");
     }

    /**
     * @dev Internal cast vote logic that includes params.
     * Called by both standard castVote and castVoteWithOption.
     * @param proposalId The ID of the proposal
     * @param account The address of the voter
     * @param support The support value (0=Against, 1=For, 2=Abstain)
     * @param reason The reason for the vote (optional)
     * @param params Additional parameters, used for option index
     * @return The weight of the cast vote
     */
    function _internalCastVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual returns (uint256) {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");
        uint256 snapshot = proposalSnapshot(proposalId);
        uint256 weight = getVotes(account, snapshot);

        // Call our overridden _countVote
        _countVote(proposalId, account, support, weight, params);
        // Emit events matching GovernorVotes
        emit VoteCast(account, proposalId, support, weight, reason);
        emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        return weight;
    }

    // --- New Functions for Multiple Choice ---

    /**
     * @dev Cast a vote for a specific option in a multiple choice proposal.
     * Encodes optionIndex into params for the internal cast vote function.
     * @param proposalId The ID of the proposal
     * @param optionIndex The index of the option to vote for
     * @return balance The weight of the cast vote
     */
    function castVoteWithOption(uint256 proposalId, uint8 optionIndex) public virtual returns (uint256 balance) {
        address voter = _msgSender();
        (, uint8 optionCount) = proposalOptions(proposalId);
        require(optionCount > 0, "Governor: standard proposal, use castVote");
        require(optionIndex < optionCount, "Governor: invalid option index");
        uint8 support = 1; // Convention: support = 1 for choosing an option
        bytes memory params = abi.encodePacked(optionIndex);
        balance = _internalCastVote(proposalId, voter, support, "", params);
    }

    /**
     * @dev Returns the vote counts for a specific option.
     * @param proposalId The ID of the proposal
     * @param optionIndex The index of the option to get votes for
     * @return optionVotes The number of votes for the specified option
     */
    function proposalOptionVotes(uint256 proposalId, uint8 optionIndex) public view virtual returns (uint256 optionVotes) {
        (, uint8 optionCount) = proposalOptions(proposalId);
        require(optionIndex < optionCount, "Governor: invalid option index");
        return _proposalOptionVotesCount[proposalId][optionIndex];
    }

    /**
     * @dev Returns all vote counts for a proposal.
     * The array order is: Against, For, Abstain, Option 0, Option 1, ..., Option N-1.
     * @param proposalId The ID of the proposal
     * @return allVotes Array containing all vote counts
     */
    function proposalAllVotes(uint256 proposalId) public view virtual returns (uint256[] memory allVotes) {
        // Get standard votes using the public function from GovernorCountingSimple
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId); 
        
        // Get multiple choice options
        (, uint8 optionCount) = proposalOptions(proposalId);

        uint256 arraySize = 3 + optionCount; // 3 standard + number of options
        allVotes = new uint256[](arraySize);

        allVotes[0] = againstVotes;
        allVotes[1] = forVotes;
        allVotes[2] = abstainVotes;

        for (uint8 i = 0; i < optionCount; i++) {
            allVotes[3 + i] = _proposalOptionVotesCount[proposalId][i];
        }
    }

    // --- Required Supports Interface --- 

    /**
     * @dev See {IERC165-supportsInterface}.
     * @param interfaceId The interface ID to check
     * @return True if the contract supports the interface
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

} 