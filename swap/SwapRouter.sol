// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISwapRouter} from "./swap-interfaces/ISwapRouter.sol";
import {ISwapPair} from "./swap-interfaces/ISwapPair.sol";
import {ISwapFactory} from "./swap-interfaces/ISwapFactory.sol";
import {IFarmTokenProvider} from "../interfaces/IFarmTokenProvider.sol";
import {SafeMath} from "./swap-libs/SafeMath.sol";
import {TransferHelper} from "./swap-libs/TransferHelper.sol";
import {IWETH} from "./swap-interfaces/IWETH.sol";
import {SwapLibrary} from "./swap-libs/SwapLibrary.sol";

contract SwapRouter is ISwapRouter, Ownable {
    using SafeMath for uint256;

    address public override factory;
    address public override WETH;

    /// @notice 是否是农场币
    address public xToken;
    address public staticPool;
    /// @notice 农场币 白名单(允许购买)
    mapping(address => bool) public isGuardedOf;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "SwapRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {}

    /// @notice 依赖注入
    function bind(address _xToken, address _staticPool) external onlyOwner {
        require(xToken == address(0) && staticPool == address(0), "only once");
        // 空投合约
        xToken = _xToken;
        // 空投条件
        staticPool = _staticPool;
    }

    function addGuarded(address account) external onlyOwner {
        require(!isGuardedOf[account], "account already exist");
        isGuardedOf[account] = true;
    }

    function removeGuarded(address account) external onlyOwner {
        require(isGuardedOf[account], "account not exist");
        isGuardedOf[account] = false;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (ISwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ISwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = SwapLibrary.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = SwapLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "SwapRouter: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = SwapLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "SwapRouter: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = SwapLibrary.pairFor(factory, token, WETH);

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ISwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH)
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function _removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = ISwapPair(pair).burn(to);
        (address token0, ) = SwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(amountA >= amountAMin, "SwapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SwapRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint amountA, uint amountB)
    {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ISwapPair(pair).burn(to);
        (address token0, ) = SwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(amountA >= amountAMin, "SwapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SwapRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        (amountToken, amountETH) = _removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        address from,
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        require(path.length == 2, "error");
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = SwapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? SwapLibrary.pairFor(factory, output, path[i + 2])
                : _to;
            if (!isGuardedOf[from] && path[0] == xToken) {
                to = staticPool;
            }
            ISwapPair(SwapLibrary.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
        if (!isGuardedOf[from]) {
            require(path[1] != xToken, "not buy");
            require(msg.value > 0, "not tokenId");
            if (path[0] == xToken) {
                ISwapPair(SwapLibrary.pairFor(factory, path[0], path[1]))
                    .burnToken(xToken, amounts[0]);
                IFarmTokenProvider(staticPool).afterSell(from, _to, msg.value);
            }
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SwapLibrary.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(msg.sender, amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "SwapRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(msg.sender, amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "SwapRouter: INVALID_PATH");
        amounts = SwapLibrary.getAmountsOut(factory, msg.value, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                SwapLibrary.pairFor(factory, path[0], path[1]),
                amounts[0]
            )
        );
        _swap(msg.sender, amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "SwapRouter: INVALID_PATH");
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "SwapRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(msg.sender, amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "SwapRouter: INVALID_PATH");
        amounts = SwapLibrary.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(msg.sender, amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "SwapRouter: INVALID_PATH");
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "SwapRouter: EXCESSIVE_INPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                SwapLibrary.pairFor(factory, path[0], path[1]),
                amounts[0]
            )
        );
        _swap(msg.sender, amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0])
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return SwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return SwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return SwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return SwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return SwapLibrary.getAmountsIn(factory, amountOut, path);
    }

    function takeEth() external {
        payable(msg.sender).transfer(address(this).balance);
    }
}
