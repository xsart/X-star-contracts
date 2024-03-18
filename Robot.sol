// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PermissionControl} from "./permission/PermissionControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";

contract Robot is Initializable, PermissionControl {
    address public token;
    address public router;
    address public usdt;
    address public receiptor;

    function initialize(
        address _token,
        address _usdt,
        address _router,
        address _receiptor
    ) external initializer {
        __PermissionControl_init();
        token = _token;
        router = _router;
        usdt = _usdt;
        receiptor = _receiptor;
        IERC20(token).approve(router, type(uint256).max);
        IERC20(usdt).approve(router, type(uint256).max);
    }

    receive() external payable {}

    function setReceiptor(address account) external onlyRole(MANAGER_ROLE) {
        require(account != address(0), "not zero");
        receiptor = account;
    }

    function addLiquidity() external {
        address[] memory sellPath = new address[](2);
        sellPath[0] = token;
        sellPath[1] = usdt;
        uint256 liquidityReserve = IERC20(token).balanceOf(address(this));

        uint256 useToken = (liquidityReserve * 3) / 4;
        uint256[] memory getUsdt = IPancakeRouter(router).getAmountsOut(
            useToken,
            sellPath
        );
        IPancakeRouter(router).swapExactTokensForTokens(
            useToken,
            (getUsdt[1] * 98) / 100,
            sellPath,
            address(this),
            block.timestamp
        );

        IPancakeRouter(router).addLiquidity(
            token,
            usdt,
            IERC20(token).balanceOf(address(this)),
            IERC20(usdt).balanceOf(address(this)),
            0,
            0,
            address(0),
            block.timestamp
        );
        if (IERC20(usdt).balanceOf(address(this)) > 0) {
            IERC20(usdt).transfer(
                receiptor,
                IERC20(usdt).balanceOf(address(this))
            );
        }
    }
}
