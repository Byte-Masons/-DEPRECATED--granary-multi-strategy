const hre = require('hardhat');

async function main() {
  const vaultAddress = '0xa9A9dB466685F977F9ECEe347958bcef90498177';

  const Strategy = await ethers.getContractFactory('ReaperStrategyGranary');
  const treasuryAddress = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
  const paymentSplitterAddress = '0x63cbd4134c2253041F370472c130e92daE4Ff174';
  const strategist1 = '0x1E71AEE6081f62053123140aacC7a06021D77348';
  const strategist2 = '0x81876677843D00a7D792E1617459aC2E93202576';
  const strategist3 = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
  const superAdmin = '0x04C710a1E8a738CDf7cAD3a52Ba77A784C35d8CE';
  const admin = '0x539eF36C804e4D735d8cAb69e8e441c12d4B88E0';
  const guardian = '0xf20E25f2AB644C8ecBFc992a6829478a85A98F2c';
  const gWant = '0x6cBE07B362f2be4217a5ce247F07C422B0Bd88f3';
  const targetLtv = 0;

  const strategy = await hre.upgrades.deployProxy(
    Strategy,
    [
      vaultAddress,
      [treasuryAddress, paymentSplitterAddress],
      [strategist1, strategist2, strategist3],
      [superAdmin, admin, guardian],
      gWant,
      targetLtv,
      targetLtv,
    ],
    {kind: 'uups', timeout: 0},
  );

  await strategy.deployed();
  console.log('Strategy deployed to:', strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
