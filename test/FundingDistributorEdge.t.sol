// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FundingDistributor} from "src/FundingDistributor.sol";
import {GovernorCountingMultipleChoice} from "src/GovernorCountingMultipleChoice.sol";
import {VotesToken} from "./GovernorCountingMultipleChoice.t.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract FundingDistributorEdgeTest is Test {
    /* -------------------------------------------------------------------------- */
    /*                              Minimal set‑up                                */
    /* -------------------------------------------------------------------------- */

    address internal constant VOTER = address(0xA0);

    VotesToken internal token;
    TimelockController internal timelock;
    GovernorCountingMultipleChoice internal governor;
    FundingDistributor internal distributor;

    // Proposal scaffolding
    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas;
    string internal constant DESCRIPTION = "Edge distro";
    bytes32 internal descriptionHash;

    function setUp() public {
        // token
        token = new VotesToken("EdgeDistroToken", "EDTK");
        token.mint(VOTER, 100);
        vm.prank(VOTER); token.delegate(VOTER);

        // timelock
        address[] memory proposers = new address[](1); proposers[0] = address(0);
        address[] memory executors = new address[](1); executors[0] = address(0);
        timelock = new TimelockController(1, proposers, executors, address(this));

        // governor
        governor = new GovernorCountingMultipleChoice(IVotes(address(token)), timelock, "EdgeGov");
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        // distributor
        distributor = new FundingDistributor(address(governor), address(timelock), address(this));

        // generic call arrays (placeholder updated later)
        targets = new address[](1); targets[0] = address(distributor);
        values  = new uint256[](1); values[0]  = 0;
        calldatas = new bytes[](1);
        descriptionHash = keccak256(bytes(DESCRIPTION));
    }

    /* -------------------------------------------------------------------------- */
    /*                               Helper flow                                  */
    /* -------------------------------------------------------------------------- */

    function _proposeAndQueue(
        string[] memory options,
        address[] memory recipients,
        uint8 topN,
        uint256 initialBalance
    ) internal returns (uint256 proposalId) {
        // fund distributor
        vm.deal(address(distributor), initialBalance);

        // create proposal with placeholder id 0
        bytes memory tempCall = abi.encodeWithSelector(
            FundingDistributor.distribute.selector,
            uint256(0),
            topN,
            recipients
        );
        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = tempCall;

        proposalId = governor.propose(targets, values, _calldatas, DESCRIPTION, options);

        // advance to active & vote
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(VOTER);
        governor.castVoteWithOption(proposalId, 0);
        vm.roll(block.number + governor.votingPeriod() + 1);
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "not succeeded");

        // schedule with real calldata
        bytes memory realCall = abi.encodeWithSelector(
            FundingDistributor.distribute.selector,
            proposalId,
            topN,
            recipients
        );
        calldatas[0] = realCall;
        vm.prank(address(governor));
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), descriptionHash, 1);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        vm.roll(block.number + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   TESTS                                    */
    /* -------------------------------------------------------------------------- */

    function test_LargeBalanceSingleWinner() public {
        uint256 balance = 9 ether;
        string[] memory options = new string[](3);
        options[0] = "A"; options[1] = "B"; options[2] = "C";
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);
        recipients[2] = address(0x3);
        uint8 topN = 1; // only highest‑vote option wins

        _proposeAndQueue(options, recipients, topN, balance);

        // execute
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);

        assertEq(address(recipients[0]).balance, balance, "winner should receive full balance");
        assertEq(address(recipients[1]).balance, 0);
        assertEq(address(recipients[2]).balance, 0);
        assertEq(address(distributor).balance, 0);
    }

    /* ------------------------- Re‑entrancy simulation ------------------------- */

    function test_Reentrancy_NotPossible() public {
        uint256 balance = 1 ether;
        string[] memory options = new string[](2);
        options[0] = "A";
        options[1] = "B";

        // Deploy reenter recipient that will attempt to re‑enter
        Reenter re = new Reenter(distributor, timelock);

        address[] memory recipients = new address[](2);
        recipients[0] = address(re);
        recipients[1] = address(0xdead);
        uint8 topN = 1;

        _proposeAndQueue(options, recipients, topN, balance);

        // execute – should succeed, transfer goes through, no revert
        timelock.executeBatch(targets, values, calldatas, bytes32(0), descriptionHash);

        assertEq(address(re).balance, balance, "recipient should receive full balance");
        assertEq(address(distributor).balance, 0);
    }
}

// Minimal contract used within re‑entrancy test
contract Reenter {
    FundingDistributor public distributor;
    TimelockController public timelock;

    constructor(FundingDistributor _d, TimelockController _t) {
        distributor = _d;
        timelock = _t;
    }

    receive() external payable {
        // Attempt to re‑enter
        try distributor.distribute(0, 1, new address[](0)) {
        } catch {}
    }
} 