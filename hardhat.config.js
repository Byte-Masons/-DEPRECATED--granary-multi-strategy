require('dotenv').config();
require('hardhat-contract-sizer');
require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');

const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const FTMSCAN_KEY = process.env.FTMSCAN_API_KEY;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.5.17',
      },
      {
        version: '0.8.18',
        settings: {
          optimizer: {
            enabled: true,
            runs: 199,
          },
        },
      },
    ],
  },
  networks: {
    mainnet: {
      url: `https://rpc.ankr.com/fantom`,
      chainId: 250,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    testnet: {
      url: `https://rpcapi-tracing.testnet.fantom.network`,
      chainId: 4002,
      accounts: [`0x${PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: FTMSCAN_KEY,
  },
  mocha: {
    timeout: 1200000,
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
  }
};
