require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("@nomiclabs/hardhat-web3");
require('@openzeppelin/hardhat-upgrades');
require("@tenderly/hardhat-tenderly");
require('dotenv').config()

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  settings: {
    optimizer: {
      enabled: true,
      runs: 1000,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  sourcify: {
    enabled: false
  },
  tenderly: {
    username: "BrightDaniel",
    project: "suprime-core",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    localhost: {
      //url: ``,
      sabler: '0x7a43F8a888fa15e68C103E18b0439Eb1e98E4301',
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: [process.env.SEPOLIA_PRIVATE_KEY],
      sabler: '0x7a43F8a888fa15e68C103E18b0439Eb1e98E4301',
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: [process.env.MAINNET_PRIVATE_KEY],
      sabler: '0xB10daee1FCF62243aE27776D7a92D39dC8740f95',
    }
  },
};
