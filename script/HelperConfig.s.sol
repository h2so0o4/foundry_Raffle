// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract HelperConfig is Script {
    uint96 private constant BASE_FEE = 0.1 ether;
    uint96 private constant GAS_PRICE_LINK = 1e9;
    int256 private constant WEI_PER_UNIT_LINK = 1e18;

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30,
                vrfCoordinator: 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61,
                gasLane: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
                subscriptionId: 98466040875174291769540812110908567626620455947820310827951789600597203509297,
                callbackGasLimit: 500000,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        VRFCoordinatorV2_5Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2_5Mock(
                BASE_FEE,
                GAS_PRICE_LINK,
                WEI_PER_UNIT_LINK
            );

        vm.stopBroadcast();

        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30,
                vrfCoordinator: address(vrfCoordinatorV2Mock),
                gasLane: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
                subscriptionId: 0, //如果是0，通过脚本生成链上subid
                callbackGasLimit: 500000,
                link: address(0)
            });
    }
}
