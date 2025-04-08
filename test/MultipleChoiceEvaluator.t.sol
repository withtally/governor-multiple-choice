// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MultipleChoiceEvaluator} from "src/MultipleChoiceEvaluator.sol";
import {GovernorCountingMultipleChoice} from "src/GovernorCountingMultipleChoice.sol"; // Import governor for context if needed later
import {MockGovernor} from "./mocks/MockGovernor.sol"; // Will create this mock shortly
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MultipleChoiceEvaluatorTest
 * @dev Test contract for MultipleChoiceEvaluator
 */
contract MultipleChoiceEvaluatorTest is Test {
    MultipleChoiceEvaluator internal evaluator;
    MockGovernor internal mockGovernor; // Using a mock to isolate evaluator logic

    function setUp() public {
        // Deploy a mock governor first
        mockGovernor = new MockGovernor();
        
        // Deploy the evaluator, linking it to the mock governor
        evaluator = new MultipleChoiceEvaluator(address(mockGovernor));
        
        // Set the evaluator address in the mock governor
        mockGovernor.setEvaluator(address(evaluator));
    }

    // --- PLURALITY TESTS --- // TODO: Gas snapshot for evaluate (Plurality)

    function test_Plurality_Basic_HighestVoteWins() public {
        // Mock vote counts: Option 2 has the most votes
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 100; // Against
        votes[1] = 500; // For (sum of options)
        votes[2] = 50;  // Abstain
        votes[3] = 150; // Option 0
        votes[4] = 100; // Option 1
        votes[5] = 250; // Option 2 (Highest)

        // Set the mock return value for proposalAllVotes
        mockGovernor.setProposalAllVotes(1, votes);
        
        // Set the evaluation strategy in the evaluator
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);

        // Evaluate the proposal
        uint256 winningOption = evaluator.evaluate(1); // proposalId 1

        // Assert that Option 2 wins in Plurality
        assertEq(winningOption, 2, "Winning option should be 2 (Plurality)");
    }

    // --- Test for Plurality with Tied Votes ---
    function test_Plurality_TiedVotes_ReturnsLowestIndex() public {
        // Mock vote counts: Option 0 and Option 2 are tied for the highest
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 100; 
        votes[1] = 600; // For (sum of options)
        votes[2] = 50;  
        votes[3] = 250; // Option 0 (Tied Highest)
        votes[4] = 100; // Option 1
        votes[5] = 250; // Option 2 (Tied Highest)

        mockGovernor.setProposalAllVotes(2, votes); // Use proposalId 2
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);

        uint256 winningOption = evaluator.evaluate(2); 

        // In case of a tie, the lowest index of the tied options should win
        assertEq(winningOption, 0, "Winning option should be 0 (Lowest index in tie)");
    }
    
    // --- Test for Plurality with No Votes Cast ---
    function test_Plurality_NoVotes_ReturnsZero() public {
        // Mock vote counts: All zero
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        // All elements default to 0

        mockGovernor.setProposalAllVotes(3, votes); // Use proposalId 3
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);

        uint256 winningOption = evaluator.evaluate(3); 

        // If no votes are cast for any option, should return 0 (representing no winning option or index 0 if it exists)
        // Let's assume convention is 0 means Option 0 wins if it exists and has 0 votes along with others.
        assertEq(winningOption, 0, "Winning option should be 0 when no votes are cast");
    }

    // --- Test for Plurality with Single Option Receiving Votes ---
     function test_Plurality_SingleOptionVotes_Wins() public {
        // Mock vote counts: Only Option 1 has votes
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 0; 
        votes[1] = 100; // For (sum of options)
        votes[2] = 0;  
        votes[3] = 0;   // Option 0
        votes[4] = 100; // Option 1 (Only one with votes)
        votes[5] = 0;   // Option 2

        mockGovernor.setProposalAllVotes(4, votes); // Use proposalId 4
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);

        uint256 winningOption = evaluator.evaluate(4); 

        assertEq(winningOption, 1, "Winning option should be 1 (Single option with votes)");
    }
    
     // --- MAJORITY TESTS --- // TODO: Gas snapshot for evaluate (Majority)

    function test_Majority_ClearMajority_Wins() public {
        // Mock vote counts: Option 0 has > 50% of total option votes (300 / (100+50+300) = 300/450 > 0.5)
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 10; 
        votes[1] = 450; // For (sum of options)
        votes[2] = 20;  
        votes[3] = 300; // Option 0 (Majority)
        votes[4] = 100; // Option 1
        votes[5] = 50;  // Option 2

        mockGovernor.setProposalAllVotes(5, votes); // Use proposalId 5
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority);

        uint256 winningOption = evaluator.evaluate(5); 

        assertEq(winningOption, 0, "Winning option should be 0 (Majority)");
    }

    function test_Majority_NoClearMajority_ReturnsMaxUint() public {
        // Mock vote counts: No option has > 50% (Highest is 250 / (150+100+250) = 250/500 = 0.5, not > 0.5)
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 100; 
        votes[1] = 500; // For (sum of options)
        votes[2] = 50;  
        votes[3] = 150; // Option 0
        votes[4] = 100; // Option 1
        votes[5] = 250; // Option 2 (Highest, but not majority)

        mockGovernor.setProposalAllVotes(6, votes); // Use proposalId 6
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority);

        uint256 winningOption = evaluator.evaluate(6); 

        // If no majority, should return type(uint256).max
        assertEq(winningOption, type(uint256).max, "Should return max uint when no majority");
    }

    function test_Majority_ExactFiftyPercent_ReturnsMaxUint() public {
        // Mock vote counts: Option 0 has exactly 50% (250 / (250+150+100) = 250/500 = 0.5)
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 10; 
        votes[1] = 500; // For (sum of options)
        votes[2] = 20;  
        votes[3] = 250; // Option 0 (Exactly 50%)
        votes[4] = 150; // Option 1
        votes[5] = 100; // Option 2

        mockGovernor.setProposalAllVotes(7, votes); // Use proposalId 7
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority);

        uint256 winningOption = evaluator.evaluate(7); 

        // Exactly 50% is not a majority (>50%)
        assertEq(winningOption, type(uint256).max, "Should return max uint for exact 50%");
    }

    function test_Majority_NoVotes_ReturnsMaxUint() public {
        // Mock vote counts: All zero
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2

        mockGovernor.setProposalAllVotes(8, votes); // Use proposalId 8
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority);

        uint256 winningOption = evaluator.evaluate(8); 

        // No votes means no majority
        assertEq(winningOption, type(uint256).max, "Should return max uint when no votes are cast");
    }

    // --- ADMINISTRATIVE FUNCTION TESTS ---

    function test_SetEvaluationStrategy() public {
        assertEq(uint8(evaluator.evaluationStrategy()), uint8(MultipleChoiceEvaluator.EvaluationStrategy.Plurality), "Initial strategy should be Plurality");

        // Change strategy to Majority
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority);
        assertEq(uint8(evaluator.evaluationStrategy()), uint8(MultipleChoiceEvaluator.EvaluationStrategy.Majority), "Strategy should be Majority after set");

        // Change back to Plurality
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);
        assertEq(uint8(evaluator.evaluationStrategy()), uint8(MultipleChoiceEvaluator.EvaluationStrategy.Plurality), "Strategy should be Plurality after set back");
    }

    function test_UpdateGovernor() public {
        address initialGovernor = address(evaluator.governor()); // Cast to address
        assertEq(initialGovernor, address(mockGovernor), "Initial governor address mismatch");

        // Deploy a new mock governor
        MockGovernor newMockGovernor = new MockGovernor();
        
        // Update the governor address in the evaluator
        evaluator.updateGovernor(address(newMockGovernor));

        // Verify the address was updated
        assertEq(address(evaluator.governor()), address(newMockGovernor), "Governor address should be updated"); // Cast to address
    }

     function test_RevertWhen_UpdateGovernor_NotOwner() public {
        address initialGovernor = address(evaluator.governor()); // Cast to address
        address attacker = address(0x123);
        // Attempt to update governor from a different address (not the deployer/owner)
        vm.prank(attacker); // Use an arbitrary address
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        evaluator.updateGovernor(address(0x456)); 
        
        // Verify the address remains unchanged
        assertEq(address(evaluator.governor()), initialGovernor, "Governor address should not change"); // Cast to address
    }
    
     function test_RevertWhen_SetEvaluationStrategy_NotOwner() public {
         MultipleChoiceEvaluator.EvaluationStrategy initialStrategy = evaluator.evaluationStrategy();
         address attacker = address(0x123);
        // Attempt to set strategy from a different address
        vm.prank(attacker); 
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority); 
        
        // Verify the strategy remains unchanged
        assertEq(uint8(evaluator.evaluationStrategy()), uint8(initialStrategy), "Strategy should not change");
    }
    
    // --- EDGE CASE TESTS ---
    
    function test_EdgeCase_LargeVoteCounts_Plurality() public {
        // Use extremely large numbers, close to type(uint256).max / 3
        uint256 largeVote1 = type(uint256).max / 4;
        uint256 largeVote2 = type(uint256).max / 3; // Largest
        uint256 largeVote3 = type(uint256).max / 5;
        uint256 totalOptionVotes = largeVote1 + largeVote2 + largeVote3; // Should not overflow
        
        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 100; 
        votes[1] = totalOptionVotes; // For (sum of options)
        votes[2] = 50;  
        votes[3] = largeVote1; // Option 0
        votes[4] = largeVote2; // Option 1 (Highest)
        votes[5] = largeVote3; // Option 2

        mockGovernor.setProposalAllVotes(11, votes); // Use proposalId 11
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);

        uint256 winningOption = evaluator.evaluate(11); 

        // Option 1 should win
        assertEq(winningOption, 1, "Winning option should be 1 with large votes (Plurality)");
    }

    function test_EdgeCase_LargeVoteCounts_Majority() public {
        // Majority requires > 50%. Use values where one option clearly has > 50%.
        uint256 majorityVote = (type(uint256).max / 3) * 2; // ~66%
        uint256 minorityVote1 = type(uint256).max / 10;
        uint256 minorityVote2 = type(uint256).max / 11;
        uint256 totalOptionVotes = majorityVote + minorityVote1 + minorityVote2; // Should not overflow

        uint256[] memory votes = new uint256[](6); // Against, For, Abstain, Opt0, Opt1, Opt2
        votes[0] = 100; 
        votes[1] = totalOptionVotes; // For (sum of options)
        votes[2] = 50;  
        votes[3] = majorityVote; // Option 0 (Majority)
        votes[4] = minorityVote1; // Option 1
        votes[5] = minorityVote2; // Option 2

        mockGovernor.setProposalAllVotes(12, votes); // Use proposalId 12
        evaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Majority);

        uint256 winningOption = evaluator.evaluate(12); 

        // Option 0 should win
        assertEq(winningOption, 0, "Winning option should be 0 with large votes (Majority)");
        
        // Test case where no majority exists with large numbers
        uint256 largeEqualVote1 = type(uint256).max / 3;
        uint256 largeEqualVote2 = type(uint256).max / 3;
        uint256 largeEqualVote3 = type(uint256).max / 4; // Slightly less, prevents exact 1/3
        uint256 totalNoMajorityVotes = largeEqualVote1 + largeEqualVote2 + largeEqualVote3;
        
        uint256[] memory noMajorityVotes = new uint256[](6);
        noMajorityVotes[0] = 10; noMajorityVotes[1] = totalNoMajorityVotes; noMajorityVotes[2] = 5;
        noMajorityVotes[3] = largeEqualVote1;
        noMajorityVotes[4] = largeEqualVote2;
        noMajorityVotes[5] = largeEqualVote3;
        
        mockGovernor.setProposalAllVotes(13, noMajorityVotes); // Use proposalId 13
        // Strategy is still Majority
        uint256 noWinningOption = evaluator.evaluate(13); 
        assertEq(noWinningOption, type(uint256).max, "Should return max uint with no majority (large votes)");
    }
} 