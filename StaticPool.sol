// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {PermissionControl} from "./permission/PermissionControl.sol";
import {ABDKMath64x64} from "./libs/ABDKMath64x64.sol";
import {Vault} from "./libs/Vault.sol";

import {IDynamicFarm} from "./interfaces/IDynamicFarm.sol";
import {IStaticPool} from "./interfaces/IStaticPool.sol";
import {IFarmTokenProvider} from "./interfaces/IFarmTokenProvider.sol";
import {IEpoch} from "./interfaces/IEpoch.sol";
import {IERC20Burn} from "./interfaces/IERC20Burn.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";
import {ICard} from "./interfaces/ICard.sol";
import {IFamily} from "./interfaces/IFamily.sol";

contract StaticPool is
    Initializable,
    PermissionControl,
    IFarmTokenProvider,
    IStaticPool,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 用户信息.
    struct UserInfo {
        uint256 reward; // 累计未提取收益
        uint256 taked; // 累计已提取收益
        uint256 power; // 算力
        uint256 rewardDebt; // 债务率
    }
    // 投入资产
    struct Capital {
        address token; // 资产代币
        uint256 radio; // 每次投入的usdt去向pancke的比例
        uint256 minValueOnce; // 单次最小投入额度
        address[] buyPath; // 投入比例
        bool burnOrDead; // 销毁形式
    }

    /// @notice 用户信息
    mapping(address => UserInfo) public userInfoOf;

    /// @notice 奖励代币
    address private rewardToken;
    /// @notice usdt地址
    address private usdt;
    /// @notice 投入X的占比
    uint256 public xRadio;
    /// @notice 时间节点
    address private epoch;
    /// @notice swap路由
    address private router;
    /// @notice pancke路由
    address private pancakeRouter;
    /// @notice 动态矿池
    address private dFarm;
    /// @notice 奖励金库
    address public override vault;

    /// @notice 矿池累计收益率
    uint256 private accTokenPerShare;
    /// @notice 总算力
    uint256 public override totalPower;
    /// @notice 奖励储备额度
    uint256 public reserve;

    /// @notice 新人池
    address private newPool;

    /// @notice 周奖池
    address private weekPool;

    /// @notice farm
    address private family;

    address private card;

    address[] private buyPath;

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 power,
        uint256 time
    );

    event TakeReward(address indexed user, uint256 reward, uint256 time);

    function initialize(
        address _card,
        address _rewardToken,
        address _usdt,
        address _router,
        address _epoch,
        address _dFarm,
        address _newPool,
        address _weekPool,
        address _family,
        address _pancakeRouter
    ) external initializer {
        __PermissionControl_init();
        __ReentrancyGuard_init();
        card = _card;
        rewardToken = _rewardToken;
        usdt = _usdt;
        router = _router;
        epoch = _epoch;
        dFarm = _dFarm;
        newPool = _newPool;
        weekPool = _weekPool;
        family = _family;
        pancakeRouter = _pancakeRouter;
        xRadio = 0.9e12;
        IERC20Upgradeable(usdt).approve(pancakeRouter, type(uint256).max);
        IERC20Upgradeable(rewardToken).approve(
            pancakeRouter,
            type(uint256).max
        );
        IERC20Upgradeable(usdt).approve(router, type(uint256).max);
        IERC20Upgradeable(rewardToken).approve(router, type(uint256).max);
        vault = address(new Vault(rewardToken));
        buyPath.push(usdt);
        buyPath.push(rewardToken);
    }

    /**
     * @notice 设置投入时Xswap购买比例
     * @param radio 投入代币占比 $amount:szabo
     */
    function setXRadio(uint256 radio) external onlyRole(MANAGER_ROLE) {
        require(radio <= 1e12, "StaticPool: Invalid Radio!");
        xRadio = radio;
    }

    /// @notice 分发奖励
    function distribute() external nonReentrant {
        require(msg.sender == epoch, "StaticPool: Only Epoch");

        uint256 totalReward = IERC20Upgradeable(rewardToken).balanceOf(vault) -
            reserve;

        if (totalReward > 0 && totalPower > 0) {
            accTokenPerShare += (totalReward * 1e12) / totalPower;
        }
        reserve += totalReward;
    }

    /**
     * @notice 用户可领取收益
     * @param account  用户地址
     * @return 用户未领取收益 $amount:ether
     */
    function earned(address account) public view returns (uint256) {
        UserInfo memory user = userInfoOf[account];
        return
            user.reward +
            (user.power * (accTokenPerShare - user.rewardDebt)) /
            1e12;
    }

    function getPowerByUSDT(uint256 amount) public view returns (uint256) {
        // 幂运算
        int128 float = ABDKMath64x64.divu(1.02e12, 1e12);
        int128 pow = ABDKMath64x64.pow(float, IEpoch(epoch).getCurrentEpoch());
        return ABDKMath64x64.mulu(pow, amount);
    }

    /**
     * @notice 质押投入
     * @param amount  usdt 数量 $amount:ether
     */
    function deposit(address cardAddr, uint256 amount) external nonReentrant {
        require(
            ICard(card).ownerOfAddr(cardAddr) != address(0),
            "invalid cardAddr"
        );
        require(amount >= 100e18, "StaticPool: Too Low");

        IERC20Upgradeable(usdt).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        //pancake
        uint256 usdtPanckAmount = (amount * (1e12 - xRadio)) / 1e12;
        if (usdtPanckAmount > 0) {
            _panckeAddLiquidity(usdtPanckAmount / 2);
        }

        //Xswap
        uint256 usdtXAmount = IERC20Upgradeable(usdt).balanceOf(address(this));
        if (usdtXAmount > 0) {
            IPancakeRouter(router).swapExactTokensForTokens(
                usdtXAmount / 2,
                0,
                buyPath,
                address(this),
                block.timestamp
            );
            IPancakeRouter(router).addLiquidity(
                address(rewardToken),
                usdt,
                IERC20Upgradeable(rewardToken).balanceOf(address(this)),
                IERC20Upgradeable(usdt).balanceOf(address(this)),
                0,
                0,
                address(0),
                block.timestamp
            );
        }

        uint256 power = getPowerByUSDT(amount);
        _deposit(cardAddr, power);
        IStaticPool(newPool).deposit(cardAddr, amount);
        IStaticPool(weekPool).deposit(
            IFamily(family).parentOf(cardAddr),
            amount
        );

        emit Deposit(cardAddr, amount, power, block.timestamp);
    }

    function _panckeAddLiquidity(uint256 usdtAmount) internal {
        IPancakeRouter(pancakeRouter).swapExactTokensForTokens(
            usdtAmount,
            0,
            buyPath,
            address(this),
            block.timestamp
        );
        IPancakeRouter(pancakeRouter).addLiquidity(
            address(rewardToken),
            usdt,
            IERC20Upgradeable(rewardToken).balanceOf(address(this)),
            usdtAmount,
            0,
            0,
            address(0),
            block.timestamp
        );
    }

    function _deposit(address account, uint256 amount) internal {
        UserInfo storage user = userInfoOf[account];
        if (user.power > 0) {
            user.reward +=
                (user.power * (accTokenPerShare - user.rewardDebt)) /
                1e12;
        }
        user.power += amount;
        totalPower += amount;
        user.rewardDebt = accTokenPerShare;
    }

    /// @notice 领取收益
    function takeReward(address cardAddr) external {
        require(
            ICard(card).ownerOfAddr(cardAddr) == msg.sender,
            "invalid cardAddr"
        );
        UserInfo storage user = userInfoOf[cardAddr];
        uint256 reward = user.reward +
            (user.power * (accTokenPerShare - user.rewardDebt)) /
            1e12;
        if (reward > 0) {
            user.reward = 0;
            user.rewardDebt = accTokenPerShare;
            user.taked += reward;
            reserve -= reward;
            IERC20Upgradeable(rewardToken).safeTransferFrom(
                vault,
                msg.sender,
                reward
            );
            IDynamicFarm(dFarm).addPowerA(cardAddr, reward);
            emit TakeReward(cardAddr, reward, block.timestamp);
        }
    }

    function ido(
        address account,
        uint256 amount
    ) external onlyRole(DELEGATE_ROLE) {
        _deposit(account, amount);
    }

    /**
     * @notice 卖出复投
     * @param operator 操作者
     * @param to 倒账地址
     * @param tokenId 充能Nft
     */
    function afterSell(
        address operator,
        address to,
        uint256 tokenId
    ) external override nonReentrant {
        operator;
        address[] memory tmpPath = new address[](2);
        tmpPath[0] = usdt;
        tmpPath[1] = rewardToken;
        require(ICard(card).ownerOf(tokenId) != address(0), "invalid cardAddr");
        uint256 usdtAmount = IERC20Upgradeable(usdt).balanceOf(address(this));
        require(usdtAmount > 0, "FarmSellProvider: NO_SELL");
        // 卖出所得usdt45%给用户
        IERC20Upgradeable(usdt).safeTransfer(to, (usdtAmount * 0.45e12) / 1e12);

        // 卖出所得usdt55%回购token销毁
        IPancakeRouter(router).swapExactTokensForTokens(
            IERC20Upgradeable(usdt).balanceOf(address(this)),
            0,
            tmpPath,
            address(this),
            block.timestamp
        );
        if (tokenId > 0) {
            address cardAddr = address(uint160(tokenId));
            IERC20Burn(rewardToken).burn(
                IERC20Upgradeable(rewardToken).balanceOf(address(this))
            );
            uint256 power = getPowerByUSDT((usdtAmount * 0.55e12) / 1e12);

            _deposit(cardAddr, power);

            emit Deposit(cardAddr, usdtAmount, power, block.timestamp);
        }
    }
}
