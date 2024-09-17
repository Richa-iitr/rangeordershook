// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {TickMath} from "v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";

import {PoolId, PoolIdLibrary} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";

import {FixedPointMathLib} from "lib/v4-periphery/lib/v4-core/lib/solmate/src/utils/FixedPointMathLib.sol";
import {IERC20} from "lib/v4-periphery/lib/v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Events} from "./utils/Events.sol";

contract RangeOrders is Events {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

    mapping(PoolId poolId => mapping(int24 tickToSellAt => mapping(bool zeroForOne => uint256 inputAmount)))
        public pendingOrders;

    mapping(PoolId poolId => int24 lowerTick) public lastLowerTicks;
    mapping(uint256 positionId => uint256 outputClaimable)
        public claimableOutputTokens;

    PoolKey public poolKey;

    uint256 public count;

    enum Status {
        PLACED,
        EXECUTED,
        CANCELED,
        PARTIAL
    }

    struct Order {
        bytes32 id;
        OrderType orderType;
        Status orderStatus;
        address user;
        uint256 amountIn;
        int24 tick;
        bool zeroForOne;
    }

    mapping(bytes32 => Order) public ordersById;
    mapping(int24 tick => mapping(bool zeroForOne => Order[])) public orders;
    mapping(PoolId => int24) public lastLowerTick;
    mapping(address userAddress => Order[]) public ordersByUser;

    function getOrderId(address sender) internal returns (bytes32) {
        return keccak256(abi.encodePacked(count, sender, block.timestamp));
    }

    function getZeroForOne(OrderType orderType) internal returns (bool) {
        return
            (orderType == OrderType.BUYSTOP) ||
            (orderType == OrderType.STOPLOSS);
    }

    function getPositionId(
        PoolKey calldata key,
        int24 tick,
        bool zeroForOne
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(key.toId(), tick, zeroForOne)));
    }

    function placeOrder(
        OrderType orderType,
        uint256 amountIn,
        int24 triggerTick,
        PoolKey calldata _poolKey,
        int24 lowerTick
    ) external returns (bytes32 orderId) {
        require(amountIn > 0, "RangeOrders: Amount must be greater than 0");

        orderId = getOrderId(msg.sender);
        bool zeroForOne = getZeroForOne(orderType);

        ordersById[orderId] = Order({
            id: orderId,
            user: msg.sender,
            orderType: orderType,
            amountIn: amountIn,
            tick: triggerTick,
            orderStatus: Status.PLACED,
            zeroForOne: zeroForOne
        });

        int24 tick = getLowerUsableTick(lowerTick, _poolKey.tickSpacing);
        orders[tick][zeroForOne].push(ordersById[orderId]);
        ordersByUser[msg.sender].push(ordersById[orderId]);
        count++;

        address token = zeroForOne
            ? Currency.unwrap(_poolKey.currency0)
            : Currency.unwrap(_poolKey.currency1);
        IERC20(token).transferFrom(msg.sender, address(this), amountIn);
        emit OrderPlaced(orderId, msg.sender, orderType, amountIn, triggerTick);
    }

    function getOrder(bytes32 orderId) external view returns (Order memory) {
        return ordersById[orderId];
    }

    function cancelOrder(bytes32 orderId) external {
        //TODO: check logic for partial orders and refunds
        Order storage order = ordersById[orderId];
        require(order.user == msg.sender, "RangeOrders: Not Creator");
        require(
            order.orderStatus == Status.PLACED,
            "RangeOrders: Order can only be canceled if it is open"
        );

        order.orderStatus = Status.CANCELED;

        address token = order.zeroForOne
            ? Currency.unwrap(poolKey.currency0)
            : Currency.unwrap(poolKey.currency1);
        IERC20(token).transfer(order.user, order.amountIn);

        emit OrderCanceled(orderId, msg.sender, order.orderType);
    }

    function getLowerUsableTick(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 intervals = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) intervals--;
        return intervals * tickSpacing;
    }

    function checkExecuteOrder(
        Order storage order,
        int24 currentTick
    ) internal view returns (bool) {
        if (
            (order.orderType == OrderType.STOPLOSS ||
                order.orderType == OrderType.BUYLIMIT) &&
            currentTick <= order.tick
        ) {
            return true;
        } else if (
            (order.orderType == OrderType.BUYSTOP ||
                order.orderType == OrderType.TAKEPROFIT) &&
            currentTick >= order.tick
        ) {
            return true;
        }
        return false;
    }

    // TODO
    function killOrder() external {}

    //TODO
    function redeem(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmountToClaimFor
    ) external {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 positionId = getPositionId(key, tick, zeroForOne);

        // if (claimableOutputTokens[positionId] == 0) revert NothingToClaim();

        // uint256 positionTokens = balanceOf(msg.sender, positionId);
        // if (positionTokens < inputAmountToClaimFor) revert NotEnoughToClaim();

        // uint256 totalClaimableForPosition = claimableOutputTokens[positionId];
        // uint256 totalInputAmountForPosition = claimTokensSupply[positionId];

        // uint256 outputAmount = inputAmountToClaimFor.mulDivDown(
        //     totalClaimableForPosition,
        //     totalInputAmountForPosition
        // );

        // claimableOutputTokens[positionId] -= outputAmount;
        // claimTokensSupply[positionId] -= inputAmountToClaimFor;
        // _burn(msg.sender, positionId, inputAmountToClaimFor);

        // // Transfer output tokens
        // Currency token = zeroForOne ? key.currency1 : key.currency0;
        // token.transfer(msg.sender, outputAmount);
    }
}
