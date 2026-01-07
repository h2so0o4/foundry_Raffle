// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    event EnteredRaffle(address indexed player);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link
        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleInitializesInOpenState() public {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testCanEnterRaffle() public {
        //准备
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        vm.startPrank(PLAYER);

        //执行

        raffle.enterRaffle{value: entranceFee}(); //成功参与抽奖
        vm.stopPrank();

        //验证
        assert(raffle.getPlayer(0) == PLAYER); //参与成功

        vm.expectRevert(Raffle.Raffle_NotEnoughEthSent.selector); //金额不足参与失败
        raffle.enterRaffle();

        assert(raffle.getPlayer(0) == PLAYER); //验证地址
        vm.expectRevert();
        raffle.getPlayer(1);
    }

    function testRaffleEmitsEnterRaffleEvent() public {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);

        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle_RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ///////
    //checkUpkeep//
    ///////

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        //正在计算中不能抽奖
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep(""); //计算
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded == false);
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        //时间未到不能抽奖
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        //时间到了 有参与人数 有余额 可以抽奖
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded == true);
    }

    /////////
    //performUpkeep//
    /////////
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsWhenCheckUpkeepIsFalse() public {
        //准备
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        //执行 验证
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    //测试事件event
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        assert(uint256(requestId) > 0);
        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(rState) == 1);
    }

    //////////
    //fulfillRandomWords//
    //////////
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 requestId //模糊测试
    ) public raffleEnteredAndTimePassed {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            requestId,
            address(raffle)
        );

        // vm.recordLogs();
        // raffle.performUpkeep("");
        // Vm.Log[] memory logs = vm.getRecordedLogs();
        // bytes32 requestId = logs[1].topics[1];
        // vrfCoordinator.fulfillRandomWords(uint256(requestId), address(raffle));

        // assert(raffle.getPlayerCount() == 0);
        // assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        // assert(raffle.getLastTimeStamp() > block.timestamp);
    }

    //大型测试函数
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
    {
        //准备
        uint256 additionalEntrants = 5; //添加5个参与
        uint256 startingIndex = 1; //从第2个开始
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}(); //参与抽奖
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];
        uint256 previousRaffleBalance = address(raffle).balance;
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //验证
        // assert(uint256(raffle.getRaffleState()) == 0);
        // assert(raffle.getPlayerCount() == 0);
        // assert(raffle.getLastTimeStamp() > startingTimeStamp);
        uint256 winnerEndingBalance = raffle.getRecentWinner().balance;
        console.log(unicode"中奖者地址:", raffle.getRecentWinner());
        console.log(unicode"初始合约余额: %s", previousRaffleBalance); //60000000000000000
        console.log(unicode"中奖者余额: %s", winnerEndingBalance); //10050000000000000000
        console.log(unicode"当前合约余额: %s", address(raffle).balance); //0

        //中奖者余额 = 初始合约余额 - 参与金额 + 参与人数 * 参与金额
        assert(
            winnerEndingBalance ==
                STARTING_USER_BALANCE -
                    entranceFee +
                    entranceFee *
                    (additionalEntrants + 1)
        );
    }
}
