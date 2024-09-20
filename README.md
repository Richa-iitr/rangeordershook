# RangeOrders Hook
Uniswap provides users an opportunity to place range orders which are liquidity provision strategy where users supply a single asset within a specific price range, functioning similarly to a limit order. As the market price moves through the designated range, the liquidity gradually converts into the target asset, allowing users to trade at predefined price levels. Unlike traditional limit orders, range orders also generate trading fees while being executed, as they are part of Uniswap's liquidity pool. The uniswap doc mentions:
> One important distinction: range orders, unlike traditional limit orders, will be unfilled if the spot price crosses the given range and then reverses to recross in the opposite direction before the target asset is withdrawn. While you will be earning LP fees during this time, if the goal is to exit fully in the desired destination asset, you will need to keep an eye on the order and either manually remove your liquidity when the order has been filled or use a third party position manager service to withdraw on your behalf.

This makes range orders a little tedious for the user as it needs to be monitored and the position manually withdrawn.

## Project description
The project is a modified version of one of my previous projects where range orders were automated. So that was a project without the use of hooks by keeping a track of orders placed and running a cron job to execute the orders as and when the tick ranges match. This project is an attempt to duplicate the functionality with Uniswap v4 features and hooks. The flow goes as follows:
- The user uses the hook to place a range order of any type (Take Profit, Buy Stop, Buy Limit, Stop Loss).
- The orders are stored in a storage mappings.
- Whenever a swap happens an `afterSwap` hook fetches the orders which can be executed with the ticks shifted to new range.
- An executor executes the order which can be executed based on the afterSwap, it fulfills the order and redeems and transfers the swapped tokens to user.
![Research and design](https://github.com/user-attachments/assets/e4354d08-b4ef-47aa-a2e4-62c339270c9b)

## Extension
- Currently a batch executor is running the valid orders, as a future work would research on how this can be done via hook itself or some other mechanism.
- The current version is a basic one with inconsiderations of slippage, losses and partial orders fulfillments, these need to be taken care of to make the hook production ready.
- The hook can be extended to a LP position manager providing automated services to LPs like range orders, rebalancing, profit strategies, loss-safety, auth.
- Integration with Brevis for profit strategies can be done based on common patterns in trades (if possible an AI model can be trained to recommend strategies based on position)
- Integration with EigenLayer AVS for validation and execution of orders automatically.

## Challenges
- Understanding Uniswap v4 took time.
- It was a bit challenging to decide on a flow however previous works on Take profit, Limit Orders, Stop Loss and similar helped.
- Version mismatches led to a lot of time in debugging.
- The logic flow of certain components especially automating within the hook and so are a bit time-taking.

# v4-template
### **A template for writing Uniswap v4 Hooks 🦄**

[`Use this Template`](https://github.com/uniswapfoundation/v4-template/generate)

1. The example hook [Counter.sol](src/Counter.sol) demonstrates the `beforeSwap()` and `afterSwap()` hooks
2. The test template [Counter.t.sol](test/Counter.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity.

<details>
<summary>Updating to v4-template:latest</summary>

This template is actively maintained -- you can update the v4 dependencies, scripts, and helpers: 
```bash
git remote add template https://github.com/uniswapfoundation/v4-template
git fetch template
git merge template/main <BRANCH> --allow-unrelated-histories
```

</details>

---

## Check Forge Installation
*Ensure that you have correctly installed Foundry (Forge) and that it's up to date. You can update Foundry by running:*

```
foundryup
```

## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```

### Local Development (Anvil)

Other than writing unit tests (recommended!), you can only deploy & test hooks on [anvil](https://book.getfoundry.sh/anvil/)

```bash
# start anvil, a local EVM chain
anvil

# in a new terminal
forge script script/Anvil.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

<details>
<summary><h3>Testnets</h3></summary>

NOTE: 11/21/2023, the Goerli deployment is out of sync with the latest v4. **It is recommend to use local testing instead**

~~For testing on Goerli Testnet the Uniswap Foundation team has deployed a slimmed down version of the V4 contract (due to current contract size limits) on the network.~~

~~The relevant addresses for testing on Goerli are the ones below~~

```bash
POOL_MANAGER = 0x0
POOL_MODIFY_POSITION_TEST = 0x0
SWAP_ROUTER = 0x0
```

Update the following command with your own private key:

```
forge script script/00_Counter.s.sol \
--rpc-url https://rpc.ankr.com/eth_goerli \
--private-key [your_private_key_on_goerli_here] \
--broadcast
```

### *Deploying your own Tokens For Testing*

Because V4 is still in testing mode, most networks don't have liquidity pools live on V4 testnets. We recommend launching your own test tokens and expirementing with them that. We've included in the templace a Mock UNI and Mock USDC contract for easier testing. You can deploy the contracts and when you do you'll have 1 million mock tokens to test with for each contract. See deployment commands below

```
forge create script/mocks/mUNI.sol:MockUNI \
--rpc-url [your_rpc_url_here] \
--private-key [your_private_key_on_goerli_here]
```

```
forge create script/mocks/mUSDC.sol:MockUSDC \
--rpc-url [your_rpc_url_here] \
--private-key [your_private_key_on_goerli_here]
```

</details>

---

<details>
<summary><h2>Troubleshooting</h2></summary>



### *Permission Denied*

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

Typically caused by missing Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh) 

Or [adding the keys to your ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent), if you have already uploaded SSH keys

### Hook deployment failures

Hook deployment failures are caused by incorrect flags or incorrect salt mining

1. Verify the flags are in agreement:
    * `getHookCalls()` returns the correct flags
    * `flags` provided to `HookMiner.find(...)`
2. Verify salt mining is correct:
    * In **forge test**: the *deploye*r for: `new Hook{salt: salt}(...)` and `HookMiner.find(deployer, ...)` are the same. This will be `address(this)`. If using `vm.prank`, the deployer will be the pranking address
    * In **forge script**: the deployer must be the CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
        * If anvil does not have the CREATE2 deployer, your foundry may be out of date. You can update it with `foundryup`

</details>

---

Additional resources:

[v4-periphery](https://github.com/uniswap/v4-periphery) contains advanced hook implementations that serve as a great reference

[v4-core](https://github.com/uniswap/v4-core)

[v4-by-example](https://v4-by-example.org)

