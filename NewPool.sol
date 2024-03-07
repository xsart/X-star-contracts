// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {PermissionControl} from "./permission/PermissionControl.sol";
import {IEpoch} from "./interfaces/IEpoch.sol";
import {ICard} from "./interfaces/ICard.sol";

contract NewPool is
    Initializable,
    PermissionControl,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Pool {
        uint256 totalPower;
        uint256 accTokenPerShare;
    }

    /// @notice 奖励代币
    address private rewardToken;
    /// @notice 奖励储备额度
    uint256 public reserve;

    mapping(address => uint256) public userLastEpoch;

    mapping(uint256 => mapping(address => uint256)) public userPowerByEpoch;
    mapping(uint256 => Pool) public poolInfoByEpoch;

    address private card;

    /// @notice 时间节点
    address private epoch;

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

    function deposit(
        address cardAddr,
        uint256 amount
    ) external nonReentrant onlyRole(DELEGATE_ROLE) {
        uint256 currentEpoch = IEpoch(epoch).getCurrentEpoch();
        userPowerByEpoch[currentEpoch][cardAddr] += amount;
        poolInfoByEpoch[currentEpoch].totalPower += amount;
        if (userLastEpoch[cardAddr] == 0) {
            userLastEpoch[cardAddr] = currentEpoch;
        }
    }

    function earn(address cardAddr) public view returns (uint256) {
        uint256 start = userLastEpoch[cardAddr];
        uint256 last = IEpoch(epoch).getCurrentEpoch();
        uint256 total;
        for (uint i = start; i < last; i++) {
            total +=
                (userPowerByEpoch[i][cardAddr] *
                    poolInfoByEpoch[i].accTokenPerShare) /
                1e12;
        }
        return total;
    }

    function takeReward(address cardAddr) external nonReentrant {
        require(
            ICard(card).ownerOfAddr(cardAddr) == msg.sender,
            "invalid cardAddr"
        );
        uint256 start = userLastEpoch[cardAddr];
        uint256 last = IEpoch(epoch).getCurrentEpoch();
        uint256 total;
        for (uint i = start; i < last; i++) {
            total +=
                (userPowerByEpoch[i][cardAddr] *
                    poolInfoByEpoch[i].accTokenPerShare) /
                1e12;
        }

        if (total > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, total);
            reserve -= total;
        }
        userLastEpoch[cardAddr] = last;
    }

    /// @notice 分发奖励
    function distribute() external nonReentrant {
        require(msg.sender == epoch, "StaticPool: Only Epoch");

        uint256 totalReward = IERC20Upgradeable(rewardToken).balanceOf(
            address(this)
        ) - reserve;
        uint256 currentEpoch = IEpoch(epoch).getCurrentEpoch();

        if (totalReward > 0 && poolInfoByEpoch[currentEpoch].totalPower > 0) {
            poolInfoByEpoch[currentEpoch].accTokenPerShare +=
                (totalReward * 1e12) /
                poolInfoByEpoch[currentEpoch].totalPower;
            reserve += totalReward;
        }
    }
}
