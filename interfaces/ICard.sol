// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ICard {
    function ownerOfAddr(address cardAddr) external view returns (address);

    function currentTokenId() external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function safeMint(address to) external returns (address);

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256);
}
