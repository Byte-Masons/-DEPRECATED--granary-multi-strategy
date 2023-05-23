const {ethers, upgrades} = require('hardhat');

async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyGranary');
  const newImpl = await upgrades.prepareUpgrade('0xc99911Af7594964C399f605840d1107E98602aD4', stratFactory, {
    timeout: 0,
    kind: 'uups',
  });
  console.log(`New impl address: ${newImpl}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
