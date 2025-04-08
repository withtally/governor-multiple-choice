// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovernorCountingMultipleChoice} from "./GovernorCountingMultipleChoice.sol"; // May only need interfaces/structs later

/**
 * @title FundingDistributor
 * @notice Distributes received ETH based on the results of a GovernorCountingMultipleChoice proposal.
 * @dev This contract receives ETH and distributes it evenly among the recipients
 * corresponding to the top N winning options of a specified proposal.
 * The distribution is triggered by a call from the associated Timelock contract,
 * typically as the execution step of a successful governance proposal.
 */
contract FundingDistributor is Ownable {
    IGovernor public immutable governor;
    address public immutable timelock;

    /**
     * @notice Emitted when funds are successfully distributed.
     * @param proposalId The ID of the Governor proposal that triggered the distribution.
     * @param recipients The list of addresses that received funds.
     * @param amountPerRecipient The amount of ETH distributed to each recipient.
     */
    event FundsDistributed(
        uint256 indexed proposalId,
        address[] recipients,
        uint256 amountPerRecipient
    );

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
    error FundingDistributor__InvalidProposalState(
        uint256 proposalId,
        IGovernor.ProposalState currentState
    );

    /**
     * @notice Error: The length of the provided recipients array does not match the number of options in the proposal.
     * @param proposalId The ID of the proposal.
     * @param expectedLength The expected number of recipients (number of proposal options).
     * @param actualLength The actual number of recipients provided.
     */
    error FundingDistributor__RecipientArrayLengthMismatch(
        uint256 proposalId,
        uint8 expectedLength,
        uint256 actualLength
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
    constructor(address _governor, address _timelock, address _initialOwner)
        Ownable(_initialOwner)
    {
        require(_governor != address(0), "FundingDistributor: invalid governor address");
        require(_timelock != address(0), "FundingDistributor: invalid timelock address");
        governor = IGovernor(_governor);
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
    function distribute(
        uint256 proposalId,
        uint8 topN,
        address[] memory recipientsByOptionIndex
    ) external {
        // --- TODO: Implementation --- //
        // 1. Validate caller is timelock
        // 2. Validate proposal state (Succeeded)
        // 3. Validate recipientsByOptionIndex length
        // 4. Validate topN
        // 5. Fetch proposal option votes
        // 6. Identify top N winners (handle ties)
        // 7. Check for winners
        // 8. Calculate amount per recipient
        // 9. Distribute funds (check transfer success)
        // 10. Emit event
    }

    // --- Helper functions (optional, potentially internal/private) ---
    // E.g., for sorting vote counts, identifying winners

} 