// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title MockGovernorForFuzz
 * @notice A simplified mock that only provides function signatures for mocking
 * @dev Instead of inheriting from GovernorCountingMultipleChoice with all its complexity,
 *      this contract only implements the necessary function signatures that we'll mock in tests
 */
contract MockGovernorForFuzz {
    // Function signatures that match those in GovernorCountingMultipleChoice
    // We only need the signatures to be correct for vm.mockCall
    
    function state(uint256) external pure returns (IGovernor.ProposalState) {
        revert("MockGovernorForFuzz: state should be mocked");
    }
    
    function proposalOptions(uint256) external pure returns (string[] memory, uint8) {
        revert("MockGovernorForFuzz: proposalOptions should be mocked");
    }
    
    function proposalOptionVotes(uint256, uint8) external pure returns (uint256) {
        revert("MockGovernorForFuzz: proposalOptionVotes should be mocked");
    }
    
    // Add any missing functions that might be needed by FundingDistributor
    function proposalVotes(uint256) external pure returns (uint256, uint256, uint256) {
        revert("MockGovernorForFuzz: proposalVotes should be mocked");
    }
    
    function proposalAllVotes(uint256) external pure returns (uint256[] memory) {
        revert("MockGovernorForFuzz: proposalAllVotes should be mocked");
    }
} 