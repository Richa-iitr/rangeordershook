// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {RangeOrders} from "./RangeOrders.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "lib/v4-periphery/lib/v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";

contract RangeOrdersHook is BaseHook, RangeOrders {
    using StateLibrary for IPoolManager;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4) {
        poolKey = key;
        lastLowerTicks[key.toId()] = getLowerUsableTick(tick, key.tickSpacing);
        return RangeOrdersHook.afterInitialize.selector;
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, int128) {
        int24 prevTick = lastLowerTicks[key.toId()];
        int24 tick;
        (, tick, , ) = poolManager.getSlot0(key.toId());
        int24 currentTick = getLowerUsableTick(tick, key.tickSpacing);
        tick = prevTick;

        Order[] memory ordersToExecute;
        bool zeroForOne = !params.zeroForOne;

        if (prevTick < currentTick) {
            for (; tick < currentTick; ) {
                ordersToExecute = orders[tick][zeroForOne];

                bytes32[] memory orderIds = new bytes32[](
                    ordersToExecute.length
                );
                uint256 index = 0;
                for (uint256 i = 0; i < ordersToExecute.length; i++) {
                    orderIds[index] = ordersToExecute[i].id;
                    index++;
                    IPoolManager.SwapParams
                        memory orderSwapParams = IPoolManager.SwapParams({
                            zeroForOne: zeroForOne,
                            amountSpecified: int256(ordersToExecute[i].amountIn),
                            sqrtPriceLimitX96: zeroForOne
                                ? MIN_PRICE_LIMIT
                                : MAX_PRICE_LIMIT
                        });
                }
                if (orderIds.length > 0) {
                    emit OrdersQueued(orderIds);
                }
                unchecked {
                    tick += key.tickSpacing;
                }
            }
        } else {
            for (; currentTick < tick; ) {
                ordersToExecute = orders[tick][zeroForOne];
                bytes32[] memory orderIds = new bytes32[](
                    ordersToExecute.length
                );
                uint256 index = 0;
                for (uint256 i = 0; i < ordersToExecute.length; i++) {
                    orderIds[index] = ordersToExecute[i].id;
                    index++;
                    IPoolManager.SwapParams
                        memory orderSwapParams = IPoolManager.SwapParams({
                            zeroForOne: zeroForOne,
                            amountSpecified: int256(ordersToExecute[i].amountIn),
                            sqrtPriceLimitX96: zeroForOne
                                ? MIN_PRICE_LIMIT
                                : MAX_PRICE_LIMIT
                        });
                }
                if (orderIds.length > 0) {
                    emit OrdersQueued(orderIds);
                }
                unchecked {
                    tick -= key.tickSpacing;
                }
            }
        }
        return (RangeOrdersHook.afterSwap.selector, 0);
    }

    //TODO: hook call when??
    function executeOrderAndRedeem(
        bytes32 orderId,
        bytes calldata data
    ) external {
        Order storage order = ordersById[orderId];
        (, int24 currentTick, , ) = poolManager.getSlot0(poolKey.toId());

        if (!checkExecuteOrder(order, currentTick)) {
            revert("RangeOrders: in-valid order");
        }

        address tokenOut = order.zeroForOne
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);
        address tokenIn = order.zeroForOne
            ? Currency.unwrap(poolKey.currency0)
            : Currency.unwrap(poolKey.currency1);
        IERC20(tokenIn).transfer(msg.sender, order.amountIn);

        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "execute(address,address,bytes)",
                tokenIn,
                tokenOut,
                data
            )
        );
        require(success, "RangeOrders: Callback failed");

        order.orderStatus = Status.EXECUTED;

        //redeem
        IERC20(tokenOut).transfer(
            order.user,
            IERC20(tokenOut).balanceOf(address(this))
        );
    }
}
