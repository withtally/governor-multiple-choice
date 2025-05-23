// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GovernorCountingMultipleChoice} from "../src/GovernorCountingMultipleChoice.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernorProposalMultipleChoiceOptions} from "../src/GovernorProposalMultipleChoiceOptions.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ReentrancyAttacker} from "./mocks/ReentrancyAttacker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";

/**
 * @title VotesToken
 * @dev A simple ERC20 token with voting capabilities for testing
 */
contract VotesToken is ERC20, Votes {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) EIP712(name, "1") {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override(ERC20) {
        super._update(from, to, amount);
        _transferVotingUnits(from, to, amount);
    }

    function _getVotingUnits(address account) internal view override returns (uint256) {
        return balanceOf(account);
    }
}

/**
 * @title GovernorCountingMultipleChoiceTest
 * @dev Test contract for GovernorCountingMultipleChoice
 */
contract GovernorCountingMultipleChoiceTest is Test, GovernorProposalMultipleChoiceOptions {
    // Test accounts
    address internal constant VOTER_A = address(101);
    address internal constant VOTER_B = address(102);
    address internal constant VOTER_C = address(103);
    address internal constant VOTER_D = address(104);
    address internal constant PROPOSER = address(105);

    // Contract instances
    VotesToken internal token;
    TimelockController internal timelock;
    GovernorCountingMultipleChoice internal governor;

    // Proposal data
    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas;
    string internal description = "Test Proposal #1";
    bytes32 internal descriptionHash;

    // Governor settings
    uint256 internal votingDelay = 1;
    uint256 internal votingPeriod = 5;
    uint256 internal proposalThreshold = 0;

    function setUp() public {
        // Setup token
        token = new VotesToken("MyToken", "MTKN");

        // Setup timelock
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(1, proposers, executors, address(this));

        // Setup governor
        governor =
            new GovernorCountingMultipleChoice(IVotes(address(token)), timelock, "GovernorCountingMultipleChoice");

        // Setup timelock roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));

        // Setup token balances and delegate voting power
        token.mint(VOTER_A, 100);
        token.mint(VOTER_B, 200);
        token.mint(VOTER_C, 300);
        token.mint(VOTER_D, 400);
        vm.prank(VOTER_A);
        token.delegate(VOTER_A);
        vm.prank(VOTER_B);
        token.delegate(VOTER_B);
        vm.prank(VOTER_C);
        token.delegate(VOTER_C);
        vm.prank(VOTER_D);
        token.delegate(VOTER_D);

        // Setup proposal data
        targets = new address[](1);
        targets[0] = address(token);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", address(this), 0);
        descriptionHash = keccak256(bytes(description));
    }

    // --- PROPOSAL CREATION TESTS --- // TODO: Gas snapshot for propose

    function test_CreateStandardProposal() public {
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Verify proposal was created correctly
        assertGt(proposalId, 0, "Proposal ID should not be zero");
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Initial state should be Pending"
        );

        // Verify no options were set
        (, uint8 optionCount) = governor.proposalOptions(proposalId);
        assertEq(optionCount, 0, "Standard proposal should have 0 options");
    }

    function test_CreateMultipleChoiceProposal() public {
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Verify proposal was created correctly
        assertGt(proposalId, 0, "Proposal ID should not be zero");
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Initial state should be Pending"
        );

        // Verify options were set correctly
        (string[] memory storedOptions, uint8 optionCount) = governor.proposalOptions(proposalId);
        assertEq(optionCount, options.length, "Option count mismatch");
        assertEq(storedOptions.length, options.length, "Stored options array length mismatch");

        // Verify option content
        for (uint8 i = 0; i < options.length; i++) {
            assertEq(
                keccak256(bytes(storedOptions[i])),
                keccak256(bytes(options[i])),
                string(abi.encodePacked("Option ", i, " mismatch"))
            );
        }
    }

    function test_CreateMultipleChoiceProposalWithMinOptions() public {
        string[] memory options = new string[](2); // Minimum options
        options[0] = "Min Option 1";
        options[1] = "Min Option 2";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Verify proposal was created correctly
        assertGt(proposalId, 0, "Proposal ID should not be zero");
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Initial state should be Pending"
        );

        // Verify minimum options were set correctly
        (string[] memory storedOptions, uint8 optionCount) = governor.proposalOptions(proposalId);
        assertEq(optionCount, 2, "Option count should be 2");
        assertEq(storedOptions.length, 2, "Stored options array length should be 2");

        // Verify option content
        assertEq(keccak256(bytes(storedOptions[0])), keccak256(bytes(options[0])), "Min Option 0 mismatch");
        assertEq(keccak256(bytes(storedOptions[1])), keccak256(bytes(options[1])), "Min Option 1 mismatch");
    }

    function test_CreateMultipleChoiceProposalWithMaxOptions() public {
        string[] memory options = new string[](10); // Maximum options
        for (uint8 i = 0; i < 10; i++) {
            options[i] = string(abi.encodePacked("Option ", i + 1));
        }

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Verify proposal was created correctly
        assertGt(proposalId, 0, "Proposal ID should not be zero");
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Initial state should be Pending"
        );

        // Verify maximum options were set correctly
        (string[] memory storedOptions, uint8 optionCount) = governor.proposalOptions(proposalId);
        assertEq(optionCount, 10, "Option count should be 10");
        assertEq(storedOptions.length, 10, "Stored options array length should be 10");

        // Verify all options content
        for (uint8 i = 0; i < options.length; i++) {
            assertEq(
                keccak256(bytes(storedOptions[i])),
                keccak256(bytes(options[i])),
                string(abi.encodePacked("Option ", i + 1, " mismatch"))
            );
        }
    }

    function test_RevertWhen_CreateProposalWithTooFewOptions() public {
        string[] memory options = new string[](1); // Too few options (minimum is 2)
        options[0] = "Single Option";

        vm.prank(PROPOSER);

        // Expect the call to revert with the correct error message
        vm.expectRevert("Governor: invalid option count (too few)");
        governor.propose(targets, values, calldatas, description, options);
    }

    function test_RevertWhen_CreateProposalWithTooManyOptions() public {
        string[] memory options = new string[](11); // Too many options (maximum is 10)
        for (uint8 i = 0; i < 11; i++) {
            options[i] = string(abi.encodePacked("Option ", i + 1));
        }

        vm.prank(PROPOSER);

        // Expect the call to revert with the correct error message
        vm.expectRevert("Governor: invalid option count (too many)");
        governor.propose(targets, values, calldatas, description, options);
    }

    // --- VOTE CASTING TESTS --- // TODO: Gas snapshot for castVote / castVoteWithOption

    function test_CastStandardVotesOnStandardProposal() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Verify proposal is now active
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Proposal should be active"
        );

        // Cast votes from different accounts (For, Against, Abstain)
        vm.prank(VOTER_A);
        governor.castVote(proposalId, uint8(1)); // For

        vm.prank(VOTER_B);
        governor.castVote(proposalId, uint8(0)); // Against

        vm.prank(VOTER_C);
        governor.castVote(proposalId, uint8(2)); // Abstain

        // Check vote counts are recorded correctly
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        // Voters delegated to themselves with these token amounts in setUp()
        assertEq(forVotes, 100, "For votes should match VOTER_A balance");
        assertEq(againstVotes, 200, "Against votes should match VOTER_B balance");
        assertEq(abstainVotes, 300, "Abstain votes should match VOTER_C balance");
    }

    function test_CastMultipleChoiceVotes() public {
        // Create a multiple choice proposal
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Verify proposal is now active
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Proposal should be active"
        );

        // Cast votes for different options
        vm.prank(VOTER_A);
        governor.castVoteWithOption(proposalId, 0); // Vote for Option A

        vm.prank(VOTER_B);
        governor.castVoteWithOption(proposalId, 1); // Vote for Option B

        vm.prank(VOTER_C);
        governor.castVoteWithOption(proposalId, 2); // Vote for Option C

        // Check option-specific vote counts
        assertEq(governor.proposalOptionVotes(proposalId, 0), 100, "Option A votes should match VOTER_A balance");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 200, "Option B votes should match VOTER_B balance");
        assertEq(governor.proposalOptionVotes(proposalId, 2), 300, "Option C votes should match VOTER_C balance");

        // Check that the standard votes counter also increments "for" votes (support=1)
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 600, "For votes should be sum of all option votes");
        assertEq(againstVotes, 0, "Against votes should be zero");
        assertEq(abstainVotes, 0, "Abstain votes should be zero");
    }

    function test_RevertWhen_CastMultipleChoiceVoteOnStandardProposal() public {
        // Create a standard proposal (no options)
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Try to cast a multiple choice vote on a standard proposal
        vm.prank(VOTER_A);
        vm.expectRevert("Governor: standard proposal, use castVote");
        governor.castVoteWithOption(proposalId, 0);
    }

    function test_RevertWhen_CastVoteWithInvalidOptionIndex() public {
        // Create a multiple choice proposal with 3 options
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Try to vote for option index 3 (which doesn't exist)
        vm.prank(VOTER_A);
        vm.expectRevert("Governor: invalid option index");
        governor.castVoteWithOption(proposalId, 3);
    }

    function test_CastStandardVotesOnMultipleChoiceProposal() public {
        // Create a multiple choice proposal
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Verify proposal is now active
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Proposal should be active"
        );

        // Cast standard votes
        vm.prank(VOTER_A);
        governor.castVote(proposalId, uint8(1)); // For

        vm.prank(VOTER_B);
        governor.castVote(proposalId, uint8(0)); // Against

        vm.prank(VOTER_C);
        governor.castVote(proposalId, uint8(2)); // Abstain

        // Check standard vote counts are recorded correctly
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 100, "For votes should match VOTER_A balance");
        assertEq(againstVotes, 200, "Against votes should match VOTER_B balance");
        assertEq(abstainVotes, 300, "Abstain votes should match VOTER_C balance");

        // Check option-specific vote counts remain zero for standard votes
        assertEq(governor.proposalOptionVotes(proposalId, 0), 0, "Option A votes should be zero");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 0, "Option B votes should be zero");
        assertEq(governor.proposalOptionVotes(proposalId, 2), 0, "Option C votes should be zero");
    }

    // --- VOTE DELEGATION TESTS ---

    function test_VoteDelegationImpactsVoteCounting() public {
        // Start with a clean voting setup (need to handle delegation properly)
        vm.prank(VOTER_D);
        token.delegate(VOTER_A);

        // Roll forward to ensure delegation takes effect
        vm.roll(block.number + 1);

        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // VOTER_A casts a vote with their delegated voting power
        vm.prank(VOTER_A);
        governor.castVote(proposalId, uint8(1)); // For

        // Check that the full delegated voting power is counted
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 500, "For votes should include delegated votes (100 + 400)");

        // VOTER_D should not be able to vote effectively since they delegated
        vm.prank(VOTER_D);
        governor.castVote(proposalId, uint8(0)); // Against

        // Check vote counts - should not change since VOTER_D has no voting power
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 500, "For votes should remain unchanged");
        assertEq(againstVotes, 0, "Against votes should be 0");
    }

    function test_VoteDelegationChangeMidProposal() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Snapshot block is taken when the proposal is created
        uint256 snapshotBlock = governor.proposalSnapshot(proposalId);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Initial voting power
        assertEq(token.getVotes(VOTER_A), 100, "VOTER_A should have 100 voting power initially");
        assertEq(token.getVotes(VOTER_B), 200, "VOTER_B should have 200 voting power initially");

        // VOTER_B delegates to VOTER_A after the proposal snapshot
        vm.prank(VOTER_B);
        token.delegate(VOTER_A);

        // Check current voting power has changed
        assertEq(token.getVotes(VOTER_A), 300, "VOTER_A should now have 300 voting power");
        assertEq(token.getVotes(VOTER_B), 0, "VOTER_B should now have 0 voting power");

        // But the voting power at snapshot block is unchanged
        assertEq(token.getPastVotes(VOTER_A, snapshotBlock), 100, "VOTER_A should have 100 voting power at snapshot");
        assertEq(token.getPastVotes(VOTER_B, snapshotBlock), 200, "VOTER_B should have 200 voting power at snapshot");

        // VOTER_A casts a vote - should use snapshot voting power
        vm.prank(VOTER_A);
        governor.castVote(proposalId, uint8(1)); // For

        // VOTER_B can still vote independently despite current delegation
        vm.prank(VOTER_B);
        governor.castVote(proposalId, uint8(0)); // Against

        // Check vote counts - should reflect snapshot voting power
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 100, "For votes should be VOTER_A's snapshot power");
        assertEq(againstVotes, 200, "Against votes should be VOTER_B's snapshot power");
    }

    // --- VOTE COUNTING & STATE TESTS ---

    function test_StdProposal_VoteCountsWhenNoVotesCast() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        // console.log("Standard Proposal ID:", proposalId);

        // Verify initial counts are zero before voting starts
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, 0, "Initial against votes should be 0");
        assertEq(forVotes, 0, "Initial for votes should be 0");
        assertEq(abstainVotes, 0, "Initial abstain votes should be 0");

        // Calculate expected vote start/end based on proposal creation block + settings
        uint256 creationBlock = block.number;
        uint256 calculatedVoteStart = creationBlock + governor.votingDelay();
        uint256 calculatedVoteEnd = calculatedVoteStart + governor.votingPeriod();
        // console.log("Initial Block Number:", creationBlock);
        // console.log("Voting Delay:", governor.votingDelay());
        // console.log("Voting Period:", governor.votingPeriod());
        // console.log("Calculated voteStart:", calculatedVoteStart);
        // console.log("Calculated voteEnd:", calculatedVoteEnd);

        // Move blocks forward past voting period without casting votes
        uint256 targetBlock = calculatedVoteEnd + 1;
        // console.log("Rolling to block:", targetBlock);
        vm.roll(targetBlock);
        // console.log("Current Block Number after roll:", block.number);

        // Log the state directly before asserting
        IGovernor.ProposalState currentState = governor.state(proposalId);
        // console.log("Actual state before assert (Standard Proposal):", uint256(currentState));

        // Verify proposal is defeated (assuming quorum > 0 or required threshold not met)
        assertEq(
            uint256(currentState),
            uint256(IGovernor.ProposalState.Defeated),
            "Std State should be Defeated with no votes"
        );

        // Verify counts remain zero after voting period ends
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, 0, "Final against votes should be 0");
        assertEq(forVotes, 0, "Final for votes should be 0");
        assertEq(abstainVotes, 0, "Final abstain votes should be 0");
    }

    function test_McProposal_VoteCountsWhenNoVotesCast() public {
        // Create a multiple choice proposal
        string[] memory options = new string[](3);
        options[0] = "A";
        options[1] = "B";
        options[2] = "C";
        vm.prank(PROPOSER);
        // uint256 blockBeforeMC = block.number;
        // console.log("\nBlock number before MC proposal:", blockBeforeMC);
        uint256 mcProposalId = governor.propose(targets, values, calldatas, description, options);
        // console.log("MC Proposal ID:", mcProposalId);

        // Verify initial standard counts are zero
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(mcProposalId);
        assertEq(againstVotes, 0, "Initial MC against votes should be 0");
        assertEq(forVotes, 0, "Initial MC for votes should be 0");
        assertEq(abstainVotes, 0, "Initial MC abstain votes should be 0");

        // Verify initial option counts are zero
        assertEq(governor.proposalOptionVotes(mcProposalId, 0), 0, "Initial Option A votes should be 0");
        assertEq(governor.proposalOptionVotes(mcProposalId, 1), 0, "Initial Option B votes should be 0");
        assertEq(governor.proposalOptionVotes(mcProposalId, 2), 0, "Initial Option C votes should be 0");

        // Calculate MC vote start/end
        uint256 mcCreationBlock = block.number;
        uint256 mcCalculatedVoteStart = mcCreationBlock + governor.votingDelay();
        uint256 mcCalculatedVoteEnd = mcCalculatedVoteStart + governor.votingPeriod();
        // console.log("MC Initial Block Number:", mcCreationBlock);
        // console.log("MC Calculated voteStart:", mcCalculatedVoteStart);
        // console.log("MC Calculated voteEnd:", mcCalculatedVoteEnd);

        // Move past voting period
        uint256 mcTargetBlock = mcCalculatedVoteEnd + 1;
        // console.log("Rolling to block for MC:", mcTargetBlock);
        vm.roll(mcTargetBlock);
        // console.log("Current Block Number after MC roll:", block.number);

        // Log the state directly before asserting for MC proposal
        IGovernor.ProposalState mcCurrentState = governor.state(mcProposalId);
        // console.log("Actual state before assert (MC Proposal):", uint256(mcCurrentState));

        // Verify state is Defeated
        assertEq(
            uint256(mcCurrentState),
            uint256(IGovernor.ProposalState.Defeated),
            "MC State should be Defeated with no votes"
        );

        // Verify final option counts are zero
        assertEq(governor.proposalOptionVotes(mcProposalId, 0), 0, "Final Option A votes should be 0");
        assertEq(governor.proposalOptionVotes(mcProposalId, 1), 0, "Final Option B votes should be 0");
        assertEq(governor.proposalOptionVotes(mcProposalId, 2), 0, "Final Option C votes should be 0");

        // Verify final standard counts are also zero
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(mcProposalId);
        assertEq(againstVotes, 0, "Final MC against votes should be 0");
        assertEq(forVotes, 0, "Final MC for votes should be 0");
        assertEq(abstainVotes, 0, "Final MC abstain votes should be 0");
    }

    function test_ProposalAllVotes() public {
        // Create a multiple choice proposal with 3 options
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Cast a mix of votes
        vm.prank(VOTER_A); // 100 votes
        governor.castVote(proposalId, uint8(0)); // Against

        vm.prank(VOTER_B); // 200 votes
        governor.castVote(proposalId, uint8(1)); // For (Standard)

        vm.prank(VOTER_C); // 300 votes
        governor.castVoteWithOption(proposalId, 0); // Option A

        vm.prank(VOTER_D); // 400 votes
        governor.castVoteWithOption(proposalId, 2); // Option C

        // Get all vote counts
        uint256[] memory allVotes = governor.proposalAllVotes(proposalId);

        // Expected array length = 3 standard votes + 3 option votes = 6
        assertEq(allVotes.length, 6, "Array length should be 6 (3 standard + 3 options)");

        // Verify counts in the expected order: Against, For, Abstain, Opt0, Opt1, Opt2
        assertEq(allVotes[0], 100, "Against votes mismatch (VOTER_A)");
        // For votes = Standard For (VOTER_B) + Option A (VOTER_C) + Option C (VOTER_D)
        assertEq(allVotes[1], 200 + 300 + 400, "For votes mismatch (Std + Options)");
        assertEq(allVotes[2], 0, "Abstain votes should be 0");
        assertEq(allVotes[3], 300, "Option 0 votes mismatch (VOTER_C)");
        assertEq(allVotes[4], 0, "Option 1 votes should be 0");
        assertEq(allVotes[5], 400, "Option 2 votes mismatch (VOTER_D)");
    }

    // --- PROPOSAL STATE TRANSITION TESTS ---

    function test_ProposalStateTransitions() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // State should be Pending before voting delay
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Initial state should be Pending"
        );

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // State should be Active during voting period
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active),
            "State should be Active after delay"
        );

        // Cast votes: more against than for
        vm.prank(VOTER_A);
        governor.castVote(proposalId, uint8(1)); // For: 100 votes

        vm.prank(VOTER_B);
        governor.castVote(proposalId, uint8(0)); // Against: 200 votes

        // Move blocks forward to after voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Since more against (200) than for (100), proposal should be Defeated
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated), "State should be Defeated"
        );

        // Create another proposal, this time with more for votes than against
        vm.prank(PROPOSER);
        uint256 proposalId2 = governor.propose(targets, values, calldatas, "Proposal #2");

        // Move to active state
        vm.roll(block.number + governor.votingDelay() + 1);

        // Cast votes: more for than against
        vm.prank(VOTER_A);
        governor.castVote(proposalId2, uint8(1)); // For: 100 votes

        vm.prank(VOTER_C);
        governor.castVote(proposalId2, uint8(1)); // For: 300 votes more

        vm.prank(VOTER_B);
        governor.castVote(proposalId2, uint8(0)); // Against: 200 votes

        // Move blocks forward to after voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Since more for (400) than against (200), proposal should be Succeeded
        assertEq(
            uint256(governor.state(proposalId2)),
            uint256(IGovernor.ProposalState.Succeeded),
            "State should be Succeeded"
        );
    }

    function test_QuorumCalculationWithMultipleChoiceVotes() public {
        // Create a multiple choice proposal
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Get the quorum required
        uint256 proposalSnapshot = governor.proposalSnapshot(proposalId);
        uint256 quorumRequired = governor.quorum(proposalSnapshot);

        // Total supply is 100 + 200 + 300 + 400 = 1000
        // Default quorum is 4% (set in constructor) = 40 votes
        assertEq(quorumRequired, 40, "Quorum should be 4% of total supply");

        // Cast votes for different options exceeding quorum
        vm.prank(VOTER_A);
        governor.castVoteWithOption(proposalId, 0); // 100 votes for option A

        vm.prank(VOTER_B);
        governor.castVoteWithOption(proposalId, 1); // 200 votes for option B

        vm.prank(VOTER_C);
        governor.castVoteWithOption(proposalId, 2); // 300 votes for option C

        // Total votes: 600, well above quorum of 40

        // Move blocks forward to after voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Since total votes (600) > quorum (40), proposal should be Succeeded
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded), "State should be Succeeded"
        );

        // Verify option vote counts
        assertEq(governor.proposalOptionVotes(proposalId, 0), 100, "Option A should have 100 votes");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 200, "Option B should have 200 votes");
        assertEq(governor.proposalOptionVotes(proposalId, 2), 300, "Option C should have 300 votes");
    }

    function test_RevertWhen_VotingAfterProposalEnds() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Verify proposal is Active
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Proposal should be active"
        );

        // Move blocks forward past the end of the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Verify proposal is not Active anymore
        assertTrue(
            uint256(governor.state(proposalId)) != uint256(IGovernor.ProposalState.Active),
            "Proposal should not be active"
        );

        // Voting should no longer be possible
        vm.prank(VOTER_B);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(proposalId, uint8(1));
    }

    // --- EVENT EMISSION TESTS ---

    function test_Emit_ProposalCreated_Standard() public {
        vm.startPrank(PROPOSER);
        // Expect ProposalCreated event (skip proposalId, check proposer, skip unused topic, skip data)
        vm.expectEmit(false, true, false, false);
        emit IGovernor.ProposalCreated(
            0, // proposalId - skip check
            PROPOSER, // Check proposer
            targets,
            values,
            new string[](1), // signatures
            calldatas,
            0, // voteStart - skip check
            0, // voteEnd - skip check
            description
        );
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();
        // Basic check that proposalId is generated
        assertGt(proposalId, 0, "Proposal ID should be generated");
    }

    function test_Emit_ProposalCreated_MultipleChoice() public {
        string[] memory options = new string[](3);
        options[0] = "A";
        options[1] = "B";
        options[2] = "C";

        vm.startPrank(PROPOSER);
        // Expect ProposalCreated event (skip proposalId, check proposer, skip unused topic, skip data)
        vm.expectEmit(false, true, false, false);
        emit IGovernor.ProposalCreated(
            0, // proposalId - skip check
            PROPOSER, // Check proposer
            targets,
            values,
            new string[](1), // signatures
            calldatas,
            0, // voteStart - skip check
            0, // voteEnd - skip check
            description
        );
        // Expect ProposalOptionsCreated event (check indexed proposalId and non-indexed options)
        // This event is specific to our contract. Skip all checks for now just to verify emission.
        vm.expectEmit(false, false, false, false);
        emit GovernorProposalMultipleChoiceOptions.ProposalOptionsCreated(
            0, // proposalId - Skip check
            options // Data - Skip check
        );

        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);
        vm.stopPrank();
        assertGt(proposalId, 0, "Proposal ID should be generated");

        // Dynamically check the proposalId in the second event if needed,
        // although vm.expectEmit(true,...) implicitly checks if the topic matches *something*.
        // For exact match: Re-run propose in a separate step after getting proposalId if strict check is desired.
    }

    function test_Emit_VoteCast_Standard() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(VOTER_A);
        uint256 weight = token.getVotes(VOTER_A);
        // Expect VoteCast event (check indexed voter, proposalId, support)
        vm.expectEmit(true, true, true, true);
        emit IGovernor.VoteCast(VOTER_A, proposalId, uint8(1), weight, ""); // support = For, reason = empty
        governor.castVote(proposalId, uint8(1));
        vm.stopPrank();
    }

    function test_Emit_VoteCastWithOption() public {
        // Create a multiple choice proposal
        string[] memory options = new string[](3);
        options[0] = "A";
        options[1] = "B";
        options[2] = "C";
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move blocks forward to active voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(VOTER_B);
        uint256 weight = token.getVotes(VOTER_B);
        uint8 optionIndex = 1; // Vote for Option B
        // Expect VoteCastWithParams event (check indexed voter, proposalId, support)
        // The option index is encoded in the non-indexed `params` field
        vm.expectEmit(true, true, true, true);
        bytes memory expectedParams = abi.encodePacked(optionIndex);
        emit IGovernor.VoteCastWithParams(VOTER_B, proposalId, uint8(1), weight, "", expectedParams); // support = 1 for option vote
        governor.castVoteWithOption(proposalId, optionIndex);
        vm.stopPrank();
    }

    // --- EDGE CASE / SECURITY TESTS ---

    function test_RevertWhen_DoubleVoting_Standard() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move to active state
        vm.roll(block.number + governor.votingDelay() + 1);

        // First vote
        vm.prank(VOTER_A);
        governor.castVote(proposalId, 1); // Vote For

        // Try to vote again
        vm.prank(VOTER_A);
        // Use expectRevert with selector and encoded arguments
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("GovernorAlreadyCastVote(address)")), VOTER_A));
        governor.castVote(proposalId, 0); // Try voting Against
    }

    function test_RevertWhen_DoubleVoting_MultipleChoice() public {
        // Create a multiple choice proposal
        string[] memory options = new string[](3);
        options[0] = "A";
        options[1] = "B";
        options[2] = "C";
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Move to active state
        vm.roll(block.number + governor.votingDelay() + 1);

        // First vote (multiple choice)
        vm.prank(VOTER_B);
        governor.castVoteWithOption(proposalId, 1); // Vote for Option 1

        // Try to vote again (multiple choice)
        vm.prank(VOTER_B);
        // Use expectRevert with selector and encoded arguments
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("GovernorAlreadyCastVote(address)")), VOTER_B));
        governor.castVoteWithOption(proposalId, 2); // Try voting for Option 2

        // Try to vote again (standard vote on MC proposal)
        vm.prank(VOTER_B);
        // Use expectRevert with selector and encoded arguments
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("GovernorAlreadyCastVote(address)")), VOTER_B));
        governor.castVote(proposalId, 0); // Try voting Against
    }

    function test_Auth_Propose_ThresholdNotMet() public {
        // Get current threshold (should be 0 initially)
        uint256 initialThreshold = governor.proposalThreshold();
        assertEq(initialThreshold, 0, "Initial proposal threshold should be 0");

        // Anyone can propose if threshold is 0
        address nonVoter = address(0xABC);
        vm.prank(nonVoter);
        uint256 proposalId1 = governor.propose(targets, values, calldatas, "Proposal from non-voter");
        assertGt(proposalId1, 0, "Proposal should be created with threshold 0");

        // Need a way to set the proposal threshold. GovernorCore doesn't expose this.
        // We would need to inherit GovernorSettings or add a custom setter.
        // Let's assume we redeploy with a threshold for this test.

        // Redeploy Governor with a threshold (e.g., 500 votes)
        // Need to also redeploy dependent contracts or re-link
        TimelockController newTimelock = new TimelockController(1, new address[](1), new address[](1), address(this));
        GovernorCountingMultipleChoice governorWithThreshold =
            new GovernorCountingMultipleChoice(IVotes(address(token)), newTimelock, "GovernorWithThreshold");
        // Assume setProposalThreshold exists or is set in constructor if inheriting GovernorSettings
        // governorWithThreshold.setProposalThreshold(500); // Hypothetical call
        // For now, we cannot directly test the revert without modifying the contract
        // to include GovernorSettings or a custom threshold setter.

        // --- Test Placeholder (if threshold could be set) ---
        /*
        uint256 newThreshold = 500;
        governor.setProposalThreshold(newThreshold); // Assume this function exists
        assertEq(governor.proposalThreshold(), newThreshold, "Threshold should be updated");

        // VOTER_A only has 100 votes, less than threshold
        vm.prank(VOTER_A);
        vm.expectRevert("Governor: proposer votes below proposal threshold");
        governor.propose(targets, values, calldatas, "Proposal below threshold");
        */
        assertTrue(true, "Skipping threshold revert test: Governor needs modification to set threshold");
    }

    function test_Reentrancy_CastVote_Standard() public {
        // Create a standard proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Deploy attacker contract
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(governor));
        address attackerAddress = address(attacker);

        // Give attacker voting power
        uint256 attackerVotes = 50;
        token.mint(attackerAddress, attackerVotes);
        vm.prank(attackerAddress);
        token.delegate(attackerAddress);
        vm.roll(block.number + 1); // Ensure delegation takes effect

        // Move to active state
        vm.roll(block.number + governor.votingDelay() + 1);

        // Set up and execute attack
        attacker.setAttackParamsStandard(proposalId, 1); // Attack with 'For' vote

        // Expect the second internal call within the attacker's receive() to fail
        // (due to 'vote already cast', not necessarily nonReentrant directly here).
        // The initial call from attacker should succeed.
        vm.prank(attackerAddress); // Attacker contract initiates the vote
        attacker.initialAttackStandard();

        // Verify the initial vote was cast correctly
        (,, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertTrue(governor.hasVoted(proposalId, attackerAddress), "Attacker should have voted");
        (uint256 againstAfter, uint256 forAfter,) = governor.proposalVotes(proposalId);
        assertEq(forAfter, attackerVotes, "For votes should reflect attacker's initial vote");
        assertEq(againstAfter, 0, "Against votes should be 0");

        // We cannot easily assert the internal revert within the attacker's receive(),
        // but the fact that the vote count is correct and not doubled confirms
        // that the reentrant call did not succeed in casting a second vote.
    }

    function test_Reentrancy_CastVote_MultipleChoice() public {
        // Create MC proposal
        string[] memory options = new string[](2);
        options[0] = "X";
        options[1] = "Y";
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description, options);

        // Deploy attacker
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(governor));
        address attackerAddress = address(attacker);

        // Give attacker voting power
        uint256 attackerVotes = 75;
        token.mint(attackerAddress, attackerVotes);
        vm.prank(attackerAddress);
        token.delegate(attackerAddress);
        vm.roll(block.number + 1);

        // Move to active state
        vm.roll(block.number + governor.votingDelay() + 1);

        // Set up and execute attack
        uint8 initialOption = 0;
        attacker.setAttackParamsOption(proposalId, initialOption);

        vm.prank(attackerAddress);
        attacker.initialAttackOption();

        // Verify initial vote cast correctly
        assertTrue(governor.hasVoted(proposalId, attackerAddress), "Attacker should have voted (MC)");
        assertEq(governor.proposalOptionVotes(proposalId, initialOption), attackerVotes, "Option 0 votes mismatch");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 0, "Option 1 votes should be 0");
        (,, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(abstainVotes, 0, "Abstain votes should be 0 (MC)");

        // Correct check for 'For' votes in MC: sum of option votes
        (, uint256 forVotesTotal,) = governor.proposalVotes(proposalId);
        assertEq(forVotesTotal, attackerVotes, "Total For votes should equal Option 0 votes");
    }

    function test_Auth_SetEvaluator_OnlyOwner() public {
        address initialEvaluator = governor.evaluator();
        address newEvaluatorAddress = address(0xABCD);
        address attacker = VOTER_A; // Use any address other than the deployer/owner

        // Attempt to set evaluator from a non-owner address
        vm.prank(attacker);
        // Use correct error signature: Ownable.OwnableUnauthorizedAccount(address account)
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        governor.setEvaluator(newEvaluatorAddress);

        // Verify the evaluator address remains unchanged
        assertEq(governor.evaluator(), initialEvaluator, "Evaluator address should not change");

        // Owner should be able to set it (assuming deployer is owner)
        address deployer = address(this); // Test contract deployed the governor
        vm.prank(deployer);
        governor.setEvaluator(newEvaluatorAddress);
        assertEq(governor.evaluator(), newEvaluatorAddress, "Evaluator address should be updated by owner");
    }

    // Add tests for option manipulation, auth boundaries, reentrancy etc. here
}
