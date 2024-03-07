// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {PermissionControl} from "./permission/PermissionControl.sol";

import {ICard} from "./interfaces/ICard.sol";

contract Family is PermissionControl {
    /// @notice 根地址
    address public rootAddress;

    /// @notice 地址总数
    uint256 public totalAddresses;

    /// @notice 上级检索
    mapping(address => address) public parentOf;

    /// @notice 深度记录
    mapping(address => uint256) public depthOf;

    // 下级检索-直推
    mapping(address => address[]) internal _childrenMapping;

    address public card;

    function initialize(
        address _rootAddress,
        address _card
    ) public initializer {
        __PermissionControl_init();
        require(_rootAddress != address(0), "invalid _rootAddress");
        card = _card;
        rootAddress = _rootAddress;
        //初始树形
        depthOf[_rootAddress] = 1;
        parentOf[_rootAddress] = address(0);
        _childrenMapping[address(0)].push(rootAddress);
    }

    /**
     * @notice 直系家族(父辈)
     *
     * @param owner 查询的用户地址
     * @param depth 查询深度 $number
     *
     * @return 地址列表(从下至上)
     *
     */
    function getForefathers(
        address owner,
        uint256 depth
    ) external view returns (address[] memory) {
        address[] memory forefathers = new address[](depth);
        for (
            (address parent, uint256 i) = (parentOf[owner], 0);
            i < depth && parent != address(0);
            (i++, parent = parentOf[parent])
        ) {
            forefathers[i] = parent;
        }

        return forefathers;
    }

    /// @notice 获取直推列表
    function childrenOf(
        address owner
    ) external view returns (address[] memory) {
        return _childrenMapping[owner];
    }

    /**
     * @notice 下级添加上级
     * @param parentCardAddr 上级身份ID地址
     * @param cardAddr 当前身份ID地址(address(0)代表尚未铸造nft需要系统代理铸造)
     */
    function makeRelation(address parentCardAddr, address cardAddr) external {
        address ownerCard = cardAddr;
        if (ownerCard == address(0)) {
            ownerCard = ICard(card).safeMint(msg.sender);
        }

        require(
            ICard(card).ownerOfAddr(ownerCard) == msg.sender,
            "invalid cardAddr"
        );
        _makeRelationFrom(parentCardAddr, ownerCard);
    }

    function _makeRelationFrom(address parent, address child) internal {
        require(depthOf[parent] > 0, "invalid parent");
        require(depthOf[child] == 0, "invalid child");

        // 累加数量
        totalAddresses++;

        // 上级检索
        parentOf[child] = parent;

        // 深度记录
        depthOf[child] = depthOf[parent] + 1;

        // 下级检索
        _childrenMapping[parent].push(child);
    }
}
