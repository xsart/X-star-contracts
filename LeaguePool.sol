// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {PermissionControl} from "./permission/PermissionControl.sol";
import {ICard} from "./interfaces/ICard.sol";

contract LeaguePool is
    Initializable,
    PermissionControl,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice 用户信息
    mapping(address => uint256) public takedOf;
    /// @notice 奖励储备额度
    uint256 public reserve;
    /// @notice 总算力
    uint256 public constant totalPower = 10;
    /// @notice 奖励代币
    address private rewardToken;
    /// @notice 矿池累计收益率
    uint256 public accTokenPerShare;

    address private card;

    /// @notice 时间节点
    address private epoch;

    event Deposit(address indexed user, uint256 amount, uint256 time);

    event TakeReward(address indexed user, uint256 reward, uint256 time);

    event Withdraw(address indexed user, uint256 amount, uint256 time);

    function initialize(
        address _rewardToken,
        address _card,
        address _epoch
    ) external initializer {
        __PermissionControl_init();
        __ReentrancyGuard_init();
        rewardToken = _rewardToken;
        card = _card;
        epoch = _epoch;
    }

    /// @notice 分发奖励
    function distribute() external nonReentrant {
        require(msg.sender == epoch, "LeaguePool: Only Epoch");

        uint256 totalReward = IERC20Upgradeable(rewardToken).balanceOf(
            address(this)
        ) - reserve;

        if (totalReward > 0 && totalPower > 0) {
            accTokenPerShare += (totalReward * 1e12) / totalPower;
        }
        reserve += totalReward;
    }

    /// @notice 用户收益
    function earned(address cardAddr) public view returns (uint256) {
        if (accTokenPerShare == 0) {
            return 0;
        } else {
            return accTokenPerShare / 1e12 - takedOf[cardAddr];
        }
    }

    /// @notice 领取收益
    function takeReward(address cardAddr) external nonReentrant {
        require(
            ICard(card).ownerOfAddr(cardAddr) == msg.sender,
            "invalid cardAddr"
        );
        uint256 tokenId = uint256(uint160(cardAddr));
        require(tokenId >= 666 && tokenId < 666 + totalPower, "error");
        uint256 reward = earned(cardAddr);
        if (reward > 0) {
            takedOf[cardAddr] += reward;
            reserve -= reward;
            IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, reward);
            emit TakeReward(msg.sender, reward, block.timestamp);
        }
    }
}
