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

    // --- Integration Tests --- //

    // --- Input Validation Tests (using _createAndPrepareDistroProposal) ---

    function test_Integration_RevertWhen_InvalidProposalState_Pending() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](2); options[0]="A"; options[1]="B";
        address[] memory recipients = new address[](2); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1;
        uint8 topN = 1;
        address[] memory voters = new address[](0); // No voters needed
        uint8[] memory votes = new uint8[](0);

        // Create proposal BUT DO NOT advance time past voting delay
        vm.deal(address(distributor), initialFunding);
        bytes memory distributeCalldata = abi.encodeWithSelector(FundingDistributor.distribute.selector, 0, topN, recipients);
        bytes[] memory tempCalldatas = new bytes[](1); tempCalldatas[0] = distributeCalldata;
        vm.startPrank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, tempCalldatas, description, options);
        vm.stopPrank();

        // Verify state is Pending
        assertEq(uint(governor.state(proposalId)), uint(IGovernor.ProposalState.Pending));

        // Prepare final calldata for execution attempt (even though it shouldn't get scheduled)
        distributeCalldata = abi.encodeWithSelector(FundingDistributor.distribute.selector, proposalId, topN, recipients);
        calldatas[0] = distributeCalldata;

        // Attempting to schedule/execute a Pending proposal should fail.
        // Timelock's scheduleBatch likely won't be callable by Governor if state isn't Succeeded.
        // Let's test the direct call to distributor first, simulating Timelock bypass (requires prank)
        vm.startPrank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__InvalidProposalState.selector, proposalId, IGovernor.ProposalState.Pending));
        distributor.distribute(proposalId, topN, recipients);
        vm.stopPrank();
    }

    function test_Integration_RevertWhen_InvalidProposalState_Active() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](2); options[0]="A"; options[1]="B";
        address[] memory recipients = new address[](2); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1;
        uint8 topN = 1;
        address[] memory voters = new address[](0); // No voters needed
        uint8[] memory votes = new uint8[](0);

        // Create proposal and advance time INTO voting period
        vm.deal(address(distributor), initialFunding);
        bytes memory distributeCalldata = abi.encodeWithSelector(FundingDistributor.distribute.selector, 0, topN, recipients);
        bytes[] memory tempCalldatas = new bytes[](1); tempCalldatas[0] = distributeCalldata;
        vm.startPrank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, tempCalldatas, description, options);
        vm.stopPrank();
        vm.roll(block.number + governor.votingDelay() + 1);

        // Verify state is Active
        assertEq(uint(governor.state(proposalId)), uint(IGovernor.ProposalState.Active));

        // Simulate Timelock calling distribute while proposal is Active
        vm.startPrank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__InvalidProposalState.selector, proposalId, IGovernor.ProposalState.Active));
        distributor.distribute(proposalId, topN, recipients);
        vm.stopPrank();
    }

    // Note: Testing Defeated/Canceled states directly might be hard as Timelock wouldn't execute.
    // These tests simulate a bypass where Timelock *could* call distributor.

    function test_Integration_RevertWhen_RecipientArrayMismatch() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients_wrong = new address[](2); // Intentionally wrong length
        recipients_wrong[0]=RECIPIENT_0; recipients_wrong[1]=RECIPIENT_1;
        uint8 topN = 1;
        address[] memory voters = new address[](1); voters[0]=VOTER_B;
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        // Create proposal with the *invalid* calldata from the start
        vm.deal(address(distributor), initialFunding);
        bytes memory initialInvalidCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector,
            0, // Placeholder ID
            topN,
            recipients_wrong // Use wrong array here
        );
        bytes[] memory tempCalldatas = new bytes[](1); tempCalldatas[0] = initialInvalidCalldata;

        vm.startPrank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, tempCalldatas, description, options);
        vm.stopPrank();

        // Vote to make it succeed
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.startPrank(VOTER_B); governor.castVoteWithOption(proposalId, 0); vm.stopPrank();
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal did not succeed");

        // Prepare the *final* invalid calldata for scheduling/execution
        bytes memory finalInvalidCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector,
            proposalId,
            topN,
            recipients_wrong // Use wrong array here again
        );
        calldatas[0] = finalInvalidCalldata;

        // Schedule
        vm.startPrank(address(governor));
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), descriptionHash, timelockMinDelay);
        vm.stopPrank();

        // Wait
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        vm.roll(block.number + 1);

        // Execute expecting the revert from FundingDistributor
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__RecipientArrayLengthMismatch.selector, proposalId, 3, 2));
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
    }

    function test_Integration_RevertWhen_InvalidTopN_Zero() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients = new address[](3); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2;
        uint8 topN_invalid = 0; // Invalid topN
        address[] memory voters = new address[](1); voters[0]=VOTER_B;
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        // Create proposal with the *invalid* calldata (invalid topN) from the start
        vm.deal(address(distributor), initialFunding);
        bytes memory initialInvalidCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector, 0, topN_invalid, recipients);
        bytes[] memory tempCalldatas = new bytes[](1); tempCalldatas[0] = initialInvalidCalldata;
        vm.startPrank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, tempCalldatas, description, options);
        vm.stopPrank();

        // Vote to make it succeed
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.startPrank(VOTER_B); governor.castVoteWithOption(proposalId, 0); vm.stopPrank();
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal did not succeed");

        // Prepare final invalid calldata
        bytes memory finalInvalidCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector, proposalId, topN_invalid, recipients);
        calldatas[0] = finalInvalidCalldata;

        // Schedule
        vm.startPrank(address(governor));
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), descriptionHash, timelockMinDelay);
        vm.stopPrank();
        // Wait
        vm.warp(block.timestamp + timelock.getMinDelay() + 1); vm.roll(block.number + 1);

        // Execute expecting the revert from FundingDistributor
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__InvalidTopN.selector, topN_invalid, 3));
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
    }

    function test_Integration_RevertWhen_InvalidTopN_TooLarge() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients = new address[](3); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2;
        uint8 topN_invalid = 4; // Invalid topN
        address[] memory voters = new address[](1); voters[0]=VOTER_B;
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        // Create proposal with the *invalid* calldata (invalid topN) from the start
        vm.deal(address(distributor), initialFunding);
        bytes memory initialInvalidCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector, 0, topN_invalid, recipients);
        bytes[] memory tempCalldatas = new bytes[](1); tempCalldatas[0] = initialInvalidCalldata;
        vm.startPrank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, tempCalldatas, description, options);
        vm.stopPrank();

        // Vote to make it succeed
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.startPrank(VOTER_B); governor.castVoteWithOption(proposalId, 0); vm.stopPrank();
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal did not succeed");

        // Prepare final invalid calldata
        bytes memory finalInvalidCalldata = abi.encodeWithSelector(
            FundingDistributor.distribute.selector, proposalId, topN_invalid, recipients);
        calldatas[0] = finalInvalidCalldata;

        // Schedule
        vm.startPrank(address(governor));
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), descriptionHash, timelockMinDelay);
        vm.stopPrank();
        // Wait
        vm.warp(block.timestamp + timelock.getMinDelay() + 1); vm.roll(block.number + 1);

        // Execute expecting the revert from FundingDistributor
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__InvalidTopN.selector, topN_invalid, 3));
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
    }

    // --- Funding Edge Case Tests --- //

    function test_Integration_Funding_ZeroBalance() public {
        uint256 initialFunding = 0 ether; // Zero initial funding
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients = new address[](3); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2;
        uint8 topN = 1;
        address[] memory voters = new address[](1); voters[0]=VOTER_B; // Vote for A
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Record logs - expect amountPerRecipient = 0
        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        address[] memory expectedWinners = new address[](1); expectedWinners[0] = RECIPIENT_0;
        bytes memory expectedData = abi.encode(expectedWinners, 0); // Expect amount 0

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], expectedTopic1);
                assertEq(logs[i].data, expectedData, "Event data mismatch (expected amount 0)");
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances haven't changed
        assertEq(address(distributor).balance, 0);
        assertEq(RECIPIENT_0.balance, 0);
    }

    function test_Integration_Funding_DustBalance() public {
        uint256 initialFunding = 5 wei; // Less than number of winners
        string[] memory options = new string[](4); options[0]="A"; options[1]="B"; options[2]="C"; options[3]="D";
        address[] memory recipients = new address[](4); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2; recipients[3]=RECIPIENT_3;
        uint8 topN = 3; // 3 winners expected
        // Make A, B, C win
        address[] memory voters = new address[](3); voters[0]=VOTER_A; voters[1]=VOTER_B; voters[2]=VOTER_C;
        uint8[] memory votes = new uint8[](3); votes[0]=0; votes[1]=1; votes[2]=2;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Record logs - expect amountPerRecipient = 1 (5 wei / 3 winners)
        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        uint256 expectedAmount = 1; // 5 wei / 3 winners = 1 wei each
        // Expected recipients, order doesn't matter for check
        address[] memory expectedWinnersSet = new address[](3); 
        expectedWinnersSet[0] = RECIPIENT_0; 
        expectedWinnersSet[1] = RECIPIENT_1; 
        expectedWinnersSet[2] = RECIPIENT_2;

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], expectedTopic1);

                // Decode the event data
                (address[] memory emittedRecipients, uint256 emittedAmount) = 
                    abi.decode(logs[i].data, (address[], uint256));

                // Check amount
                assertEq(emittedAmount, expectedAmount, "Event amount mismatch");

                // Check recipients count
                assertEq(emittedRecipients.length, expectedWinnersSet.length, "Recipient count mismatch");

                // Check if all expected recipients are present (order-independent)
                uint foundCount = 0;
                for(uint j = 0; j < expectedWinnersSet.length; j++) {
                    for(uint k = 0; k < emittedRecipients.length; k++) {
                        if (expectedWinnersSet[j] == emittedRecipients[k]) {
                            foundCount++;
                            break; // Found this expected recipient, move to next one
                        }
                    }
                }
                assertEq(foundCount, expectedWinnersSet.length, "Mismatch in emitted recipients set");

                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances (2 wei should remain)
        assertEq(address(distributor).balance, initialFunding - (expectedAmount * 3), "Distributor balance incorrect");
        assertEq(RECIPIENT_0.balance, expectedAmount);
        assertEq(RECIPIENT_1.balance, expectedAmount);
        assertEq(RECIPIENT_2.balance, expectedAmount);
    }

    // TODO: Test large balance

    // --- Winner/Recipient Edge Case Tests --- //

    function test_Integration_WinnerRecipient_TopN_Equals_OptionCount() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        address[] memory recipients = new address[](3); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_1; recipients[2]=RECIPIENT_2;
        uint8 topN = 3; // topN equals option count
        // A=100, B=200, C=300 votes. All should win.
        address[] memory voters = new address[](3); voters[0]=VOTER_A; voters[1]=VOTER_B; voters[2]=VOTER_C;
        uint8[] memory votes = new uint8[](3); votes[0]=0; votes[1]=1; votes[2]=2;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log - Expect 3 winners
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        uint256 expectedAmount = initialFunding / 3;
        address[] memory expectedWinnersSet = new address[](3); 
        expectedWinnersSet[0] = RECIPIENT_0; expectedWinnersSet[1] = RECIPIENT_1; expectedWinnersSet[2] = RECIPIENT_2;

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                (address[] memory emittedRecipients, uint256 emittedAmount) = abi.decode(logs[i].data, (address[], uint256));
                assertEq(emittedAmount, expectedAmount, "Event amount mismatch");
                assertEq(emittedRecipients.length, 3, "Recipient count mismatch");
                
                // Manual check for recipient presence
                uint foundCount = 0;
                for(uint j=0; j < expectedWinnersSet.length; j++) {
                    bool recipientFound = false;
                    for(uint k=0; k < emittedRecipients.length; k++) {
                        if (expectedWinnersSet[j] == emittedRecipients[k]) {
                            recipientFound = true;
                            break;
                        }
                    }
                    assertTrue(recipientFound, string(abi.encodePacked("Expected recipient not found: ", vm.toString(expectedWinnersSet[j]))));
                }

                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances
        assertEq(address(distributor).balance, initialFunding - (expectedAmount * 3), "Distributor balance incorrect");
        assertEq(RECIPIENT_0.balance, expectedAmount);
        assertEq(RECIPIENT_1.balance, expectedAmount);
        assertEq(RECIPIENT_2.balance, expectedAmount);
    }

    function test_Integration_WinnerRecipient_RevertWhen_AllWinnersAreAddressZero() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](2); options[0]="A"; options[1]="B";
        // Both potential winners map to address(0)
        address[] memory recipients = new address[](2); recipients[0]=address(0); recipients[1]=address(0);
        uint8 topN = 1; // Request top 1
        address[] memory voters = new address[](1); voters[0]=VOTER_A; // A votes for Option 0
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        // Execute expecting revert because the only winner (A) corresponds to address(0)
        vm.expectRevert(abi.encodeWithSelector(FundingDistributor.FundingDistributor__NoWinners.selector, proposalId));
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);

        assertEq(address(distributor).balance, initialFunding);
    }

    function test_Integration_WinnerRecipient_DuplicateRecipientGetsMultiplePayouts() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](3); options[0]="A"; options[1]="B"; options[2]="C";
        // Recipient 0 is mapped to two winning options (A and B)
        address[] memory recipients = new address[](3); recipients[0]=RECIPIENT_0; recipients[1]=RECIPIENT_0; recipients[2]=RECIPIENT_2;
        uint8 topN = 2; // Request top 2
        // A votes A (100), B votes B (200). Winners A, B.
        address[] memory voters = new address[](2); voters[0]=VOTER_A; voters[1]=VOTER_B;
        uint8[] memory votes = new uint8[](2); votes[0]=0; votes[1]=1;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log - Expect 2 winners (R0, R0)
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        uint256 expectedAmount = initialFunding / 2; // Divided by 2 winners
        address[] memory expectedWinnersInEvent = new address[](2); expectedWinnersInEvent[0] = RECIPIENT_0; expectedWinnersInEvent[1] = RECIPIENT_0;
        bytes memory expectedData = abi.encode(expectedWinnersInEvent, expectedAmount);

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                 (address[] memory emittedRecipients, uint256 emittedAmount) = abi.decode(logs[i].data, (address[], uint256));
                assertEq(emittedAmount, expectedAmount, "Event amount mismatch");
                assertEq(emittedRecipients.length, 2, "Recipient count mismatch");
                // Check R0 appears twice (can check exact data match here)
                assertEq(logs[i].data, expectedData, "Event data mismatch"); 
                eventFound = true;
                break;
            }
        }
         assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances - R0 gets 2x amount
        assertEq(address(distributor).balance, 0, "Distributor balance should be 0");
        assertEq(RECIPIENT_0.balance, expectedAmount * 2, "Recipient 0 balance incorrect");
        assertEq(RECIPIENT_2.balance, 0, "Recipient 2 balance incorrect");
    }

    function test_Integration_WinnerRecipient_DistributorAsRecipient() public {
        uint256 initialFunding = 1 ether;
        string[] memory options = new string[](2); options[0]="A"; options[1]="B";
        // Option A winner maps to the distributor itself
        address[] memory recipients = new address[](2); recipients[0]=address(distributor); recipients[1]=RECIPIENT_1;
        uint8 topN = 1;
        address[] memory voters = new address[](1); voters[0]=VOTER_A; // Vote A
        uint8[] memory votes = new uint8[](1); votes[0]=0;

        uint256 proposalId = _createAndPrepareDistroProposal(options, topN, recipients, voters, votes, true, initialFunding);

        vm.recordLogs();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Check log - Expect 1 winner (distributor)
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("FundsDistributed(uint256,address[],uint256)");
        bytes32 expectedTopic1 = bytes32(proposalId);
        uint256 expectedAmount = initialFunding; // 1 winner
        address[] memory expectedWinnersInEvent = new address[](1); expectedWinnersInEvent[0] = address(distributor);
        bytes memory expectedData = abi.encode(expectedWinnersInEvent, expectedAmount);

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(distributor) && logs[i].topics[0] == expectedTopic0) {
                 (address[] memory emittedRecipients, uint256 emittedAmount) = abi.decode(logs[i].data, (address[], uint256));
                assertEq(emittedAmount, expectedAmount, "Event amount mismatch");
                assertEq(emittedRecipients.length, 1, "Recipient count mismatch");
                assertEq(logs[i].data, expectedData, "Event data mismatch");
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "FundsDistributed event not found");

        // Verify balances - Distributor balance remains the same (transfer to self)
        assertEq(address(distributor).balance, initialFunding, "Distributor balance incorrect");
        assertEq(RECIPIENT_1.balance, 0, "Recipient 1 balance incorrect");
    }

}

contract RejectReceiver {
    receive() external payable { revert("I reject ETH"); }
} 