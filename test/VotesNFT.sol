// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title VotesNFT
 * @dev A simple ERC721 token with voting capabilities for testing
 */
contract VotesNFT is ERC721, ERC721Votes, Ownable {
    uint256 private _nextTokenId;

    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
        EIP712(name, "1")
        Ownable(msg.sender)
    {}
    
    function mint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    // The following functions are overrides required by Solidity.

    function _update(address to, uint256 tokenId, address auth) 
        internal 
        override(ERC721, ERC721Votes) 
        returns (address) 
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 amount) 
        internal 
        override(ERC721, ERC721Votes) 
    {
        super._increaseBalance(account, amount);
    }
} 