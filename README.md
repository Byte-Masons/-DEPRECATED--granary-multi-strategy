# High-level blueprint

## As a user:
- deposit USDC anytime
- withdraw the USDC that I've deposited (partially or wholly) anytime
- expect my USDC investment to grow

## Main functions of strategy

### deposit(x):
1. flash loan for `[(x)(ltv)] / [10000 - ltv]`, `ltv` is target loan-to-value ratio
2. deposit everything we have into `lendingPool` during the `executeTransaction()` callback
    - this should be just the right amount to cover the full required collateral

### withdraw(x):
1. pay up from contract's balance if present
2. otherwise
	1. flash loan for `10000x/(10000 + y)`, where `y` is flash loan premium
	2. contract now has spendable `allowance` of `10000x/(10000 + y)`
	3. keep repaying and withdrawing using `allowance` while ensuring `targetLtv` is never exceeded (loop)
	4. loop ends when `allowance` is enough to pay up user + flash loan

Here's some code in Kotlin
```kotlin
fun main() {
    freeUp(1414.0) // user won't actually get full amount cuz of flash loan fee
}

fun freeUp(amount: Double) {
    val targetLtv = 0.78
    var deposit = 52347.0
    var borrowed = 40802.0
    assert(borrowed / deposit <= targetLtv)

    val realAssets = deposit - borrowed
    assert(amount <= realAssets)

    // user is responsible for flash loan fee
    val flAmount = amount * 10000 / 10009
    println("took out flash loan for ${flAmount}")

    val owedToVault = flAmount
    val owedToLender = loanBalance(flAmount)
    val netOwing = owedToVault + owedToLender

    var allowance = flAmount
    var counter = 0
    while (allowance < netOwing && counter <= 10) {
        counter++

        val repayment = Math.min(borrowed, allowance)
        borrowed -= repayment // reduce borrowed
        allowance -= repayment
        assert(borrowed / deposit <= targetLtv)

        val withdrawal = Math.min(deposit, repayment / targetLtv)
        deposit -= withdrawal // reduce deposit
        allowance += withdrawal
        assert(borrowed / deposit <= targetLtv)

        println("new deposit ${deposit}, new borrowed ${borrowed}, new allowance ${allowance}")
    }

    println("replaying flash loan with ${loanBalance(flAmount)}")
    allowance -= loanBalance(flAmount)

    println("paying up user with what's left, that is ${allowance}")
}

fun loanBalance(principal: Double) = (1.0009 * principal)
```

### harvest():
1. vest any unvested Geist (using `ChefIncentivesController#claim()` function)
    1. can call `poolLength()` to get length of `registeredTokens` array and keep a copy in storage
	2. each time when we call `harvest()`, we can compare the lengths and if more tokens have been added copy them over as well
	3. vest everything by calling `claim(address _user, address[] registeredTokens)`
2. claim rewards and lock any fully vested geist (using `MultiFeeDistribution` contract)
	1. can check earned balances to see what amount has matured, if any
	2. can withdraw that amount and lock it
	3. rest is similar to what we do in geist-staking-crypt
3. convert all remaining reward tokens to wftm, charge fees
4. convert remaining wftm to USDC and redeposit

## Fees

- User is responsible for paying flash loan fees during withdrawal, which is 0.09%. This would change if Geist's flash loan fee changes.
- While Geist tokens are vesting, they are still earning platform fee rewards like with staking. As part of `harvest()`, we will withdraw and lock any fully vested Geist to earn the boosted APR that comes with locking Geist. End users, however, have no claim to these Geist tokens. This is for several reasons:
    - Users should only have exposure to USDC
    - Rewards from vesting/locking Geist tokens will always be converted to USDC
    - Geist tokens will be quite difficult to account for on a per-user basis with the vesting and locking schedules. Moreover we need them to stay locked so that the crypt can pay high APY **in USDC**.
    - We are confident that we will offer a very compelling APY even with this caveat, and that this APY will only increase once the crypt has been active for 90 days as after that point we can start locking up some Geist to earn more rewards.
- Due to the above, we have decided to not charge any **additional** conventional performance fee (besides call fee and treasury fee) in `harvest()`. Any Geist tokens that are left in the strategy are to be considered additional performance fee. We can decide how we wish to claim them. We could either:
    - Leave them locked up for as long as the crypt is active and withdraw them all at the end.
    - Periodically withdraw any *expired* locks (Geist tokens that have remained locked for 90+ days). This will however impact the rewards as the total locked Geist tokens would decrease. But if we only withdraw a small % (like 5% of the expired locks every week after 6 months, 6 months being the first opportunity as any Geist tokens have to endure 3 months of vesting followed by 3 months of locking before they can be withdrawn without any sort of penalty), then the impact would be minimal, and we can limit our own exposure to Geist.
    - **[CURRENT METHOD]** Periodically withdraw any *fully vested* tokens (Geist tokens that have finished vesting for 90 days). This will however impact the rewards as the total vested Geist tokens that we would be able to lock would decrease. But if we only withdraw a small % (like 5% of the vested tokens every week after 3 months, 3 months being the first opportunity as any Geist tokens have to endure 3 months of vesting before they can be withdrawn without any sort of penalty), then the impact would be minimal, and we can limit our own exposure to Geist.
    - Some other combination thereof.

# Advanced Sample Hardhat Project

This project demonstrates an advanced Hardhat use case, integrating other tools commonly used alongside Hardhat in the ecosystem.

The project comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts. It also comes with a variety of other tools, preconfigured to work with the project code.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
REPORT_GAS=true npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.js
node scripts/deploy.js
npx eslint '**/*.js'
npx eslint '**/*.js' --fix
npx prettier '**/*.{json,sol,md}' --check
npx prettier '**/*.{json,sol,md}' --write
npx solhint 'contracts/**/*.sol'
npx solhint 'contracts/**/*.sol' --fix
```

# Etherscan verification

To try out Etherscan verification, you first need to deploy a contract to an Ethereum network that's supported by Etherscan, such as Ropsten.

In this project, copy the .env.example file to a file named .env, and then edit it to fill in the details. Enter your Etherscan API key, your Ropsten node URL (eg from Alchemy), and the private key of the account which will send the deployment transaction. With a valid .env file in place, first deploy your contract:

```shell
hardhat run --network ropsten scripts/deploy.js
```

Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:

```shell
npx hardhat verify --network ropsten DEPLOYED_CONTRACT_ADDRESS "Hello, Hardhat!"
```
