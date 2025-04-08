// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTE: This test requires mainnet fork configuration (e.g., RPC URL in foundry.toml or via CLI)

import {Test, console} from "forge-std/Test.sol";
import {GovernorCountingMultipleChoice} from "src/GovernorCountingMultipleChoice.sol";
import {MultipleChoiceEvaluator} from "src/MultipleChoiceEvaluator.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ForkTest
 * @dev Tests the governor system on a forked mainnet environment.
 */
contract ForkTest is Test {
    // Mainnet Addresses (Example: UNI token and a known holder)
    address constant UNI_TOKEN = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant UNI_HOLDER = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8; // Example: Binance 14 wallet
    // We need an address with delegated UNI voting power to propose/vote
    // Finding one easily might be tricky; using a large holder is a starting point.
    // Alternatively, we can mint tokens in the fork if using a mock token, but this uses the real UNI.

    // Use a different address for the proposer if needed
    address constant FORK_PROPOSER = address(0xFA57);

    // Contract instances deployed on the fork
    TimelockController internal forkTimelock;
    GovernorCountingMultipleChoice internal forkGovernor;
    MultipleChoiceEvaluator internal forkEvaluator;

    // Target for proposals
    address constant FORK_TARGET = address(0xCAFE);

    function setUp() public {
        // Specify the block number to fork from for consistency (optional)
        // uint256 blockNumber = 19_000_000;
        try vm.envString("MAINNET_RPC_URL") returns (string memory mainnetRpcUrl) {
            vm.createSelectFork(mainnetRpcUrl); // Forks at latest block by default

            // --- Deploy contracts on the fork ---
            // 1. Deploy Timelock
            address[] memory proposers = new address[](1);
            proposers[0] = address(0); // Placeholder
            address[] memory executors = new address[](1);
            executors[0] = address(0); // Anyone
            forkTimelock = new TimelockController(1, proposers, executors, address(this));

            // 2. Deploy Evaluator
            forkEvaluator = new MultipleChoiceEvaluator(address(0));
            forkEvaluator.setEvaluationStrategy(MultipleChoiceEvaluator.EvaluationStrategy.Plurality);

            // 3. Deploy Governor (using mainnet UNI token)
            forkGovernor = new GovernorCountingMultipleChoice(IVotes(UNI_TOKEN), forkTimelock, "ForkGovernorUNI");
            forkGovernor.setEvaluator(address(forkEvaluator));
            // evaluator.updateGovernor(address(forkGovernor)); // If needed

            // 4. Configure Timelock Roles
            bytes32 proposerRole = forkTimelock.PROPOSER_ROLE();
            bytes32 executorRole = forkTimelock.EXECUTOR_ROLE();
            bytes32 cancellerRole = forkTimelock.CANCELLER_ROLE();
            bytes32 adminRole = forkTimelock.DEFAULT_ADMIN_ROLE();
            forkTimelock.grantRole(proposerRole, address(forkGovernor));
            forkTimelock.grantRole(executorRole, address(0));
            forkTimelock.grantRole(cancellerRole, address(forkGovernor));
            forkTimelock.revokeRole(adminRole, address(this));

            // Give the test contract some Ether for gas
            vm.deal(address(this), 1 ether);
            // Give the proposer some Ether for gas
            vm.deal(FORK_PROPOSER, 1 ether);
        } catch Error(string memory reason) {
            console.log("Setup failed:", reason);
            vm.skip(true); // Skip the test if MAINNET_RPC_URL is not available
        } catch {
            console.log("Setup failed: MAINNET_RPC_URL not available");
            vm.skip(true); // Skip the test if MAINNET_RPC_URL is not available
        }
    }

    // Basic fork test: Propose, vote (requires holder with delegated votes), check state
    function testFork_ProposeVoteStateAndTargetInteraction() public {
        // We need an address that holds UNI *and* has delegated voting power to itself or another controlled account.
        // Using a known EOA with significant delegated power.
        address FORK_VOTER = 0x55FE002aefF02F77364de339a1292923A15844B8; // Corrected checksum

        // Check initial voting power (requires delegation to self on mainnet prior to fork block)
        uint256 voterPower = IVotes(UNI_TOKEN).getVotes(FORK_VOTER);
        console.log("Fork Voter UNI Power:", voterPower);
        // This assertion might fail if the chosen account hasn't delegated or has 0 power at the fork block.
        // Consider adjusting the voter address or removing this assertion if fork testing setup is primary goal.
        assertTrue(voterPower > 0, "Fork voter must have delegated UNI voting power > 0");

        // Give voter Ether
        vm.deal(FORK_VOTER, 1 ether);

        // Proposal Data: Target the UNI token contract, try to transfer 1 UNI from Timelock to FORK_TARGET
        address[] memory targets = new address[](1);
        targets[0] = UNI_TOKEN; // Target the live UNI contract
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        // Calldata for UNI.transfer(FORK_TARGET, 1 * 1e18)
        calldatas[0] = abi.encodeWithSelector(IERC20.transfer.selector, FORK_TARGET, 1 * 1e18);
        string memory description = "Fork Test Proposal - Transfer UNI";
        bytes32 descriptionHash = keccak256(bytes(description));
        string[] memory options = new string[](2);
        options[0] = "Approve Transfer";
        options[1] = "Reject Transfer";

        // --- Proposal ---
        // Use the voter account to propose (assuming they meet threshold, default 0)
        vm.prank(FORK_VOTER);
        uint256 proposalId = forkGovernor.propose(targets, values, calldatas, description, options);
        assertEq(
            uint256(forkGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "Fork State Pending"
        );

        // --- Voting ---
        vm.roll(block.number + forkGovernor.votingDelay() + 1);
        assertEq(uint256(forkGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Fork State Active");

        vm.prank(FORK_VOTER);
        forkGovernor.castVoteWithOption(proposalId, 0); // Vote for Option 0

        // --- State Check ---
        vm.roll(block.number + forkGovernor.votingPeriod() + 1);

        // Check vote counts
        uint256 option0Votes = forkGovernor.proposalOptionVotes(proposalId, 0);
        assertEq(option0Votes, voterPower, "Option 0 votes should match voter power");

        // Check quorum (UNI total supply is large, 4% is significant)
        uint256 snapshot = forkGovernor.proposalSnapshot(proposalId);
        uint256 quorum = forkGovernor.quorum(snapshot);
        console.log("Fork Quorum Required (UNI):", quorum);

        // Determine expected state based on votes vs quorum
        // Since only one voter voted, it likely won't meet UNI quorum.
        bool shouldSucceed = voterPower >= quorum;
        if (shouldSucceed) {
            assertEq(
                uint256(forkGovernor.state(proposalId)),
                uint256(IGovernor.ProposalState.Succeeded),
                "Fork State should be Succeeded"
            );

            // --- Queue & Execute (if Succeeded) ---
            bytes32 operationId =
                forkTimelock.hashOperationBatch(targets, values, calldatas, bytes32(0), descriptionHash);
            forkGovernor.queue(targets, values, calldatas, descriptionHash);
            assertEq(
                uint256(forkGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Queued), "Fork State Queued"
            );
            assertTrue(forkTimelock.isOperationPending(operationId), "Fork Op Pending");

            vm.warp(block.timestamp + forkTimelock.getMinDelay() + 1);
            assertTrue(forkTimelock.isOperationReady(operationId), "Fork Op Ready");

            // Execution will likely fail here unless Timelock has UNI balance and approval
            // We can grant UNI to the timelock using vm.deal for testing execution:
            // address uniWhale = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8; // Binance 14
            // uint256 amountToDeal = 2 * 1e18;
            // vm.startPrank(uniWhale);
            // IERC20(UNI_TOKEN).transfer(address(forkTimelock), amountToDeal);
            // vm.stopPrank();
            // assertGe(IERC20(UNI_TOKEN).balanceOf(address(forkTimelock)), 1 * 1e18);

            // Try executing - expect revert if Timelock lacks funds/approval
            vm.expectRevert(); // Or specific ERC20 error if predictable
            forkGovernor.execute(targets, values, calldatas, descriptionHash);

            // If execution *were* expected to succeed (after dealing UNI):
            // forkGovernor.execute(targets, values, calldatas, descriptionHash);
            // assertEq(uint256(forkGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "Fork State Executed");
            // assertTrue(forkTimelock.isOperationDone(operationId), "Fork Op Done");
            // assertEq(IERC20(UNI_TOKEN).balanceOf(FORK_TARGET), 1 * 1e18, "Fork target should receive UNI");
        } else {
            assertEq(
                uint256(forkGovernor.state(proposalId)),
                uint256(IGovernor.ProposalState.Defeated),
                "Fork State should be Defeated (Quorum Fail)"
            );
            // Attempting to queue a defeated proposal should fail
            vm.expectRevert("Governor: proposal not successful");
            forkGovernor.queue(targets, values, calldatas, descriptionHash);
        }
    }

    // TODO: Add testFork_ReplicateMainnetProposal
    // - Find a real multiple choice proposal from a compatible mainnet Governor.
    // - Fork at the block *before* the proposal was created.
    // - Replicate the proposal creation parameters.
    // - Replicate voter actions using vm.prank and vm.roll.
    // - Assert final state matches the actual mainnet outcome.

    // TODO: Add more fork tests:
    // - Interaction with other live contracts as targets.
    // - Testing against actual proposals on mainnet (requires finding proposal IDs and data).
}
