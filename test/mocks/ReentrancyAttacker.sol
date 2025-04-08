// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorCountingMultipleChoice} from "../../src/GovernorCountingMultipleChoice.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

interface IGovernorReentrancy {
    function castVote(uint256 proposalId, uint8 support) external;
    function castVoteWithOption(uint256 proposalId, uint8 optionIndex) external;
}

contract ReentrancyAttacker {
    IGovernorReentrancy governor;
    uint256 proposalIdToAttack;
    uint8 supportToAttack;
    uint8 optionToAttack;
    bool attackStandard = false;
    bool attackOption = false;
    bool entered = false;

    constructor(address _governor) {
        governor = IGovernorReentrancy(_governor);
    }

    function setAttackParamsStandard(uint256 proposalId, uint8 support) public {
        proposalIdToAttack = proposalId;
        supportToAttack = support;
        attackStandard = true;
        attackOption = false;
    }
    
    function setAttackParamsOption(uint256 proposalId, uint8 optionIndex) public {
        proposalIdToAttack = proposalId;
        optionToAttack = optionIndex;
        attackStandard = false;
        attackOption = true;
    }

    // This function simulates the initial call *from* the attacker contract
    function initialAttackStandard() public {
        attackStandard = true;
        attackOption = false;
        governor.castVote(proposalIdToAttack, supportToAttack);
    }
    
    function initialAttackOption() public {
        attackStandard = false;
        attackOption = true;
        governor.castVoteWithOption(proposalIdToAttack, optionToAttack);
    }

    // Fallback function - would be triggered if governor sent Ether
    receive() external payable {
        if (entered) return; // Prevent infinite loop within the attack itself
        entered = true;
        if (attackStandard) {
             try governor.castVote(proposalIdToAttack, supportToAttack == 1 ? 0 : 1) { // Try voting differently
                // Expected to fail due to nonReentrant or already voted
            } catch { } 
        }
        if (attackOption) {
             try governor.castVoteWithOption(proposalIdToAttack, optionToAttack + 1) { // Try voting differently
                // Expected to fail due to nonReentrant or already voted
            } catch { } 
        }
        entered = false;
    }
    
    // Required for ERC721 tests if attacker holds an NFT
    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        // Similar re-entry logic could be placed here if the token transfer 
        // happened *during* the vote function and called back.
        return this.onERC721Received.selector;
    }
} 