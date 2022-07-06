const hre = require('hardhat');
const chai = require('chai');
const {solidity} = require('ethereum-waffle');
chai.use(solidity);
const {expect} = chai;

const moveTimeForward = async (seconds) => {
  await network.provider.send('evm_increaseTime', [seconds]);
  await network.provider.send('evm_mine');
};

describe('Vaults', function () {
  const wrappedNative = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';
  const wftmHolder = '0xBC58781993B3E78A1B0608F899320825189D3631';
  const strategistRemitterAddress = '0x63cbd4134c2253041F370472c130e92daE4Ff174';
  const strategistAddress = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';

  const gFTM = '0x39b3bd37208cbade74d0fcbdbb12d606295b430a';
  const targetLtv = 4800;

  let Vault;
  let Strategy;
  let Treasury;
  let WrappedFtm;

  let vault;
  let strategy;
  let treasury;
  let wrappedFtm;

  let owner;
  let strategist;
  let holder;

  beforeEach(async function () {
    // reset network
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: 'https://late-wild-fire.fantom.quiknode.pro/',
          },
        },
      ],
    });

    // get signers
    [owner] = await ethers.getSigners();
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [strategistAddress],
    });
    strategist = await ethers.provider.getSigner(strategistAddress);
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [wftmHolder],
    });
    holder = await ethers.provider.getSigner(wftmHolder);

    // get artifacts
    Strategy = await ethers.getContractFactory('ReaperAutoCompoundFlashBorrow');
    Vault = await ethers.getContractFactory('ReaperVaultv1_4');
    Treasury = await ethers.getContractFactory('ReaperTreasury');
    WrappedFtm = await ethers.getContractFactory('WrappedFtm');

    // deploy contracts
    wrappedFtm = await WrappedFtm.attach(wrappedNative);
    treasury = await Treasury.deploy();
    vault = await Vault.deploy(wrappedNative, 'FTM GEIST Crypt', 'rfFTM-Geist', 0, ethers.constants.MaxUint256);
    strategy = await hre.upgrades.deployProxy(
      Strategy,
      [vault.address, [treasury.address, strategistRemitterAddress], [strategistAddress], gFTM, targetLtv, targetLtv + 100],
      {kind: 'uups'},
    );
    await strategy.deployed();
    await vault.initialize(strategy.address);
    await wrappedFtm.connect(holder).approve(vault.address, ethers.constants.MaxUint256);
  });

  describe('Deploying the vault and strategy', function () {
    it('should initiate vault with a 0 balance', async function () {
      const totalBalance = await vault.balance();
      const availableBalance = await vault.available();
      const pricePerFullShare = await vault.getPricePerFullShare();

      expect(totalBalance).to.equal(ethers.constants.Zero);
      expect(availableBalance).to.equal(ethers.constants.Zero);
      expect(pricePerFullShare).to.equal(ethers.utils.parseEther('1'));
    });

    it('should not allow implementation upgrades without initiating cooldown', async function () {
      const StrategyV2 = await ethers.getContractFactory('TestReaperAutoCompoundFlashBorrowV2');
      await expect(hre.upgrades.upgradeProxy(strategy.address, StrategyV2)).to.be.revertedWith(
        'cooldown not initiated or still active',
      );
    });

    it('should not allow implementation upgrades before timelock has passed', async function () {
      await strategy.initiateUpgradeCooldown();

      const StrategyV2 = await ethers.getContractFactory('TestReaperAutoCompoundFlashBorrowV2');
      await expect(hre.upgrades.upgradeProxy(strategy.address, StrategyV2)).to.be.revertedWith(
        'cooldown not initiated or still active',
      );
    });

    it('should allow implementation upgrades once timelock has passed', async function () {
      const StrategyV2 = await ethers.getContractFactory('TestReaperAutoCompoundFlashBorrowV2');
      const timeToSkip = (await strategy.UPGRADE_TIMELOCK()).add(10);
      await strategy.initiateUpgradeCooldown();
      await moveTimeForward(timeToSkip.toNumber());
      await hre.upgrades.upgradeProxy(strategy.address, StrategyV2);
    });

    it('successive upgrades need to initiate timelock again', async function () {
      const StrategyV2 = await ethers.getContractFactory('TestReaperAutoCompoundFlashBorrowV2');
      const timeToSkip = (await strategy.UPGRADE_TIMELOCK()).add(10);
      await strategy.initiateUpgradeCooldown();
      await moveTimeForward(timeToSkip.toNumber());
      await hre.upgrades.upgradeProxy(strategy.address, StrategyV2);

      const StrategyV3 = await ethers.getContractFactory('TestReaperAutoCompoundFlashBorrowV3');
      await expect(hre.upgrades.upgradeProxy(strategy.address, StrategyV3)).to.be.revertedWith(
        'cooldown not initiated or still active',
      );

      await strategy.initiateUpgradeCooldown();
      await expect(hre.upgrades.upgradeProxy(strategy.address, StrategyV3)).to.be.revertedWith(
        'cooldown not initiated or still active',
      );

      await moveTimeForward(timeToSkip.toNumber());
      await hre.upgrades.upgradeProxy(strategy.address, StrategyV3);
    });
  });

  describe('Vault Tests', function () {
    it('should allow wrapped deposits and account for them correctly', async function () {
      const userBalance = await wrappedFtm.balanceOf(wftmHolder);
      const initialVaultBalance = await vault.balance();
      const depositAmount = userBalance.div(2);

      const tx = await vault.connect(holder).deposit(depositAmount);
      const receipt = await tx.wait();

      const newVaultBalance = await vault.balance();
      const newUserBalance = await wrappedFtm.balanceOf(wftmHolder);
      const deductedAmount = userBalance.sub(newUserBalance);

      expect(initialVaultBalance).to.equal(ethers.constants.Zero);
      expect(newVaultBalance).to.equal(depositAmount);
      expect(deductedAmount).to.equal(depositAmount);
    });

    it('should allow wrapped withdrawals', async function () {
      const userBalance = await wrappedFtm.balanceOf(wftmHolder);
      const depositAmount = userBalance.div(2);

      const depositTx = await vault.connect(holder).deposit(depositAmount);
      const depositReceipt = await depositTx.wait();
      const depositGasCost = depositReceipt.gasUsed.mul(depositReceipt.effectiveGasPrice);

      const withdrawAmount = depositAmount.div(2);
      const withdrawTx = await vault.connect(holder).withdrawWithMode(withdrawAmount, true);
      const withdrawReceipt = await withdrawTx.wait();
      const withdrawGasCost = withdrawReceipt.gasUsed.mul(withdrawReceipt.effectiveGasPrice);

      const totalGasCost = depositGasCost.add(withdrawGasCost);

      const actualUserBalanceAfterWithdraw = await wrappedFtm.balanceOf(wftmHolder);
      const expectedUserBalanceAfterWithdraw = userBalance.sub(depositAmount).add(withdrawAmount);

      expect(actualUserBalanceAfterWithdraw).to.be.gte(expectedUserBalanceAfterWithdraw.mul(9950).div(10000));
      console.log(
        `Withdraw fees paid is ${userBalance
          .sub(depositAmount)
          .add(withdrawAmount)
          .sub(actualUserBalanceAfterWithdraw)
          .mul(10000)
          .div(withdrawAmount)} basis points.`,
      );
    });

    it('should provide yield', async function () {
      const timeToSkip = 3600;
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);
      const depositAmount = initialUserBalance.div(5);

      await vault.connect(holder).deposit(depositAmount);
      const initialVaultBalance = await vault.balance();

      console.log(initialVaultBalance.toString());
      await strategy.authorizedDelever(ethers.constants.MaxUint256);
      await strategy.setLeverageParams(0, 1, 10, 50);
      console.log((await vault.balance()).toString());
      await strategy.deposit();

      await strategy.connect(strategist).updateHarvestLogCadence(timeToSkip / 2);

      const numHarvests = 5;
      for (let i = 0; i < numHarvests; i++) {
        await moveTimeForward(timeToSkip);
        await strategy.harvest();
      }

      // const finalVaultBalance = await vault.balance();
      // expect(finalVaultBalance).to.be.gt(initialVaultBalance);

      const averageAPR = await strategy.averageAPRAcrossLastNHarvests(numHarvests);
      console.log(`Average APR across ${numHarvests} harvests is ${averageAPR} basis points.`);
    });

    it('should trigger deleveraging on deposit when LTV is too high', async function () {
      let supply, borrow;
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);
      const depositAmount = initialUserBalance.div(5);
      await vault.connect(holder).deposit(depositAmount);
      [supply, borrow] = await strategy.getSupplyAndBorrow();
      console.log(supply.toString());
      console.log(borrow.toString());
      console.log((await vault.balance()).toString());
      await strategy.setLeverageParams(2500, 2600, 10, 50);
      // const smallDepositAmount = initialUserBalance.div(50);
      // await vault.connect(holder).deposit(smallDepositAmount);
      await strategy.deposit();
      [supply, borrow] = await strategy.getSupplyAndBorrow();
      console.log(supply.toString());
      console.log(borrow.toString());
      console.log((await vault.balance()).toString());
    });

    it('should trigger leveraging on withdraw when LTV is too low', async function () {
      let supply, borrow;
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);

      await strategy.setLeverageParams(2500, 2600, 10, 50);
      const depositAmount = initialUserBalance.div(5);
      await vault.connect(holder).deposit(depositAmount);

      [supply, borrow] = await strategy.getSupplyAndBorrow();
      console.log(supply.toString());
      console.log(borrow.toString());
      console.log((await vault.balance()).toString());

      await strategy.setLeverageParams(4800, 4900, 10, 50);
      const withdrawAmount = initialUserBalance.div(50);
      await vault.connect(holder).withdraw(withdrawAmount);

      [supply, borrow] = await strategy.getSupplyAndBorrow();
      console.log(supply.toString());
      console.log(borrow.toString());
      console.log((await vault.balance()).toString());
    });

    it('should trigger deleveraging on withdraw when LTV is too high', async function () {
      let supply, borrow;
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);

      await strategy.setLeverageParams(4800, 4900, 10, 50);
      const depositAmount = initialUserBalance.div(5);
      await vault.connect(holder).deposit(depositAmount);

      [supply, borrow] = await strategy.getSupplyAndBorrow();
      console.log(supply.toString());
      console.log(borrow.toString());
      console.log((await vault.balance()).toString());

      await strategy.setLeverageParams(2500, 2600, 10, 50);
      const withdrawAmount = initialUserBalance.div(50);
      await vault.connect(holder).withdraw(withdrawAmount);

      [supply, borrow] = await strategy.getSupplyAndBorrow();
      console.log(supply.toString());
      console.log(borrow.toString());
      console.log((await vault.balance()).toString());
    });

    it('should be able to pause and unpause', async function () {
      await strategy.pause();
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);
      const depositAmount = initialUserBalance.div(50);
      await expect(vault.connect(holder).deposit(depositAmount)).to.be.reverted;
      await strategy.unpause();
      await expect(vault.connect(holder).deposit(depositAmount)).to.not.be.reverted;
    });

    it('should be able to panic', async function () {
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);
      const depositAmount = initialUserBalance.div(50);
      await vault.connect(holder).deposit(depositAmount);

      const vaultBalance = await vault.balance();
      console.log(vaultBalance.toString());
      await strategy.panic();
      const strategyBalance = await wrappedFtm.balanceOf(strategy.address);
      console.log(strategyBalance.toString());
    });

    it('should be able to retire strategy', async function () {
      const initialUserBalance = await wrappedFtm.balanceOf(wftmHolder);
      const depositAmount = initialUserBalance.div(50);
      await vault.connect(holder).deposit(depositAmount);

      const vaultBalance = await vault.balance();
      console.log(vaultBalance.toString());
      strategy.retireStrat();
      const strategyBalance = await wrappedFtm.balanceOf(strategy.address);
      console.log(strategyBalance.toString());
      console.log(await wrappedFtm.balanceOf(vault.address));
    });
  });
});
