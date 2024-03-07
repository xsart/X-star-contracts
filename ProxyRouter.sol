// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {PermissionControl} from "./permission/PermissionControl.sol";
import {ISwapRouter} from "./swap/swap-interfaces/ISwapRouter.sol";

contract ProxyRouter is Initializable, PermissionControl {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    /// @notice swap路由
    address public router;

    function initialize(address _router) external initializer {
        __PermissionControl_init();
        router = _router;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external {
        IERC20Upgradeable(tokenA).safeTransferFrom(
            msg.sender,
            address(this),
            amountADesired
        );
        IERC20Upgradeable(tokenB).safeTransferFrom(
            msg.sender,
            address(this),
            amountBDesired
        );
        IERC20Upgradeable(tokenA).approve(router, amountADesired);
        IERC20Upgradeable(tokenB).approve(router, amountBDesired);
        ISwapRouter(router).addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
        uint256 balanceA = IERC20Upgradeable(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20Upgradeable(tokenB).balanceOf(address(this));
        if (balanceA > 0) {
            IERC20Upgradeable(tokenA).safeTransfer(msg.sender, balanceA);
        }
        if (balanceB > 0) {
            IERC20Upgradeable(tokenB).safeTransfer(msg.sender, balanceB);
        }
    }
}
