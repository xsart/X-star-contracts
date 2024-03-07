// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {PermissionControl} from "./permission/PermissionControl.sol";
import {ABDKMath64x64} from "./libs/ABDKMath64x64.sol";
import {IStaticPool} from "./interfaces/IStaticPool.sol";

contract Genesis is
    Initializable,
    PermissionControl,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private usdt;

    /// @notice usdt接受地址
    address private usdtReceiver;
    address private staticPool;
    /// @notice 用户已购买量
    mapping(address => uint256) public boughtOf;
    /// @notice 每期已认购量
    mapping(uint256 => uint256) public totalBoughtOf;
    uint256 public startTime;

    event Subscribe(address indexed user, uint256 amount, uint256 time);

    function initialize(
        address _usdt,
        address _staticPool,
        address _usdtReceiver
    ) external initializer {
        __PermissionControl_init();
        __ReentrancyGuard_init();
        usdt = _usdt;
        staticPool = _staticPool;
        usdtReceiver = _usdtReceiver;
    }

    /// @notice 开启IDO
    function start() external onlyRole(DELEGATE_ROLE) {
        require(startTime == 0, "it is started");
        startTime = block.timestamp;
    }

    function currentEpoch() public view returns (uint256) {
        return startTime > 0 ? (block.timestamp - startTime) / 1 days : 0;
    }

    /**
     * @notice 获得算力
     * @param amount usdt数量
     * @return 对应算力 $amount:ether
     */
    function getPowerByUSDT(uint256 amount) public view returns (uint256) {
        uint256 epoch = currentEpoch();
        uint256 tmp = epoch <= 2 ? 14 - (2 * epoch) : 0;
        // 幂运算
        int128 float = ABDKMath64x64.divu(1.02e12, 1e12);
        int128 pow = ABDKMath64x64.pow(float, tmp);
        return ABDKMath64x64.mulu(pow, amount);
    }

    /**
     * @notice 创世认购
     * @param amount 愿意支付的usdt数量
     * @param cardAddr 身份nft编号地址
     */
    function subscribe(uint256 amount, address cardAddr) external {
        require(startTime > 0, "it is not started");
        require(currentEpoch() <= 2, "it is over");
        require(amount >= 100e18 && amount <= 1000e18, "100--1000!");
        require(amount % 100e18 == 0, "error amount");
        require(boughtOf[cardAddr] == 0, "only once!");
        require(
            totalBoughtOf[currentEpoch()] + amount <= 100000e18,
            " this epoch over!"
        );
        boughtOf[cardAddr] += amount;
        totalBoughtOf[currentEpoch()] += amount;
        IStaticPool(staticPool).ido(cardAddr, getPowerByUSDT(amount));
        IERC20Upgradeable(usdt).safeTransferFrom(
            msg.sender,
            usdtReceiver,
            amount
        );
        emit Subscribe(msg.sender, amount, block.timestamp);
    }
}
