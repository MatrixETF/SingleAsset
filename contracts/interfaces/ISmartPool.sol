//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISmartPool is IERC20 {
//    function joinPool(uint256 _amount) external;
//    function exitPool(uint256 _amount) external;
//    function calcTokensForAmount(uint256 _amount) external view  returns(address[] memory tokens, uint256[] memory amounts);
//    function getTokens() external view returns (address[] memory);

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external;

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;

    function calcTokensForAmount(uint256 _amount) external view returns (address[] memory tokens, uint256[] memory amounts);

    function getCommunityFee()
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        address
    );

    function calcAmountWithCommunityFee(
        uint256,
        uint256,
        address
    ) external view returns (uint256, uint256);
}