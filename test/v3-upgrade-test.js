// REPLACE CONTENTS OF unknown-31337.json WITH CONTENTS OF unknown-10.json TO RUN THIS
// also add this block to the end of the `proxies` array (for the DAI strat, add others similarly)
// {
//   "address": "0xE3E972A4f59f221ab0639d2EB8DBf34897B8E7f8",
//   "txHash": "0x48ec8fb98ea2804d92cf91d54339ef296d4355d2fa2a07d6a2c4973106db492c",
//   "kind": "uups"
// }
const {ethers, network, upgrades} = require('hardhat');

describe.only('V3 Upgrade', function () {
  it('executes V3 upgrade successfully', async function () {
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

    const strategyAddress = '0xE3E972A4f59f221ab0639d2EB8DBf34897B8E7f8';
    const StrategyV3 = await ethers.getContractFactory('ReaperStrategyGranary');
    const strategyProxy = StrategyV3.attach(strategyAddress);
    const newImplAddress = await upgrades.prepareUpgrade(strategyAddress, StrategyV3);

    const superAdminAddress = '0x04C710a1E8a738CDf7cAD3a52Ba77A784C35d8CE';
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [superAdminAddress],
    });
    const superAdmin = ethers.provider.getSigner(superAdminAddress);

    const [signer] = await ethers.getSigners();
    let tx = await signer.sendTransaction({
      to: superAdminAddress,
      value: ethers.utils.parseEther('7'),
    });
    await tx.wait();

    await network.provider.send('evm_increaseTime', [3600 * 49]);
    await network.provider.send('evm_mine');
    await strategyProxy.connect(superAdmin).upgradeTo(newImplAddress);

    // try harvesting with keeper, should pass
    const keeperAddress = '0x3b410908e71Ee04e7dE2a87f8F9003AFe6c1c7cE';
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [keeperAddress],
    });
    const keeper = ethers.provider.getSigner(keeperAddress);

    tx = await signer.sendTransaction({
      to: keeperAddress,
      value: ethers.utils.parseEther('3'),
    });
    await tx.wait();
    tx = await strategyProxy.connect(keeper).harvest();
    await tx.wait();
  });
});
