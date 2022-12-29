async function main() {
  const strategyAddress = '0xc99911Af7594964C399f605840d1107E98602aD4';
  const Strategy = await ethers.getContractFactory('ReaperStrategyGranary');
  const strategy = Strategy.attach(strategyAddress);

  const keeperAddress = [
    '0x687bD49516Dc9a066e9c43f3AF8bB439317D31c0'
  ];

  const keeperRole = '0x71a9859d7dd21b24504a6f306077ffc2d510b4d4b61128e931fe937441ad1836';

  for (let i = 0; i < keeperAddress.length; i++) {
    const keeper = keeperAddress[i];
    console.log(`Granting keeper role to: ${keeper}`);
    const tx = await strategy.grantRole(keeperRole, keeper);
    await tx.wait();
    console.log('Keeper role granted!');
    await new Promise((r) => setTimeout(r, 10000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
