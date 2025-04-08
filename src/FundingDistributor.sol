// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovernorCountingMultipleChoice} from "./GovernorCountingMultipleChoice.sol"; // For accessing proposalOptions
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title FundingDistributor
 * @notice Distributes received ETH based on the results of a GovernorCountingMultipleChoice proposal.
 * @dev This contract receives ETH and distributes it evenly among the recipients
 * corresponding to the top N winning options of a specified proposal.
 * The distribution is triggered by a call from the associated Timelock contract,
 * typically as the execution step of a successful governance proposal.
 */
contract FundingDistributor is Ownable {
    // Use GovernorCountingMultipleChoice interface directly to access specific functions
    GovernorCountingMultipleChoice public immutable governorCM;
    address public immutable timelock;

    struct OptionVote {
        uint8 index;
        uint256 votes;
    }

    /**
     * @notice Emitted when funds are successfully distributed.
     * @param proposalId The ID of the Governor proposal that triggered the distribution.
     * @param recipients The list of addresses that received funds.
     * @param amountPerRecipient The amount of ETH distributed to each recipient.
     */
    event FundsDistributed(uint256 indexed proposalId, address[] recipients, uint256 amountPerRecipient);

    /**
     * @notice Error: The caller is not the authorized Timelock contract.
     * @param caller The address that attempted the unauthorized call.
     */
    error FundingDistributor__UnauthorizedCaller(address caller);

    /**
     * @notice Error: The target proposal is not in a state where distribution is allowed (e.g., not Succeeded).
     * @param proposalId The ID of the proposal.
     * @param currentState The current state of the proposal.
     */
    error FundingDistributor__InvalidProposalState(uint256 proposalId, IGovernor.ProposalState currentState);

    /**
     * @notice Error: The length of the provided recipients array does not match the number of options in the proposal.
     * @param proposalId The ID of the proposal.
     * @param expectedLength The expected number of recipients (number of proposal options).
     * @param actualLength The actual number of recipients provided.
     */
    error FundingDistributor__RecipientArrayLengthMismatch(
        uint256 proposalId, uint8 expectedLength, uint256 actualLength
    );

    /**
     * @notice Error: The number of top winners requested (topN) is invalid (must be > 0 and <= option count).
     * @param topN The invalid number provided.
     * @param optionCount The total number of options for the proposal.
     */
    error FundingDistributor__InvalidTopN(uint8 topN, uint8 optionCount);

    /**
     * @notice Error: No winners were identified based on the votes and topN parameter.
     * @param proposalId The ID of the proposal.
     */
    error FundingDistributor__NoWinners(uint256 proposalId);

    /**
     * @notice Error: Failed to transfer ETH to a recipient.
     * @param recipient The address that failed to receive funds.
     * @param amount The amount that failed to transfer.
     */
    error FundingDistributor__TransferFailed(address recipient, uint256 amount);

    /**
     * @notice Sets the Governor and Timelock addresses.
     * @param _governor The address of the GovernorCountingMultipleChoice contract.
     * @param _timelock The address of the Timelock contract authorized to call `distribute`.
     * @param _initialOwner The address to set as the initial owner of this contract.
     */
    constructor(address _governor, address _timelock, address _initialOwner) Ownable(_initialOwner) {
        require(_governor != address(0), "FundingDistributor: invalid governor address");
        require(_timelock != address(0), "FundingDistributor: invalid timelock address");
        governorCM = GovernorCountingMultipleChoice(payable(_governor));
        timelock = _timelock;
    }

    /**
     * @notice Allows the contract to receive ETH.
     */
    receive() external payable {}

    /**
     * @notice Distributes the contract's ETH balance based on proposal results.
     * @dev MUST be called by the `timelock` address.
     * Fetches vote counts for the `proposalId` from the `governor`.
     * Identifies the `topN` winning options (including ties).
     * Distributes the contract's entire ETH balance evenly among the recipients
     * associated with the winning options via the `recipientsByOptionIndex` mapping.
     * @param proposalId The ID of the GovernorCountingMultipleChoice proposal.
     * @param topN The number of top winning options to consider for distribution.
     * @param recipientsByOptionIndex An array mapping proposal option index to recipient address.
     *                                The length MUST match the number of options in the proposal.
     *                                e.g., `recipientsByOptionIndex[0]` is the recipient for option 0.
     */
    function distribute(uint256 proposalId, uint8 topN, address[] memory recipientsByOptionIndex) external {
        // 1. Validate caller is timelock
        if (msg.sender != timelock) {
            revert FundingDistributor__UnauthorizedCaller(msg.sender);
        }

        // 2. Validate proposal state (Succeeded or Executed)
        IGovernor.ProposalState currentState = governorCM.state(proposalId);
        // Allow distribution if proposal succeeded OR if it was already executed
        // (in case this distribution is part of a multi-step execution)
        if (currentState != IGovernor.ProposalState.Succeeded && currentState != IGovernor.ProposalState.Executed) {
            revert FundingDistributor__InvalidProposalState(proposalId, currentState);
        }

        // 3. Fetch proposal options and validate recipientsByOptionIndex length
        (, uint8 optionCount) = governorCM.proposalOptions(proposalId);
        if (recipientsByOptionIndex.length != optionCount) {
            revert FundingDistributor__RecipientArrayLengthMismatch(
                proposalId, optionCount, recipientsByOptionIndex.length
            );
        }

        // 4. Validate topN
        if (topN == 0 || topN > optionCount) {
            revert FundingDistributor__InvalidTopN(topN, optionCount);
        }

        // 5. Fetch proposal option votes
        OptionVote[] memory optionVotes = new OptionVote[](optionCount);
        for (uint8 i = 0; i < optionCount; i++) {
            optionVotes[i] = OptionVote({index: i, votes: governorCM.proposalOptionVotes(proposalId, i)});
        }

        // 6. Identify top N winners (handle ties)
        // Simple bubble sort (descending) - acceptable for small option counts (max 10)
        for (uint8 i = 0; i < optionCount; i++) {
            for (uint8 j = i + 1; j < optionCount; j++) {
                if (optionVotes[j].votes > optionVotes[i].votes) {
                    OptionVote memory temp = optionVotes[i];
                    optionVotes[i] = optionVotes[j];
                    optionVotes[j] = temp;
                }
            }
        }

        // Determine the vote threshold (votes of the Nth option)
        uint256 voteThreshold = optionVotes[topN - 1].votes;

        // Collect winning recipients
        address[] memory winningRecipients = new address[](optionCount); // Max possible size
        uint256 winnerCount = 0;
        for (uint8 i = 0; i < optionCount; i++) {
            // Include if votes are above threshold, OR if votes equal threshold and we haven't reached N yet
            // This correctly handles ties at the Nth position.
            if (optionVotes[i].votes >= voteThreshold && optionVotes[i].votes > 0) {
                // Must have > 0 votes
                // Check if the recipient address is valid (not zero address)
                address recipient = recipientsByOptionIndex[optionVotes[i].index];
                if (recipient != address(0)) {
                    winningRecipients[winnerCount] = recipient;
                    winnerCount++;
                }
            } else {
                // Since the list is sorted, we can break early if votes are below threshold
                break;
            }
        }

        // Resize the winners array
        assembly {
            mstore(winningRecipients, winnerCount)
        }

        // 7. Check for winners
        if (winnerCount == 0) {
            revert FundingDistributor__NoWinners(proposalId);
        }

        // 8. Calculate amount per recipient
        uint256 totalBalance = address(this).balance;
        uint256 amountPerRecipient = totalBalance / winnerCount;

        // Ensure there's something to distribute
        if (amountPerRecipient == 0) {
            // Can happen if balance is less than winnerCount. Could revert or just emit 0 amount.
            // Let's emit 0 amount for simplicity.
            emit FundsDistributed(proposalId, winningRecipients, 0);
            return;
        }

        // 9. Distribute funds (check transfer success)
        for (uint256 i = 0; i < winnerCount; i++) {
            address recipient = winningRecipients[i];
            (bool success,) = payable(recipient).call{value: amountPerRecipient}("");
            if (!success) {
                revert FundingDistributor__TransferFailed(recipient, amountPerRecipient);
            }
        }

        // 10. Emit event
        emit FundsDistributed(proposalId, winningRecipients, amountPerRecipient);
    }

    // --- Helper functions (optional, potentially internal/private) ---
    // E.g., for sorting vote counts, identifying winners
}
