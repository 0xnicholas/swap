import { ethers } from 'ethers';

const uint256Max = ethers.MaxUint256;

const feeToSpacing = {
  3000: 60,
  500: 10
}

// forge inspect Pool bytecode| xargs cast keccak
const poolCodeHash = "0x9dc805423bd1664a6a73b31955de538c338bac1f5c61beb8f4635be5032076a2";

export { uint256Max, feeToSpacing, poolCodeHash };