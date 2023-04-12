const {ethers, upgrades} = require('hardhat');

async function deployStrat(vaultAddress, gWantAddress, targetLtv, maxLtv) {
  const Strategy = await ethers.getContractFactory('ReaperStrategyGranary');
  const strategists = [
    '0x1E71AEE6081f62053123140aacC7a06021D77348',
    '0x81876677843D00a7D792E1617459aC2E93202576',
    '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4',
    '0x60BC5E0440C867eEb4CbcE84bB1123fad2b262B1',
  ];
  const multisigRoles = [
    '0x04C710a1E8a738CDf7cAD3a52Ba77A784C35d8CE', // super admin
    '0x539eF36C804e4D735d8cAb69e8e441c12d4B88E0', // admin
    '0xf20E25f2AB644C8ecBFc992a6829478a85A98F2c', // guardian
  ];
  const keepers = [
    '0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA',
    '0x34Df14D42988e4Dc622e37dc318e70429336B6c5',
    '0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0',
    '0x3b410908e71Ee04e7dE2a87f8F9003AFe6c1c7cE',
    '0x51263D56ec81B5e823e34d7665A1F505C327b014',
    '0x5241F63D0C1f2970c45234a0F5b345036117E3C2',
    '0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D',
    '0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4',
    '0x73C882796Ea481fe0A2B8DE499d95e60ff971663',
    '0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897',
    '0x8456a746e09A18F9187E5babEe6C60211CA728D1',
    '0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f',
    '0x9a2AdcbFb972e0EC2946A342f46895702930064F',
    '0xd21e0fe4ba0379ec8df6263795c8120414acd0a3',
    '0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2',
    '0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6',
    '0xCcb4f4B05739b6C62D9663a5fA7f1E2693048019',
  ];

  const strategy = await upgrades.deployProxy(
    Strategy,
    [vaultAddress, strategists, multisigRoles, keepers, gWantAddress, targetLtv, maxLtv],
    {
      kind: 'uups',
      timeout: 0,
    },
  );
  await strategy.deployed();
  console.log('Strategy deployed to:', strategy.address);
}

async function main() {
  await deployStrat('0x963ffcd14D471E279245eE1570ad64ca78d8e67E', '0x98d5105370191D641f32589B35cDa9eCd367C74F', 6160, 6260); // WFTM
  await deployStrat('0xd55C59Da5872DE866e39b1e3Af2065330ea8Acd6', '0x0638546741f12fA55F840A763A5aEF9671C74Fc1', 7700, 7800); // USDC
  await deployStrat('0x16E4399FA9ba6e58F12BF2d2bC35f8BdE8a9a4aB', '0x8e4bFB85962A63caCfa2C0fde5eaD86D9b120B16', 7700, 7800); // DAI
  await deployStrat('0xfA985463B7FA975d06cde703EC72eFCcF293c605', '0xf3Cb6762F5C159a1494b01c50a131d7f2b24fb14', 7700, 7800); // WBTC
  await deployStrat('0xC052627bc73117d2CB3569f133419550156bdFa1', '0xA44E588Ec78066D27F768f4901A2577F821938a1', 7700, 7800); // WETH
  await deployStrat('0xAea55C0E84aF6e5eF8C9B7042fB6aB682516214A', '0x6cBE07B362f2be4217a5ce247F07C422B0Bd88f3', 7700, 7800); // fUSDT
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
