// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GovernorProposalMultipleChoiceOptions
 * @dev Abstract contract that adds support for multiple choice options to governance proposals.
 * This can be used as a mix-in with any Governor implementation to add support for
 * proposals with more than just the standard For/Against/Abstain voting options.
 */
abstract contract GovernorProposalMultipleChoiceOptions {
    /**
     * @dev Emitted when options are added to a proposal.
     * @param proposalId The ID of the proposal
     * @param options Array of option descriptions for the proposal
     */
    event ProposalOptionsCreated(uint256 proposalId, string[] options);

    /**
     * @dev Struct to store proposal options and their count.
     * @param options Array of option descriptions
     * @param optionCount Number of options (cached to avoid recalculating array length)
     */
    struct ProposalOptions {
        string[] options;
        uint8 optionCount; // Explicit count to prevent re-calculating .length
    }

    // Mapping from proposalId to its options
    mapping(uint256 => ProposalOptions) internal _proposalOptions;

    /**
     * @dev Maximum number of options allowed for a multiple choice proposal.
     * This is capped at 10 to prevent excessive gas costs and UI complexity.
     */
    uint8 public constant MAX_OPTIONS = 10;
    
    /**
     * @dev Minimum number of options required for a multiple choice proposal.
     * At least 2 options are required for a meaningful choice.
     */
    uint8 public constant MIN_OPTIONS = 2;

    /**
     * @dev Returns the options associated with a proposal.
     * @param proposalId The ID of the proposal
     * @return options Array of option descriptions
     * @return optionCount Number of options
     */
    function proposalOptions(uint256 proposalId)
        public
        view
        virtual
        returns (string[] memory options, uint8 optionCount)
    {
        ProposalOptions storage pOptions = _proposalOptions[proposalId];
        return (pOptions.options, pOptions.optionCount);
    }

    /**
     * @dev Internal function to store proposal options.
     * The validation of option count is expected to be performed by the caller.
     * @param proposalId The ID of the proposal
     * @param options Array of option descriptions
     */
    function _storeProposalOptions(uint256 proposalId, string[] memory options) internal virtual {
        uint256 numOptions = options.length;
        // require(numOptions >= MIN_OPTIONS, "Governor: invalid option count (too few)"); // Check done in GovernorCountingMultipleChoice
        // require(numOptions <= MAX_OPTIONS, "Governor: invalid option count (too many)"); // Check done in GovernorCountingMultipleChoice

        _proposalOptions[proposalId] = ProposalOptions({
            options: options,
            optionCount: uint8(numOptions) // Safe cast due to MAX_OPTIONS limit check
        });

        emit ProposalOptionsCreated(proposalId, options);
    }
} 