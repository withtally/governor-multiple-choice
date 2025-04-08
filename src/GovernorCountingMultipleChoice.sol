// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
 */
contract GovernorCountingMultipleChoice is
    Context,
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    GovernorProposalMultipleChoiceOptions
{
    using SafeCast for uint256;

    // Mapping to store votes per option for each proposal
    mapping(uint256 => mapping(uint8 => uint256)) internal _proposalOptionVotesCount; // Store just the vote count per option

    /**
     * @dev Constructor.
     */
    constructor(
        IVotes _token,
        TimelockController _timelock,
        string memory _name
    ) Governor(_name) GovernorSettings(1, 4, 0) GovernorVotes(_token) GovernorVotesQuorumFraction(4) GovernorTimelockControl(_timelock) {}

    // --- Diamond Inheritance Resolution ---

    function _executor() internal view virtual override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor(); // Use Timelock's executor by default
    }

    function proposalThreshold() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold(); // Use GovernorSettings' threshold
    }

    // --- Overridden Governor Core Functions ---

    /**
     * @dev See {IGovernor-propose}.
     * Adds support for multiple choice options.
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
     */
    function state(uint256 proposalId) public view virtual override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     */
    function votingDelay() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @dev See {IGovernor-quorum}.
     */
    function quorum(uint256 blockNumber) public view virtual override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    /**
     * @dev See {IGovernor-getVotes}.
     */
    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return super.getVotes(account, blockNumber);
    }

    // --- Overridden Timelock Control Functions ---

    function proposalNeedsQueuing(uint256 proposalId) public view virtual override(Governor, GovernorTimelockControl) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal virtual override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal virtual override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal virtual override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    // --- Overridden Counting Functions --- (Add option counting later)

    /**
     * @dev Override _countVote to add logic for multiple choice options.
     * Standard votes are handled by super._countVote.
     * MC votes also call super._countVote (to update receipts) then update option counts.
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
     * @dev Override _castVote to pass empty params by default for standard votes.
     * This ensures it matches the signature required by the Governor._castVote call within.
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
     * Renamed from _castVote to avoid conflicting override signature with the one above.
     * This function is called by both standard castVote and castVoteWithOption.
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
     */
    function proposalOptionVotes(uint256 proposalId, uint8 optionIndex) public view virtual returns (uint256 optionVotes) {
        (, uint8 optionCount) = proposalOptions(proposalId);
        require(optionIndex < optionCount, "Governor: invalid option index");
        return _proposalOptionVotesCount[proposalId][optionIndex];
    }

    // --- Required Supports Interface --- 
    // (Needed because Governor is abstract)

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

} 