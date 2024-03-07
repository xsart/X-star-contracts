// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {PermissionControl} from "./permission/PermissionControl.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";

interface IStart {
    function start() external;
}

contract RemoteControl is
    Initializable,
    PermissionControl,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public token;
    address public genesis;
    address public epoch;
    address public card;
    address public lpReceiver;
    address public usdt;
    /// @notice swap路由
    address private router;
    /// @notice pancke路由
    address private pancakeRouter;

    function initialize(
        address _token,
        address _usdt,
        address _epoch,
        address _lpReceiver,
        address _router,
        address _pancakeRouter
    ) external initializer {
        __PermissionControl_init();
        __ReentrancyGuard_init();
        token = _token;
        usdt = _usdt;
        epoch = _epoch;
        lpReceiver = _lpReceiver;
        router = _router;
        pancakeRouter = _pancakeRouter;
        IERC20Upgradeable(usdt).approve(router, type(uint256).max);
        IERC20Upgradeable(token).approve(router, type(uint256).max);
        IERC20Upgradeable(usdt).approve(pancakeRouter, type(uint256).max);
        IERC20Upgradeable(token).approve(pancakeRouter, type(uint256).max);
    }

    function setGenesis(
        address _genesis
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        genesis = _genesis;
    }

    function startGenesis() external onlyRole(MANAGER_ROLE) {
        IStart(genesis).start();
    }

    function startEpoch() external onlyRole(MANAGER_ROLE) {
        uint256 usdtBalance = IERC20Upgradeable(usdt).balanceOf(address(this));
        require(usdtBalance >= 30 * 10000e18, "not enough");
        IPancakeRouter(router).addLiquidity(
            token,
            usdt,
            6000 * 10000e18,
            20 * 10000e18,
            0,
            0,
            epoch,
            block.timestamp
        );

        IPancakeRouter(pancakeRouter).addLiquidity(
            token,
            usdt,
            30 * 10000e18,
            10 * 10000e18,
            0,
            0,
            lpReceiver,
            block.timestamp
        );

        IERC20Upgradeable(token).transfer(lpReceiver, 30 * 10000e18);

        IStart(epoch).start();
    }
}
