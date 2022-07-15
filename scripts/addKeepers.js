async function main() {
  const strategyAddress = '';
  const Strategy = await ethers.getContractFactory('ReaperStrategyGranary');
  const strategy = Strategy.attach(strategyAddress);

  const keeperAddress = [
    '0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4',
    '0x5241F63D0C1f2970c45234a0F5b345036117E3C2',
    '0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6',
    '0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D',
    '0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA',
    '0x51263D56ec81B5e823e34d7665A1F505C327b014',
    '0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f',
    '0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2',
    '0x34Df14D42988e4Dc622e37dc318e70429336B6c5',
    '0x73C882796Ea481fe0A2B8DE499d95e60ff971663',
    '0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0',
    '0x9a2AdcbFb972e0EC2946A342f46895702930064F',
    '0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897',
    '0x8456a746e09A18F9187E5babEe6C60211CA728D1',
    '0xd21E0fE4ba0379Ec8DF6263795c8120414Acd0A3',
    '0x3b410908e71ee04e7de2a87f8f9003afe6c1c7ce',
  ];

  const keeperRole = '0x71a9859d7dd21b24504a6f306077ffc2d510b4d4b61128e931fe937441ad1836';

  for (let i = 0; i < keeperAddress.length; i++) {
    const keeper = keeperAddress[i];
    console.log(`Granting keeper role to: ${keeper}`);
    const tx = await strategy.grantRole(keeperRole, keeper);
    await tx.wait();
    console.log('Keeper role granted!');
    await new Promise((r) => setTimeout(r, 4000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
