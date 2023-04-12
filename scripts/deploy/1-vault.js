const {ethers} = require('hardhat');
const helpers = require('../utils/mainnetDeploymentHelpers.js');

async function deployVault(wantAddress, wantSymbol) {
  const Vault = await ethers.getContractFactory('ReaperVaultERC4626');

  const tokenName = `${wantSymbol} Multi-Strategy Vault`;
  const tokenSymbol = `rf-${wantSymbol}`;
  const tvlCap = ethers.constants.MaxUint256;
  const treasuryAddress = '0x0e7c5313e9bb80b654734d9b7ab1fb01468dee3b';
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

  const constructorArguments = [
    wantAddress,
    tokenName,
    tokenSymbol,
    tvlCap,
    treasuryAddress,
    strategists,
    multisigRoles,
  ];
  const vault = await Vault.deploy(...constructorArguments);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);

  await helpers.verifyContract(vault.address, constructorArguments);
}

async function main() {
  await deployVault('0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83', 'WFTM');
  await deployVault('0x04068da6c83afcfa0e13ba15a6696662335d5b75', 'USDC');
  await deployVault('0x8d11ec38a3eb5e956b052f67da8bdc9bef8abf3e', 'DAI');
  await deployVault('0x321162cd933e2be498cd2267a90534a804051b11', 'WBTC');
  await deployVault('0x74b23882a30290451a17c44f4f05243b6b58c76d', 'WETH');
  await deployVault('0x049d68029688eAbF473097a2fC38ef61633A3C7A', 'fUSDT');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
