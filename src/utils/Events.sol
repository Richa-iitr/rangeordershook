// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Events {
    enum OrderType {
        BUYSTOP,
        BUYLIMIT,
        STOPLOSS,
        TAKEPROFIT
    }

    event OrderPlaced(
        bytes32 indexed orderId,
        address indexed user,
        OrderType orderType,
        uint256 amountIn,
        int24 triggerPrice
    );
    event OrderExecuted(
        bytes32 indexed orderId,
        address indexed user,
        OrderType orderType,
        uint256 amountIn,
        int24 triggerPrice
    );
    event OrderCanceled(
        bytes32 indexed orderId,
        address indexed user,
        OrderType orderType
    );

    event OrdersQueued(bytes32[] orderIds);
    event SettlementInitiated(address indexed pool, bytes32 orderId);
    event ActionExecuted(address indexed target, bool success, bytes result);
}
