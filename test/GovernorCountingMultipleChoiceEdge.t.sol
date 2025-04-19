// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernorCountingMultipleChoice} from "src/GovernorCountingMultipleChoice.sol";
import {VotesToken} from "./GovernorCountingMultipleChoice.t.sol"; // Re‑use the test ERC20Votes token
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";

/**
 * @title GovernorCountingMultipleChoiceEdgeTest
 * @dev Focused edge‑case tests that complement the main Governor tests.
 * ‑ Verifies that option votes are *also* counted as `forVotes` (current contract behaviour).
 * ‑ Verifies that casting a plain `For` vote on a multiple‑choice proposal does **not**
 *   increment any option‑specific counters.
 */
contract GovernorCountingMultipleChoiceEdgeTest is Test {
    // Test accounts
    address internal constant VOTER_A = address(201);
    address internal constant VOTER_B = address(202);

    // Contracts under test
    VotesToken internal token;
    TimelockController internal timelock;
    GovernorCountingMultipleChoice internal governor;

    // Generic proposal data (single empty call)
    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas;
    string internal constant DESCRIPTION = "Edge-case proposal";

    function setUp() public {
        // Deploy token and delegate to voters
        token = new VotesToken("EdgeToken", "EDG");
        token.mint(VOTER_A, 100);
        token.mint(VOTER_B, 200);
        vm.startPrank(VOTER_A); token.delegate(VOTER_A); vm.stopPrank();
        vm.startPrank(VOTER_B); token.delegate(VOTER_B); vm.stopPrank();

        // Deploy minimal timelock (1 second delay)
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(1, proposers, executors, address(this));

        // Deploy governor under test
        governor = new GovernorCountingMultipleChoice(IVotes(address(token)), timelock, "EdgeGovernor");

        // Give governor proposer role on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        // Prepare dummy call arrays (1 no‑op transfer)
        targets = new address[](1); targets[0] = address(token);
        values  = new uint256[](1); values[0]  = 0;
        calldatas = new bytes[](1); calldatas[0] = "";
    }

    /// @dev Utility that creates a 3‑option proposal and returns its id.
    function _createThreeOptionProposal() internal returns (uint256 proposalId) {
        string[] memory opts = new string[](3);
        opts[0] = "Opt0";
        opts[1] = "Opt1";
        opts[2] = "Opt2";
        proposalId = governor.propose(targets, values, calldatas, DESCRIPTION, opts);
    }

    function _advanceToActive(uint256 proposalId) internal {
        // Move one block after delay so proposal becomes Active
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
    }

    /* -------------------------------------------------------------------------- */
    /*                               Edge‑case tests                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Option votes should also be counted towards `forVotes` as per the current
     *         governor implementation.
     */
    function test_ForVotesEqualsSumOfOptionVotes() public {
        uint256 proposalId = _createThreeOptionProposal();
        _advanceToActive(proposalId);

        // VOTER_A votes option 0 (weight 100)
        vm.prank(VOTER_A);
        governor.castVoteWithOption(proposalId, 0);

        // VOTER_B votes option 1 (weight 200)
        vm.prank(VOTER_B);
        governor.castVoteWithOption(proposalId, 1);

        // End voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal not succeeded");

        // Fetch aggregate votes
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        // Sanity
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);

        // Fetch option‑specific votes
        uint256 opt0Votes = governor.proposalOptionVotes(proposalId, 0);
        uint256 opt1Votes = governor.proposalOptionVotes(proposalId, 1);
        uint256 opt2Votes = governor.proposalOptionVotes(proposalId, 2);

        // Assertions
        assertEq(opt0Votes, 100, "Opt0 votes mismatch");
        assertEq(opt1Votes, 200, "Opt1 votes mismatch");
        assertEq(opt2Votes, 0,   "Opt2 votes mismatch");
        assertEq(forVotes, opt0Votes + opt1Votes + opt2Votes, "forVotes should equal sum of option votes");
    }

    /**
     * @notice A plain `For` vote (without params) on a multiple‑choice proposal should
     *         NOT increase any option‑specific counters.
     */
    function test_PlainForVoteDoesNotAffectOptionCounters() public {
        uint256 proposalId = _createThreeOptionProposal();
        _advanceToActive(proposalId);

        // VOTER_A casts a plain `For` vote (support == 1) via standard API
        vm.prank(VOTER_A);
        governor.castVote(proposalId, 1);

        // End voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal not succeeded");

        // Aggregate votes: should reflect VOTER_A weight
        (, uint256 forVotes, ) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 100, "forVotes should equal weight of VOTER_A");

        // All option counters must remain zero
        assertEq(governor.proposalOptionVotes(proposalId, 0), 0, "Opt0 should remain 0");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 0, "Opt1 should remain 0");
        assertEq(governor.proposalOptionVotes(proposalId, 2), 0, "Opt2 should remain 0");
    }

    function test_MixedPlainAndOptionForVotesCounting() public {
        uint256 proposalId = _createThreeOptionProposal();
        _advanceToActive(proposalId);

        // Option vote by VOTER_A (weight 100)
        vm.prank(VOTER_A);
        governor.castVoteWithOption(proposalId, 0);

        // Plain `For` vote by VOTER_B (weight 200)
        vm.prank(VOTER_B);
        governor.castVote(proposalId, 1);

        // End voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal not succeeded");

        // Aggregate votes
        (, uint256 forVotes, ) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 300, "Total forVotes should equal 300 (100 + 200)");

        // Option counters
        assertEq(governor.proposalOptionVotes(proposalId, 0), 100, "Opt0 votes mismatch");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 0, "Opt1 votes should be 0");
        assertEq(governor.proposalOptionVotes(proposalId, 2), 0, "Opt2 votes should be 0");
    }

    /**
     * @notice Reverts when attempting to submit an option index with a support value other than 1.
     */
    function test_RevertWhen_OptionVoteWithAgainstSupport() public {
        uint256 proposalId = _createThreeOptionProposal();
        _advanceToActive(proposalId);

        // Prepare params encoding option index 0
        bytes memory params = abi.encodePacked(uint8(0));

        vm.prank(VOTER_A);
        vm.expectRevert(bytes("Governor: Invalid support for option vote (must be 1)"));
        governor.castVoteWithReasonAndParams(proposalId, 0, "", params); // support == 0 (Against)
    }

    /**
     * @notice Reverts when a voter who cast a plain `For` vote attempts to cast an option vote afterwards.
     */
    function test_RevertWhen_DoubleVote_PlainThenOption() public {
        uint256 proposalId = _createThreeOptionProposal();
        _advanceToActive(proposalId);

        // Plain `For` vote first
        vm.prank(VOTER_A);
        governor.castVote(proposalId, 1);

        // Attempt option vote afterwards (should revert)
        vm.prank(VOTER_A);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, VOTER_A));
        governor.castVoteWithOption(proposalId, 0);
    }

    /**
     * @notice When params array has >1 byte, governor should *not* treat it as option vote
     *         (since implementation checks for params.length == 1).
     */
    function test_ParamsWithExtraBytesIgnoredForOption() public {
        uint256 proposalId = _createThreeOptionProposal();
        _advanceToActive(proposalId);

        bytes memory params = abi.encodePacked(uint8(2), uint8(99)); // Extra byte noise

        vm.prank(VOTER_B);
        governor.castVoteWithReasonAndParams(proposalId, 1, "", params); // support == 1 (For)

        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "Proposal not succeeded");

        // No option counter should be incremented
        assertEq(governor.proposalOptionVotes(proposalId, 0), 0, "Opt0 votes should be 0");
        assertEq(governor.proposalOptionVotes(proposalId, 1), 0, "Opt1 votes should be 0");
        assertEq(governor.proposalOptionVotes(proposalId, 2), 0, "Opt2 votes should be 0");

        // Aggregate forVotes should reflect VOTER_B weight
        (, uint256 forVotes, ) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 200, "forVotes should equal 200");
    }
} 