// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title IMultipleChoiceGovernor
 * @dev Interface expected by the evaluator to retrieve vote counts.
 * Any governor contract that wants to work with this evaluator must implement
 * the proposalAllVotes function to return the complete set of votes.
 */
interface IMultipleChoiceGovernor is IGovernor {
    /**
     * @dev Returns all vote counts for a proposal.
     * @param proposalId The ID of the proposal
     * @return An array of vote counts in the order:
     * [Against, For, Abstain, Option 0, Option 1, ..., Option N-1]
     */
    function proposalAllVotes(uint256 proposalId) external view returns (uint256[] memory);
}

/**
 * @title MultipleChoiceEvaluator
 * @dev Contract responsible for evaluating multiple choice proposal outcomes based on votes.
 * This separates the evaluation logic from the governor contract, allowing for different
 * evaluation strategies to be implemented and switched without modifying the governor.
 * Currently supports Plurality and Majority strategies.
 */
contract MultipleChoiceEvaluator is Ownable {
    using SafeCast for uint256;

    /**
     * @dev Enum representing the different evaluation strategies available.
     * - Plurality: Highest vote count wins (ties broken by lower index)
     * - Majority: Requires >50% of total option votes
     */
    enum EvaluationStrategy {
        Plurality, // Highest vote count wins (ties broken by lower index)
        Majority // Requires >50% of total option votes

    }

    /// @dev Reference to the governor contract that this evaluator works with
    IMultipleChoiceGovernor public governor;

    /// @dev The current evaluation strategy being used
    EvaluationStrategy public evaluationStrategy;

    /**
     * @dev Emitted when the evaluation strategy is changed.
     * @param newStrategy The new evaluation strategy
     */
    event EvaluationStrategySet(EvaluationStrategy newStrategy);

    /**
     * @dev Emitted when the governor address is updated.
     * @param newGovernor The address of the new governor
     */
    event GovernorUpdated(address newGovernor);

    /**
     * @dev Constructor for the MultipleChoiceEvaluator.
     * @param _governor The address of the governor contract
     */
    constructor(address _governor) Ownable(msg.sender) {
        governor = IMultipleChoiceGovernor(_governor);
        evaluationStrategy = EvaluationStrategy.Plurality; // Default strategy
    }

    /**
     * @dev Sets the evaluation strategy to use.
     * Only callable by the owner.
     * @param _strategy The evaluation strategy to set
     */
    function setEvaluationStrategy(EvaluationStrategy _strategy) public onlyOwner {
        require(uint8(_strategy) <= uint8(EvaluationStrategy.Majority), "MultipleChoiceEvaluator: unsupported strategy");
        evaluationStrategy = _strategy;
        emit EvaluationStrategySet(_strategy);
    }

    /**
     * @dev Updates the governor address.
     * Only callable by the owner.
     * @param _newGovernor The address of the new governor contract
     */
    function updateGovernor(address _newGovernor) public onlyOwner {
        governor = IMultipleChoiceGovernor(_newGovernor);
        emit GovernorUpdated(_newGovernor);
    }

    /**
     * @dev Evaluates a proposal based on the currently set strategy.
     * @param proposalId The ID of the proposal to evaluate
     * @return winningOption The winning option index or type(uint256).max if no winner
     */
    function evaluate(uint256 proposalId) public view returns (uint256 winningOption) {
        return _evaluate(proposalId, evaluationStrategy);
    }

    /**
     * @dev Evaluates a proposal based on a specified strategy.
     * @param proposalId The ID of the proposal to evaluate
     * @param strategy The evaluation strategy to use
     * @return winningOption The winning option index or type(uint256).max if no winner
     */
    function evaluate(uint256 proposalId, EvaluationStrategy strategy) public view returns (uint256 winningOption) {
        return _evaluate(proposalId, strategy);
    }

    /**
     * @dev Internal evaluation logic.
     * @param proposalId The ID of the proposal to evaluate
     * @param strategy The evaluation strategy to use
     * @return winningOption The winning option index or type(uint256).max if no winner
     */
    function _evaluate(uint256 proposalId, EvaluationStrategy strategy) internal view returns (uint256 winningOption) {
        uint256[] memory allVotes = governor.proposalAllVotes(proposalId);
        uint256 numOptions = allVotes.length - 3; // Total votes array length minus the 3 standard counts

        if (strategy == EvaluationStrategy.Plurality) {
            return _evaluatePlurality(allVotes, numOptions);
        } else if (strategy == EvaluationStrategy.Majority) {
            return _evaluateMajority(allVotes, numOptions);
        } else {
            revert("MultipleChoiceEvaluator: unsupported strategy");
        }
    }

    /**
     * @dev Plurality evaluation: Highest vote count wins. Ties broken by lowest index.
     * @param allVotes Array of vote counts [Against, For, Abstain, Option 0, Option 1, ...]
     * @param numOptions Number of multiple choice options
     * @return winningOption The winning option index or 0 if no votes cast
     */
    function _evaluatePlurality(uint256[] memory allVotes, uint256 numOptions)
        internal
        pure
        returns (uint256 winningOption)
    {
        uint256 maxVotes = 0;
        winningOption = 0; // Default to option 0 in case of 0 votes or if 0 wins

        for (uint256 i = 0; i < numOptions; i++) {
            uint256 currentOptionVotes = allVotes[3 + i];
            if (currentOptionVotes > maxVotes) {
                maxVotes = currentOptionVotes;
                winningOption = i;
            } else if (currentOptionVotes == maxVotes) {
                // Tie-breaking: keep the lower index
                // winningOption remains unchanged if the current index `i` is higher
            }
        }
        // If all options have 0 votes, winningOption remains 0.
    }

    /**
     * @dev Majority evaluation: Requires >50% of total *option* votes.
     * @param allVotes Array of vote counts [Against, For, Abstain, Option 0, Option 1, ...]
     * @param numOptions Number of multiple choice options
     * @return winningOption The winning option index or type(uint256).max if no majority
     */
    function _evaluateMajority(uint256[] memory allVotes, uint256 numOptions)
        internal
        pure
        returns (uint256 winningOption)
    {
        uint256 totalOptionVotes = 0;
        for (uint256 i = 0; i < numOptions; i++) {
            totalOptionVotes += allVotes[3 + i];
        }

        if (totalOptionVotes == 0) {
            return type(uint256).max; // No votes, no majority
        }

        uint256 majorityThreshold = totalOptionVotes / 2;

        for (uint256 i = 0; i < numOptions; i++) {
            if (allVotes[3 + i] > majorityThreshold) {
                return i; // Found the majority winner
            }
        }

        return type(uint256).max; // No majority found
    }
}
