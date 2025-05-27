// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

interface IFlashLoanEtherReceiver {
    function execute() external payable;
} 