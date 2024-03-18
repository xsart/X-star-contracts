// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IPancakeRouter} from "../interfaces/IPancakeRouter.sol";
import {IPancakeFactory} from "../interfaces/IPancakeFactory.sol";

interface Ipair {
    function sync() external;
}

interface IRobot {
    function addLiquidity() external;
}

contract XToken is ERC20, Ownable, ERC20Burnable {
    uint256 public buyFee;

    uint256 public sellFee;

    uint256 public sellBurnFee;

    address public buyPreAddress;

    address public robot;

    address public pair;
    address public usdt;
    address public router;
    uint256 public startTime;

    mapping(address => bool) public isBlockedOf;

    mapping(address => bool) public isGuardedOf;

    event Blocked(address indexed user, uint256 indexed time, bool addOrRemove);
    event Guarded(address indexed user, uint256 indexed time, bool addOrRemove);

    error BUG(uint256);

    constructor(
        address _account,
        address _usdt,
        address _router
    ) ERC20("X Token", "X") {
        _mint(_account, 6060 * 10000 * 1e18);

        sellFee = 0.2e12;
        buyFee = 0;
        sellBurnFee = 0.02e12;
        buyPreAddress = _account;
        usdt = _usdt;
        router = _router;

        pair = IPancakeFactory(IPancakeRouter(router).factory()).createPair(
            address(this),
            usdt
        );
        _approve(address(this), router, type(uint256).max);
        IERC20(usdt).approve(router, type(uint256).max);
        isGuardedOf[address(this)] = true;
        isGuardedOf[_account] = true;
        _transferOwnership(_account);
    }

    function setSellFee(uint256 _sellFee) external onlyOwner {
        require(_sellFee <= 1e12, "sellFee must leq 1e12");
        sellFee = _sellFee;
    }

    function setBuyFee(uint256 _buyFee) external onlyOwner {
        require(_buyFee <= 1e12, "buyFee must leq 1e12");
        buyFee = _buyFee;
    }

    function setBuyPreAddress(address _buyPreAddress) external onlyOwner {
        require(_buyPreAddress != address(0), "not zero");
        buyPreAddress = _buyPreAddress;
    }

    function setRobot(address _robot) external onlyOwner {
        require(_robot != address(0), "not zero");
        robot = _robot;
    }

    function isPairsOf(address _pair) internal view returns (bool) {
        return pair == _pair;
    }

    function _burn(address account, uint256 amount) internal override {
        if ((totalSupply() - amount) >= 300000e18) {
            super._burn(account, amount);
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!isBlockedOf[from] && !isBlockedOf[to], "blocked!");

        if (!isGuardedOf[from] && !isGuardedOf[to]) {
            if (buyFee > 0 && isPairsOf(from)) {
                uint256 buyFeeAmount = (amount * buyFee) / 1e12;
                super._transfer(from, buyPreAddress, buyFeeAmount);
                amount -= buyFeeAmount;
            } else if (sellFee > 0 && isPairsOf(to)) {
                uint256 balancePair = IERC20(pair).totalSupply();
                uint256 burnFee = startTime > 0
                    ? (block.timestamp - startTime) / 3 hours
                    : 0;

                if (burnFee > 0 && balancePair > 0) {
                    uint256 burnAmount;
                    uint256 balance = balanceOf(pair);
                    for (uint i = 0; i < burnFee; i++) {
                        burnAmount += balance / 100;
                        balance -= balance / 100;
                    }
                    _burn(pair, burnAmount);
                    Ipair(pair).sync();
                    startTime += 3 hours * burnFee;
                }

                uint256 sellFeeAmount = (amount * sellFee) / 1e12;
                super._transfer(from, robot, sellFeeAmount);
                amount -= sellFeeAmount;

                if (balanceOf(robot) >= 1e18 && balancePair > 0) {
                    IRobot(robot).addLiquidity();
                }

                if ((balanceOf(from) * 9999) / 10000 <= amount) {
                    amount = (balanceOf(from) * 9999) / 10000;
                }
            }
        }

        super._transfer(from, to, amount);
        if (IERC20(pair).totalSupply() > 0 && startTime == 0) {
            startTime = block.timestamp;
        }
    }

    function addGuarded(address account) external onlyOwner {
        require(!isGuardedOf[account], "account already exist");
        isGuardedOf[account] = true;
        emit Guarded(account, block.timestamp, true);
    }

    function removeGuarded(address account) external onlyOwner {
        require(isGuardedOf[account], "account not exist");
        isGuardedOf[account] = false;
        emit Guarded(account, block.timestamp, false);
    }

    function addBlocked(address account) external onlyOwner {
        require(!isBlockedOf[account], "account already exist");
        isBlockedOf[account] = true;
        emit Blocked(account, block.timestamp, true);
    }

    function removeBlocked(address account) external onlyOwner {
        require(isBlockedOf[account], "account not exist");
        isBlockedOf[account] = false;
        emit Blocked(account, block.timestamp, false);
    }
}
