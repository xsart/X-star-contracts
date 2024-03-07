// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {PermissionControl} from "./permission/PermissionControl.sol";

contract Random is PermissionControl {
    uint256 private _seed;
    uint256 private _internalRandomSeed;

    function initialize() public initializer {
        __PermissionControl_init();
        _internalRandomSeed = uint256(
            keccak256(
                abi.encodePacked("x0eZes3gugEeeH1yOzMNKmtLI8euB1lJPtUGjBDq")
            )
        );
    }

    function seed() external view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        _seed,
                        _internalRandomSeed >> (_seed % 32)
                    )
                )
            );
    }

    function update() external {
        _seed++;
    }
}
