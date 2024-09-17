// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";
import { TestERC20 } from "v4-core/test/TestERC20.sol";
import { IERC20Minimal } from "v4-core/interfaces/external/IERC20Minimal.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { Hooks } from "v4-core/libraries/Hooks.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { PoolManager } from "v4-core/PoolManager.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { PoolSwapTest } from "v4-core/test/PoolSwapTest.sol";
import { PoolDonateTest } from "v4-core/test/PoolDonateTest.sol";
import { CurrencyLibrary, Currency } from "v4-core/types/Currency.sol";
import { RangeOrdersHook } from "../src/RangeOrdersHook.sol";
import { BatchOrderExecutor } from "../src/utils/BatchOrderExecutor.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolModifyLiquidityTest } from "v4-core/test/PoolModifyLiquidityTest.sol";
import { Deployers } from "lib/v4-core/test/utils/Deployers.sol";
import { HookMiner } from "./utils/HookMiner.sol";

contract RangeOrdersTest is Test , Deployers, GasSnapshot{
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolKey poolKey;
    PoolId poolId;
    RangeOrdersHook hook;
    Currency testTokenA;
    Currency testTokenB;
    TestERC20 token0;
    TestERC20 token1;

    function setUp() public {
        deployFreshManagerAndRouters();
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(address(this), flags, type(RangeOrdersHook).creationCode, abi.encode(manager));
        hook = new RangeOrdersHook{ salt: salt }(manager);

        (testTokenA, testTokenB) = deployMintAndApprove2Currencies();

        if (testTokenA < testTokenB) {
            token0 = TestERC20(Currency.unwrap(testTokenA));
            token1 = TestERC20(Currency.unwrap(testTokenB));
        } else {
            token0 = TestERC20(Currency.unwrap(testTokenB));
            token1 = TestERC20(Currency.unwrap(testTokenA));
        }

        // pool liquidity
        (poolKey, poolId) = initPoolAndAddLiquidity(testTokenA, testTokenB, hook, 5000, SQRT_PRICE_1_1, ZERO_BYTES);

        token0.approve(address(swapRouter), 100 ether);
        token1.approve(address(swapRouter), 100 ether);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
    }

    function test_cancel() public {
        uint256 amount = 1 ether;
        token0.approve(address(hook), amount);

        bytes32 orderId = hook.placeOrder(RangeOrdersHook.OrderType.BUYSTOP, amount, 100, poolKey, 100);
        hook.cancelOrder(orderId);

        RangeOrdersHook.Order memory order = hook.getOrder(orderId);
        assertEq(uint256(order.orderStatus), uint256(RangeOrdersHook.Status.CANCELED));
    }

    function test_executeOrder() public {
        int24 tick = 100;
        uint256 amount = 1 ether;
        token0.approve(address(hook), amount);


        address user = vm.addr(122);
        vm.startPrank(user);
        uint256 balanceBefore = token0.balanceOf(address(user));
    
        token0.mint(user, 100 ether);

        // place order
        bytes32 orderId = hook.placeOrder(RangeOrdersHook.OrderType.BUYSTOP, amount, tick, poolKey, tick);
        assertEq(token0.balanceOf(address(user)), balanceBefore - amount);
        vm.stopPrank();

        RangeOrdersHook.Order memory order = hook.getOrder(orderId);

        // swap 
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({ takeClaims: true, settleUsingBurn: false });
        swapRouter.swap(poolKey, params, testSettings, ZERO_BYTES);

        // execute order
        address executor = vm.addr(131);
        vm.startPrank(executor);
        BatchOrderExecutor orderExecutor = new BatchOrderExecutor();
        token0.mint(address(orderExecutor), 10000 * 10 ** 18);
        token1.mint(address(orderExecutor), 10000 * 10 ** 18);

        uint256 balanceBefore1 = token1.balanceOf(address(order.user));
        BatchOrderExecutor.Action[] memory actions = new BatchOrderExecutor.Action[](1);
        actions[0] = BatchOrderExecutor.Action({
            destination: address(token1),
            amount: 0,
            data: abi.encodeWithSelector(TestERC20.transfer.selector, address(order.user), 1 * 10 ** 18) 
         });
        orderExecutor.executeSettlement(address(hook), order.id, actions);
        uint256 balanceAfter1 = token1.balanceOf(address(order.user));

        assertEq(balanceAfter1 - balanceBefore1, 1 * 10 ** 18);
        vm.stopPrank();
    }
}
