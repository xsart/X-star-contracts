// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface IFarmTokenProvider {
    function afterSell(address operator, address to, uint256 tokenId) external;
}
