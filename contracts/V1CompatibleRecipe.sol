//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.1;
pragma experimental ABIEncoderV2;

import "./UniRecipe.sol";
import "./interfaces/IWETH.sol";

contract V1CompatibleRecipe is UniRecipe {
    using SafeERC20 for IERC20;

    constructor(
        address _weth,
        address _uniRouter,
        address _smartPoolRegistry) UniRecipe(_weth, _uniRouter, _smartPoolRegistry) {
            //nothing here
    }

    function toETF(address _smartPool, uint256 _outputAmount) external payable {
        uint256 calculatedSpend = getPrice(address(WETH), _smartPool, _outputAmount);

        // convert to WETH
        address(WETH).call{value: msg.value}("");
        
        // bake
        uint256 outputAmount = _bake(address(WETH), _smartPool, msg.value, _outputAmount);

        // transfer output
        IERC20(_smartPool).safeTransfer(_msgSender(), outputAmount);

        // if any WETH left convert it into ETH and send it back
        uint256 wethBalance = WETH.balanceOf(address(this));
        if(wethBalance != 0) {
            IWETH(address(WETH)).withdraw(wethBalance);
            payable(msg.sender).transfer(wethBalance);
        }
    }

    function toETH(address _smartPool, uint256 _inputAmount) external payable{
        ISmartPool smartPool = ISmartPool(_smartPool);
        IERC20 token = IERC20(_smartPool);
        token.transferFrom(msg.sender, address(this), _inputAmount);

        (uint communitySwapFee, uint communityJoinFee, uint communityExitFee, address communityFeeReceiver) = smartPool.getCommunityFee();

        (uint poolAmountInAfterFee, uint poolAmountInFee) = smartPool.calcAmountWithCommunityFee(
            _inputAmount, communityExitFee, msg.sender
        );

        (address[] memory tokens, uint256[] memory amounts) = smartPool.calcTokensForAmount(poolAmountInAfterFee);
        uint256[] memory minAmountsOut = new uint256[](amounts.length);
        for(uint256 i = 0; i < amounts.length; i ++) {
            minAmountsOut[i] =  bmul(amounts[i], 0.9 ether);
        }
        smartPool.exitPool(_inputAmount, minAmountsOut);
        uint256 calculatedOutSum;
        for(uint256 i = 0; i < tokens.length; i ++) {
            uint[] memory uniAmounts = swapUniOrSushi2(tokens[i], address(WETH), amounts[i]);
            calculatedOutSum+=uniAmounts[1];
        }
        IWETH(address(WETH)).withdraw(calculatedOutSum);
        payable(msg.sender).transfer(calculatedOutSum);
    }

    function calcToSmartPool(address _smartPool, uint256 _poolAmount) external view returns(uint256) {
        return getPrice(address(WETH), _smartPool, _poolAmount);
    }

    fallback () external payable {}
}