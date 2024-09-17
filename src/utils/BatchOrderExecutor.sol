// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import {Events} from "./Events.sol";

contract BatchOrderExecutor is Events {
    struct Action {
        address destination;
        uint256 amount;
        bytes data;
    }

    function executeFulfillment(
        address poolHook,
        bytes32 orderId,
        Action[] calldata actions
    ) external {  
        emit SettlementInitiated(poolHook, orderId);
        
        (bool executed, ) = poolHook.call(
            abi.encodeWithSelector(
                bytes4(keccak256("executeOrderAndRedeem(bytes32,bytes)")),
                orderId,
                abi.encode(actions)
            )
        );
        require(executed, "BatchOrderExecutor: Settlement initiation failed");
    }

    function execute(
        address user,
        address tokenOut,
        bytes calldata callData
    ) external {
        // Decode the actions data from the settlement contract
        Action[] memory actionsToExecute = abi.decode(callData, (Action[]));
        uint256 actionCount = actionsToExecute.length;

        for (uint256 idx = 0; idx < actionCount; idx++) {
            Action memory currentAction = actionsToExecute[idx];
            (bool success, bytes memory result) = currentAction.destination.call{ value: currentAction.amount }(
                currentAction.data
            );

            emit ActionExecuted(currentAction.destination, success, result);

            assembly {
                if eq(success, 0) {
                    mstore(0x00, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(0x04, 0x0000000000000000000000000000000000000000000000000000000000000020)
                    mstore(0x24, 0x0000000000000000000000000000000000000000000000000000000000000017) 
                    mstore(0x44, 0x42617463684578656375746f723a206d756c746963616c6c33206661696c6564)
                    revert(0x00, 0x64) 
                }
            }
        }
    }
}
