// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {PermissionControl} from "./permission/PermissionControl.sol";
import {IEpoch, RewardType} from "./interfaces/IEpoch.sol";
import {IDynamicFarm} from "./interfaces/IDynamicFarm.sol";
import {IStaticPool} from "./interfaces/IStaticPool.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";
import {IERC20Burn} from "./interfaces/IERC20Burn.sol";

contract EpochController is Initializable, PermissionControl, IEpoch {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address private staticPool;
    address private leaguePool;
    address private dynamicFarm;
    address private weekPool;
    address private newPool;

    address private router;
    address private pancakeRouter;
    address private rewardToken;
    address private usdt;
    address public xPair;
    address[] private buyPath;

    uint256 private period;
    uint256 private startTime;
    uint256 private lastExecutedAt;

    uint256 public removeRadio;
    /// @notice 回购X的占比
    uint256 public xRadio;

    uint256 private currentEpoch;

    error BUG(uint256, uint256);

    event ShareOutBonus(
        uint256 indexed epach,
        uint256 totalLiquidity,
        uint256 totalToken,
        uint256 time
    );

    function initialize(
        address _rewardToken,
        address _usdt,
        address _router,
        address _xPair,
        address _pancakeRouter
    ) external initializer {
        __PermissionControl_init();
        rewardToken = _rewardToken;
        router = _router;
        usdt = _usdt;
        xPair = _xPair;
        pancakeRouter = _pancakeRouter;

        IERC20Upgradeable(usdt).approve(router, type(uint256).max);
        IERC20Upgradeable(xPair).approve(router, type(uint256).max);
        IERC20Upgradeable(usdt).approve(pancakeRouter, type(uint256).max);

        buyPath = [usdt, rewardToken];
        period = 1 days;
        removeRadio = 0.001e12;
        xRadio = 0.9e12;
    }

    modifier checkStartTime() {
        require(
            block.timestamp >= startTime && startTime > 0,
            "EpochController: not started yet"
        );

        _;
    }

    modifier checkEpoch() {
        require(callable(), "EpochController: not allowed");

        _;

        lastExecutedAt += period;
        currentEpoch++;
    }

    function start() external onlyRole(DELEGATE_ROLE) {
        require(startTime == 0, "EpochController: it is started");
        startTime = block.timestamp;
        lastExecutedAt = block.timestamp;
    }

    function setRemoveRadio(uint256 radio) external onlyRole(MANAGER_ROLE) {
        require(radio <= 0.01e12, "too big");
        removeRadio = radio;
    }

    function setXRadio(uint256 radio) external onlyRole(MANAGER_ROLE) {
        require(radio <= 1e12, "too big");
        xRadio = radio;
    }

    function setPool(
        address _staticPool,
        address _leaguePool,
        address _dynamicFarm,
        address _weekPool,
        address _newPool
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        staticPool = _staticPool;
        leaguePool = _leaguePool;
        dynamicFarm = _dynamicFarm;
        weekPool = _weekPool;
        newPool = _newPool;
    }

    function shareOutBonus() external checkStartTime checkEpoch {
        // 解除流动性

        uint256 _epoch = currentEpoch;
        uint256 totalLiquidity = (IERC20Upgradeable(xPair).balanceOf(
            address(this)
        ) * removeRadio) / 1e12;

        IPancakeRouter(router).removeLiquidity(
            rewardToken,
            usdt,
            totalLiquidity,
            0,
            0,
            address(this),
            block.timestamp
        );

        // 统计当前的x
        uint256 rewardTokenBalance = IERC20Upgradeable(rewardToken).balanceOf(
            address(this)
        );

        // 静态
        if (IStaticPool(staticPool).totalPower() > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(
                IStaticPool(staticPool).vault(),
                (0.5e12 * rewardTokenBalance) / 1e12
            );
            IStaticPool(staticPool).distribute();
        }

        // 联盟
        if (IStaticPool(leaguePool).totalPower() > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(
                leaguePool,
                (0.03e12 * rewardTokenBalance) / 1e12
            );
            IStaticPool(leaguePool).distribute();
        }

        // 新人池
        IERC20Upgradeable(rewardToken).safeTransfer(
            newPool,
            (0.1e12 * rewardTokenBalance) / 1e12
        );
        IStaticPool(newPool).distribute();
        // 周top
        IERC20Upgradeable(rewardToken).safeTransfer(
            weekPool,
            (0.02e12 * rewardTokenBalance) / 1e12
        );
        IStaticPool(weekPool).distribute();

        if (_epoch > 0) {
            (uint256 shareTotalPower, ) = IDynamicFarm(dynamicFarm)
                .shareRewardOfEpoch(_epoch);
            (uint256 lNodeTotalPower, ) = IDynamicFarm(dynamicFarm)
                .lNodeRewardOfEpoch(_epoch);
            (uint256 hNodeTotalPower, ) = IDynamicFarm(dynamicFarm)
                .hNodeRewardOfEpoch(_epoch);
            // 布道
            if (shareTotalPower > 0) {
                IERC20Upgradeable(rewardToken).safeTransfer(
                    dynamicFarm,
                    (0.25e12 * rewardTokenBalance) / 1e12
                );
                IDynamicFarm(dynamicFarm).distribute(RewardType.share, _epoch);
            }

            // 低节点
            if (lNodeTotalPower > 0) {
                IERC20Upgradeable(rewardToken).safeTransfer(
                    dynamicFarm,
                    (0.05e12 * rewardTokenBalance) / 1e12
                );
                IDynamicFarm(dynamicFarm).distribute(RewardType.lNode, _epoch);
            }
            // 高节点
            if (hNodeTotalPower > 0) {
                IERC20Upgradeable(rewardToken).safeTransfer(
                    dynamicFarm,
                    (0.05e12 * rewardTokenBalance) / 1e12
                );
                IDynamicFarm(dynamicFarm).distribute(RewardType.hNode, _epoch);
            }
        }
        // Xswap回购x
        if (xRadio > 0) {
            uint256 usdtBalance = IERC20Upgradeable(usdt).balanceOf(
                address(this)
            );
            IPancakeRouter(router).swapExactTokensForTokens(
                (usdtBalance * xRadio) / 1e12,
                0,
                buyPath,
                address(this),
                block.timestamp
            );
        }
        // pancke回购x
        if (IERC20Upgradeable(usdt).balanceOf(address(this)) > 0) {
            IPancakeRouter(pancakeRouter).swapExactTokensForTokens(
                IERC20Upgradeable(usdt).balanceOf(address(this)),
                0,
                buyPath,
                address(this),
                block.timestamp
            );
        }
        // 销毁全部x
        if (IERC20Upgradeable(rewardToken).balanceOf(address(this)) > 0) {
            IERC20Burn(rewardToken).burn(
                IERC20Upgradeable(rewardToken).balanceOf(address(this))
            );
        }

        emit ShareOutBonus(
            _epoch,
            totalLiquidity,
            rewardTokenBalance,
            block.timestamp
        );
    }

    function callable() public view returns (bool) {
        return (block.timestamp - lastExecutedAt) / period >= 1;
    }

    function getLastEpoch() public view returns (uint256) {
        return (lastExecutedAt - startTime) / period;
    }

    function getNextEpoch() public view returns (uint256) {
        return currentEpoch + 1;
    }

    function getCurrentEpoch() public view returns (uint256) {
        return currentEpoch;
    }

    function getStartTime() public view returns (uint256) {
        return startTime;
    }
}
