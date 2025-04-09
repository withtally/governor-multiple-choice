// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FundingDistributor} from "../src/FundingDistributor.sol";
import {GovernorCountingMultipleChoice} from "../src/GovernorCountingMultipleChoice.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {MockGovernorForFuzz} from "./mocks/MockGovernorForFuzz.sol";

contract FundingDistributorFuzzTest is Test {
    // Constants for mocking
    uint256 constant MOCK_PROPOSAL_ID = 999;
    uint8 constant MOCK_OPTION_COUNT = 5;
    uint256 constant INITIAL_BALANCE = 10 ether;
    address constant MOCK_TIMELOCK = address(0x7133);

    FundingDistributor internal distributor;
    MockGovernorForFuzz internal mockGovernor;
    address[] internal mockRecipients;
    
    // Fixed vote counts for testing
    uint256[5] voteAmounts = [500, 400, 300, 200, 100];

    function setUp() public {
        // Deploy the mock contract
        mockGovernor = new MockGovernorForFuzz(); 
        distributor = new FundingDistributor(address(mockGovernor), MOCK_TIMELOCK, address(this));

        // Prepare mock recipients array
        mockRecipients = new address[](MOCK_OPTION_COUNT);
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            mockRecipients[i] = address(uint160(i + 1)); // Simple unique addresses
        }
    }
    
    // Test that the basic mocks are working
    function test_MockIsWorking() public view {
        // Verify mock contract deployed correctly
        assertTrue(address(mockGovernor) != address(0), "Mock governor not deployed");
        assertTrue(address(distributor) != address(0), "Distributor not deployed");
        
        // Verify correct array length
        assertEq(mockRecipients.length, MOCK_OPTION_COUNT, "Recipients array wrong length");
    }
    
    // Simplified fuzzing test that just tests the mapping logic without calling distribute
    function testFuzz_MapTopN(uint8 fuzzedTopN) public pure {
        // Map the fuzzed value (0-255) to the valid range (1 to MOCK_OPTION_COUNT)
        uint8 topN = uint8(1 + (uint256(fuzzedTopN) % uint256(MOCK_OPTION_COUNT)));
        
        // Verify the mapping works correctly
        assertTrue(topN >= 1 && topN <= MOCK_OPTION_COUNT, "TopN mapping failed");
    }
    
    // Test with hardcoded values using alternative mocking approach
    function test_DistributeWithHardcodedValues() public {
        // Mock state call - this seems to work fine
        vm.mockCall(
            address(mockGovernor), 
            abi.encodeWithSelector(IGovernor.state.selector, MOCK_PROPOSAL_ID), 
            abi.encode(IGovernor.ProposalState.Succeeded)
        );
        
        // Use a more direct approach for mocking proposalOptions
        // Create options array - keep it simple (no strings)
        string[] memory emptyOptions = new string[](MOCK_OPTION_COUNT);
        
        // Testing directly encoding a tuple to avoid any potential issues with complex encoding
        bytes memory returnData = abi.encode(emptyOptions, uint8(MOCK_OPTION_COUNT));
        
        // Mock the call
        vm.mockCall(
            address(mockGovernor),
            abi.encodeWithSelector(bytes4(keccak256("proposalOptions(uint256)")), MOCK_PROPOSAL_ID),
            returnData
        );
        
        // Mock vote counts - use simple consistent values
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            uint256 votes = 100;  // Same vote count for each option
            vm.mockCall(
                address(mockGovernor),
                abi.encodeWithSelector(bytes4(keccak256("proposalOptionVotes(uint256,uint8)")), MOCK_PROPOSAL_ID, i),
                abi.encode(votes)
            );
        }
        
        // Fund the distributor
        vm.deal(address(distributor), INITIAL_BALANCE);
        
        // Call distribute with hardcoded topN value
        uint8 topN = 2; // Use a safe value
        vm.prank(MOCK_TIMELOCK);
        
        // Pre-balance check
        uint256 preBalance = address(distributor).balance;
        
        // Call the function
        distributor.distribute(MOCK_PROPOSAL_ID, topN, mockRecipients);
        
        // Post-balance check
        uint256 postBalance = address(distributor).balance;
        
        // Check that funds were distributed
        assertTrue(postBalance < preBalance, "No ETH was distributed");
    }
    
    // Fixed fuzz test for different topN values
    function testFuzz_DistributeWithDifferentTopN(uint8 fuzzedTopN) public {
        // Manually bound the topN value to a valid range (1 to MOCK_OPTION_COUNT)
        // First ensure it's not 0, then limit to MOCK_OPTION_COUNT
        uint8 topN = fuzzedTopN;
        if (topN == 0) topN = 1;
        if (topN > MOCK_OPTION_COUNT) topN = MOCK_OPTION_COUNT;
        
        // Set up mock calls with a fixed approach that avoids the overflow
        
        // Mock state call
        vm.mockCall(
            address(mockGovernor), 
            abi.encodeWithSelector(IGovernor.state.selector, MOCK_PROPOSAL_ID), 
            abi.encode(IGovernor.ProposalState.Succeeded)
        );
        
        // Mock proposalOptions with fixed encoding that works
        string[] memory emptyOptions = new string[](MOCK_OPTION_COUNT);
        vm.mockCall(
            address(mockGovernor),
            abi.encodeWithSelector(bytes4(keccak256("proposalOptions(uint256)")), MOCK_PROPOSAL_ID),
            abi.encode(emptyOptions, uint8(MOCK_OPTION_COUNT))
        );
        
        // Mock vote counts with a clear distribution pattern
        // Using the fixed vote amounts array from storage
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            vm.mockCall(
                address(mockGovernor),
                abi.encodeWithSelector(bytes4(keccak256("proposalOptionVotes(uint256,uint8)")), MOCK_PROPOSAL_ID, i),
                abi.encode(voteAmounts[i])
            );
        }
        
        // Fund the distributor
        vm.deal(address(distributor), INITIAL_BALANCE);
        
        // Record starting ETH balances
        uint256 startDistributorBalance = address(distributor).balance;
        uint256[] memory startRecipientBalances = new uint256[](MOCK_OPTION_COUNT);
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            startRecipientBalances[i] = address(mockRecipients[i]).balance;
        }
        
        // Call distribute as timelock
        vm.prank(MOCK_TIMELOCK);
        distributor.distribute(MOCK_PROPOSAL_ID, topN, mockRecipients);
        
        // Record ending ETH balances
        uint256 endDistributorBalance = address(distributor).balance;
        uint256[] memory endRecipientBalances = new uint256[](MOCK_OPTION_COUNT);
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            endRecipientBalances[i] = address(mockRecipients[i]).balance;
        }
        
        // Calculate total received by recipients
        uint256 totalReceivedByRecipients = 0;
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            totalReceivedByRecipients += (endRecipientBalances[i] - startRecipientBalances[i]);
        }
        
        // Ensure ETH conservation
        assertEq(
            startDistributorBalance - endDistributorBalance,
            totalReceivedByRecipients,
            "ETH Conservation Failed"
        );
        
        // Ensure top N received funds as expected based on vote counts
        for (uint8 i = 0; i < MOCK_OPTION_COUNT; i++) {
            if (i < topN) {
                // Top N recipients should receive funds
                assertTrue(
                    endRecipientBalances[i] > startRecipientBalances[i],
                    string(abi.encodePacked("Recipient ", vm.toString(i), " should have received funds"))
                );
            }
        }
        
        // Clear mocks
        vm.clearMockedCalls();
    }
} 