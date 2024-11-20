/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");

module.exports = {
  solidity: 
  {
    version: "0.8.27",
    settings: {
      evmVersion: "cancun",
    },
  },
  paths: {
    sources: "./src",
    tests: "./test/hardhat",
    cache: "./cache_hardhat",
    artifacts: "./artifacts"
  },
};
