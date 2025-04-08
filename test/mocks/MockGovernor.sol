// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorCountingMultipleChoice} from "src/GovernorCountingMultipleChoice.sol";
import {MultipleChoiceEvaluator} from "src/MultipleChoiceEvaluator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // Needed if mocking functions with onlyOwner

/**
 * @title MockGovernor
 * @dev Mock contract for GovernorCountingMultipleChoice to isolate evaluator testing.
 * Simulates the functions required by MultipleChoiceEvaluator.
 */
contract MockGovernor is
    Ownable(msg.sender) // Inherit Ownable if needed for mocks
{
    // Mapping to store mock return values for proposalAllVotes
    // proposalId => vote counts array (Against, For, Abstain, Opt0, Opt1, ...)
    mapping(uint256 => uint256[]) internal _mockProposalAllVotes;

    // Store the evaluator address
    address public evaluatorAddress;

    // Event to mimic evaluator setting (optional, for debugging/verification)
    event EvaluatorSet(address evaluator);

    /**
     * @dev Simulates the proposalAllVotes function of the Governor.
     * Returns the pre-configured vote counts for a given proposalId.
     */
    function proposalAllVotes(uint256 proposalId) public view virtual returns (uint256[] memory) {
        return _mockProposalAllVotes[proposalId];
    }

    /**
     * @dev Sets the mock return value for proposalAllVotes for a specific proposalId.
     * Only callable by the test contract (or owner if permissions enforced).
     */
    function setProposalAllVotes(uint256 proposalId, uint256[] memory votes) public {
        // In a real scenario, you might want Ownable control here,
        // but for simple testing, public is fine if deployed only by the test harness.
        _mockProposalAllVotes[proposalId] = votes;
    }

    /**
     * @dev Sets the address of the evaluator contract.
     * Mimics governor behavior where evaluator might be set or updated.
     */
    function setEvaluator(address _evaluator) public {
        // Similar permission consideration as setProposalAllVotes
        evaluatorAddress = _evaluator;
        emit EvaluatorSet(_evaluator);
    }

    // Add other mocked functions here if the Evaluator needs them later
}
