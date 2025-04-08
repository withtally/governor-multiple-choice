// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FundingDistributor} from "../src/FundingDistributor.sol";
import {GovernorCountingMultipleChoice} from "../src/GovernorCountingMultipleChoice.sol";
import {VotesToken} from "./GovernorCountingMultipleChoice.t.sol"; // Reuse test token
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract FundingDistributorTest is Test {
    // Test accounts
    address internal constant VOTER_A = address(0xA1);
    address internal constant VOTER_B = address(0xB1);
    address internal constant VOTER_C = address(0xC1);
    address internal constant VOTER_D = address(0xD1);
    address internal constant PROPOSER = address(0xE1);
    address internal constant RECIPIENT_0 = address(0xF0);
    address internal constant RECIPIENT_1 = address(0xF1);
    address internal constant RECIPIENT_2 = address(0xF2);
    address internal constant RECIPIENT_3 = address(0xF3);
    address internal constant OTHER_ADDRESS = address(0xDEAD);
    address internal deployer; // Set in setUp

    // Contract instances
    VotesToken internal token;
    TimelockController internal timelock;
    GovernorCountingMultipleChoice internal governor;
    FundingDistributor internal distributor;

    // Proposal data
    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas; // This will be updated in the helper
    string internal description = "Distribute Funds Proposal";
    bytes32 internal descriptionHash;

    // Governor settings
    uint256 internal votingDelay = 1;
    uint256 internal votingPeriod = 5;
    uint256 internal proposalThreshold = 0;
    uint256 internal timelockMinDelay = 1;

    function setUp() public {
        deployer = address(this);
        token = new VotesToken("DistroToken", "DTKN");
        address[] memory proposers = new address[](1); proposers[0] = address(0);
        address[] memory executors = new address[](1); executors[0] = address(0);
        timelock = new TimelockController(timelockMinDelay, proposers, executors, deployer);
        governor = new GovernorCountingMultipleChoice(IVotes(address(token)), timelock, "DistroGovernor");
        distributor = new FundingDistributor(address(governor), address(timelock), deployer);

        bytes32 proposerRole = keccak256("PROPOSER_ROLE");
        bytes32 cancellerRole = keccak256("CANCELLER_ROLE");
        bytes32 adminRole = bytes32(0x00); // DEFAULT_ADMIN_ROLE

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(adminRole, deployer);
        timelock.grantRole(cancellerRole, deployer);

        token.mint(VOTER_A, 100);
        token.mint(VOTER_B, 200);
        token.mint(VOTER_C, 300);
        token.mint(VOTER_D, 400);
        vm.startPrank(VOTER_A); token.delegate(VOTER_A); vm.stopPrank();
        vm.startPrank(VOTER_B); token.delegate(VOTER_B); vm.stopPrank();
        vm.startPrank(VOTER_C); token.delegate(VOTER_C); vm.stopPrank();
        vm.startPrank(VOTER_D); token.delegate(VOTER_D); vm.stopPrank();

        targets = new address[](1); targets[0] = address(distributor);
        values = new uint256[](1); values[0] = 0;
        calldatas = new bytes[](1); // Will be set per test by helper
        descriptionHash = keccak256(bytes(description));
    }

    // Renamed helper: Creates proposal, votes, waits, schedules, waits. DOES NOT EXECUTE.
    function _createAndPrepareDistroProposal(
        string[] memory options,
        uint8 topN,
        address[] memory recipientsByOptionIndex,
        address[] memory voters,
        uint8[] memory votesOrOptions,
        bool isMultipleChoiceVote,
        uint256 initialDistributorBalance
    ) internal returns (uint256 proposalId) {
        vm.deal(address(distributor), initialDistributorBalance);
        assertEq(address(distributor).balance, initialDistributorBalance);

        // Encode initial calldata with placeholder proposalId
        bytes memory initialDistributeCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector,
            0, // Placeholder ID
            topN,
            recipientsByOptionIndex
        );
        // Temporarily store it for proposal creation
        bytes[] memory tempCalldatas = new bytes[](1);
        tempCalldatas[0] = initialDistributeCalldata;

        // Create proposal
        vm.startPrank(PROPOSER);
        proposalId = governor.propose(targets, values, tempCalldatas, description, options);
        vm.stopPrank();
        assertGt(proposalId, 0);

        // Voting phase
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
        for (uint i = 0; i < voters.length; i++) {
            vm.startPrank(voters[i]);
            if (isMultipleChoiceVote) {
                governor.castVoteWithOption(proposalId, votesOrOptions[i]);
            } else {
                governor.castVote(proposalId, votesOrOptions[i]);
            }
            vm.stopPrank();
        }
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal did not succeed");

        // Prepare the *actual* calldata for execution using the real proposalId
        bytes memory finalDistributeCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector,
            proposalId, // Use actual proposalId
            topN,
            recipientsByOptionIndex
        );
        // Update the member variable `calldatas` used by the test functions for execution
        calldatas[0] = finalDistributeCalldata;

        // Schedule phase
        vm.startPrank(address(governor));
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), descriptionHash, timelockMinDelay);
        vm.stopPrank();

        // Wait phase
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        vm.roll(block.number + 1);
    }

    // --- Integration Tests --- //

    function test_Integration_Distribute_Top1_ClearWinner() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients = new address[](3); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2;
        uint8 topN = 1;
        address[] memory voters = new address[](3); voters[0]=VOTER_A; voters[1]=VOTER_B; voters[2]=VOTER_C;
        uint8[] memory votes = new uint8[](3); votes[0]=0; votes[1]=1; votes[2]=1; // Option 1 wins

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Record logs during execution
        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the FundsDistributed event log
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        address[] memory expectedWinners = new address[](1); expectedWinners[0] = RECIPIENT_1;
        bytes memory expectedData = abi.encode(expectedWinners, initialFunding);

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                assertEq(logs[i].topics.length, 2, "Event should have 2 topics (signature, proposalId)");
                assertEq(logs[i].topics[1], expectedTopic1, "Topic 1 (proposalId) mismatch");
                assertEq(logs[i].data, expectedData, "Event data mismatch");
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances (remain the same)
        assertEq(address(distributor).balance, 0);
        assertEq(RECIPIENT_0.balance, 0);
        assertEq(RECIPIENT_1.balance, initialFunding);
        assertEq(RECIPIENT_2.balance, 0);
    }

    function test_Integration_Distribute_Top2_TieForSecond() public {
        uint256 initialFunding = 0.9 ether;
        string[] memory options = new string[](4); options[0]="X"; options[1]="Y"; options[2]="Z"; options[3]="W";
        address[] memory recipients = new address[](4); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2; recipients[3]=RECIPIENT_3;
        uint8 topN = 2;
        address[] memory voters = new address[](4); voters[0]=VOTER_A; voters[1]=VOTER_B; voters[2]=VOTER_C; voters[3]=VOTER_D;
        uint8[] memory votes = new uint8[](4); votes[0]=0; votes[1]=1; votes[2]=2; votes[3]=1; // Opt1(600), Opt2(300), Opt0(100) -> Winners: R1, R2

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Record logs
        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        address[] memory expectedWinners = new address[](2); expectedWinners[0] = RECIPIENT_1; expectedWinners[1] = RECIPIENT_2;
        uint256 expectedAmount = initialFunding / 2;
        bytes memory expectedData = abi.encode(expectedWinners, expectedAmount);

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], expectedTopic1);
                assertEq(logs[i].data, expectedData);
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances
        assertEq(address(distributor).balance, 0);
        assertEq(RECIPIENT_0.balance, 0);
        assertEq(RECIPIENT_1.balance, expectedAmount);
        assertEq(RECIPIENT_2.balance, expectedAmount);
        assertEq(RECIPIENT_3.balance, 0);
    }

     function test_Integration_Distribute_Top2_ExactTieForSecondIncludesBoth() public {
        uint256 initialFunding = 1.5 ether;
        string[] memory options = new string[](4); options[0]="X"; options[1]="Y"; options[2]="Z"; options[3]="W";
        address[] memory recipients = new address[](4); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2; recipients[3]=RECIPIENT_3;
        uint8 topN = 2;
        address[] memory voters = new address[](4); voters[0]=VOTER_A; voters[1]=VOTER_B; voters[2]=VOTER_C; voters[3]=VOTER_D;
        uint8[] memory votes = new uint8[](4); votes[0]=0; votes[1]=1; votes[2]=2; votes[3]=0; // Opt0(500), Opt2(300), Opt1(200) -> Winners: R0, R2

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Record logs
        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        address[] memory expectedWinners = new address[](2); expectedWinners[0] = RECIPIENT_0; expectedWinners[1] = RECIPIENT_2;
        uint256 expectedAmount = initialFunding / 2;
        bytes memory expectedData = abi.encode(expectedWinners, expectedAmount);

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], expectedTopic1);
                assertEq(logs[i].data, expectedData);
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances
        assertEq(address(distributor).balance, 0);
        assertEq(RECIPIENT_0.balance, expectedAmount);
        assertEq(RECIPIENT_1.balance, 0);
        assertEq(RECIPIENT_2.balance, expectedAmount);
        assertEq(RECIPIENT_3.balance, 0);
    }

    function test_Integration_Distribute_Top2_ThreeWayTieForFirstIncludesAllThree() public {
        uint256 initialFunding = 1.2 ether;
        string[] memory options = new string[](4); options[0]="X"; options[1]="Y"; options[2]="Z"; options[3]="W";
        address[] memory recipients = new address[](4); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2; recipients[3]=RECIPIENT_3;
        uint8 topN = 2;

        address VOTER_E = address(0xE2); address VOTER_F = address(0xF2);
        token.mint(VOTER_E, 200); vm.startPrank(VOTER_E); token.delegate(VOTER_E); vm.stopPrank();
        token.mint(VOTER_F, 100); vm.startPrank(VOTER_F); token.delegate(VOTER_F); vm.stopPrank();

        address[] memory voters = new address[](6); voters[0]=VOTER_A; voters[1]=VOTER_B; voters[2]=VOTER_C; voters[3]=VOTER_D; voters[4]=VOTER_E; voters[5]=VOTER_F;
        uint8[] memory votes = new uint8[](6); votes[0]=0; votes[1]=1; votes[2]=2; votes[3]=0; votes[4]=1; votes[5]=2; // Opt0(500), Opt1(400), Opt2(400) -> Winners: R0, R1, R2

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Record logs
        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        address[] memory expectedWinners = new address[](3); expectedWinners[0] = RECIPIENT_0; expectedWinners[1] = RECIPIENT_1; expectedWinners[2] = RECIPIENT_2;
        uint256 expectedAmount = initialFunding / 3;
        bytes memory expectedData = abi.encode(expectedWinners, expectedAmount);

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], expectedTopic1);
                assertEq(logs[i].data, expectedData);
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances
        assertEq(address(distributor).balance, 0);
        assertEq(RECIPIENT_0.balance, expectedAmount);
        assertEq(RECIPIENT_1.balance, expectedAmount);
        assertEq(RECIPIENT_2.balance, expectedAmount);
        assertEq(RECIPIENT_3.balance, 0);
    }

    function test_Integration_RevertWhen_NoWinners() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients = new address[](3); recipients[0]=address(0); recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2;
        uint8 topN = 1;
        address[] memory voters = new address[](1); voters[0]=VOTER_B;
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__NoWinners.selector, proposalId));
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);

        assertEq(address(distributor).balance, initialFunding);
    }

    function test_Integration_RevertWhen_TransferFails() public {
        RejectReceiver rejector = new RejectReceiver();
        address payable rejectorAddress = payable(address(rejector));
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](2); options[0]="Win"; options[1]="Lose";
        address[] memory recipients = new address[](2); recipients[0]=rejectorAddress; recipients[1]=RECIPIENT_1;
        uint8 topN = 1;
        address[] memory voters = new address[](1); voters[0]=VOTER_A;
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__TransferFailed.selector, rejectorAddress, initialFunding));
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);

        assertEq(address(distributor).balance, initialFunding);
        assertEq(rejectorAddress.balance, 0);
    }

    // --- Unit Tests --- //
     function test_Unit_RevertWhen_CallerNotTimelock() public {
        vm.prank(OTHER_ADDRESS); // Not the timelock
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__UnauthorizedCaller.selector, OTHER_ADDRESS));
        distributor.distribute(123, 1, new address[](0));
    }
}

contract RejectReceiver {
    receive() external payable { revert("I reject ETH"); }
} 