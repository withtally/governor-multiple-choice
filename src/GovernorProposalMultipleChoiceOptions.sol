// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract GovernorProposalMultipleChoiceOptions {
    // Event emitted when options are added to a proposal
    event ProposalOptionsCreated(uint256 proposalId, string[] options);

    // Struct to store proposal options
    struct ProposalOptions {
        string[] options;
        uint8 optionCount; // Explicit count to prevent re-calculating .length
    }

    // Mapping from proposalId to its options
    mapping(uint256 => ProposalOptions) internal _proposalOptions;

    // Constant for maximum options allowed (adjust as needed)
    uint8 public constant MAX_OPTIONS = 10;
    uint8 public constant MIN_OPTIONS = 2;


    /**
     * @dev Returns the options associated with a proposal.
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