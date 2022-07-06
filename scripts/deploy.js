const hre = require('hardhat');

const Treasury = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
const StrategistRemitter = '0x63cbd4134c2253041F370472c130e92daE4Ff174';
const FeeRemitters = [Treasury, StrategistRemitter];

const Tess = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
const Bongo = '0x1E71AEE6081f62053123140aacC7a06021D77348';
const Degenicus = '0x81876677843D00a7D792E1617459aC2E93202576';
const Strategists = [Tess, Bongo, Degenicus];

const gFTM = '0x39B3bd37208CBaDE74D0fcBDBb12D606295b430a';
const WFTM = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);

  console.log('Account balance:', (await deployer.getBalance()).toString());

  // For some reason doing multiple transactions in here can fail
  // Hence comment/uncomment as necessary to ensure vault/strat aren't deployed twice
  const vaultFactory = await ethers.getContractFactory('ReaperVaultNativev1_3');
  const vaultcontract = await vaultFactory.attach('0xD7c36a64be0D9a57cfB92b4a19B1Ed5230b415b6');
  // const vaultcontract = await vaultFactory.deploy(
  //   WFTM,
  //   'FTM Geist Crypt',
  //   'rfFTM-Geist',
  //   ethers.BigNumber.from('0'), // depositFee 0
  //   ethers.utils.parseEther('60000'), // tvlCap 60k tokens
  // );

  // console.log('Vault Contract address:', vaultcontract.address);

  // const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundFlashBorrow');
  // const stratContract = await hre.upgrades.deployProxy(
  //   stratFactory,
  //   [vaultcontract.address, FeeRemitters, Strategists, gFTM, ethers.BigNumber.from('4800')],
  //   {kind: 'uups'},
  // );

  // console.log('Strategy Contract address:', stratContract.address);

  await vaultcontract.initialize('0x43132cA3c2b1e7B4247204d0d12F376b64f2F5a8');

  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
