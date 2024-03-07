// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IRandom {
    function seed() external view returns (uint256);
    function update() external;
}