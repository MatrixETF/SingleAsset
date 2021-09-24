//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.1;
pragma experimental ABIEncoderV2;

import "./interfaces/IRecipe.sol";
import "./interfaces/IUniRouter.sol";
import "./interfaces/ISmartPoolRegistry.sol";
import "./interfaces/ISmartPool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract UniRecipe is IRecipe, Ownable {

    uint public constant BONE = 10**18;

    using SafeERC20 for IERC20;

    IERC20 immutable WETH;
    IUniRouter immutable uniRouter;
    ISmartPoolRegistry immutable smartPoolRegistry;

    event HopUpdated(address indexed _token, address indexed _hop);

    // Adds a custom hop before reaching the destination token
    mapping(address => CustomHop) public customHops;

    struct CustomHop {
        address hop;
        // DexChoice dex;
    }

    enum DexChoice {Uni, Sushi}

    constructor(
        address _weth,
        address _uniRouter,
        address _smartPoolRegistry
    ) {
        require(_weth != address(0), "WETH_ZERO");
        require(_uniRouter != address(0), "UNI_ROUTER_ZERO");
        require(_smartPoolRegistry != address(0), "SMART_POOL_REGISTRY_ZERO");

        WETH = IERC20(_weth);
        uniRouter = IUniRouter(_uniRouter);
        smartPoolRegistry = ISmartPoolRegistry(_smartPoolRegistry);
    }

    function bake(
        address _inputToken,
        address _outputToken,
        uint256 _maxInput,
        bytes memory _data
    ) external override returns(uint256 inputAmountUsed, uint256 outputAmount) {
        IERC20 inputToken = IERC20(_inputToken);
        IERC20 outputToken = IERC20(_outputToken);

        inputToken.safeTransferFrom(_msgSender(), address(this), _maxInput);

        (uint256 mintAmount) = abi.decode(_data, (uint256));

        outputAmount = _bake(_inputToken, _outputToken, _maxInput, mintAmount);

        uint256 remainingInputBalance = inputToken.balanceOf(address(this));
        if(remainingInputBalance > 0) {
            inputToken.transfer(_msgSender(), remainingInputBalance);
        }

        outputToken.safeTransfer(_msgSender(), outputAmount);

        return(inputAmountUsed, outputAmount);
    }

    function _bake(address _inputToken, address _outputToken, uint256 _maxInput, uint256 _mintAmount) internal returns(uint256 outputAmount) {
        swap(_inputToken, _outputToken, _mintAmount);

        outputAmount = IERC20(_outputToken).balanceOf(address(this));

        return(outputAmount);
    }

    function swap(address _inputToken, address _outputToken, uint256 _outputAmount) internal {
        // console.log("Buying", _outputToken, "with", _inputToken);

        if(_inputToken == _outputToken) {
            return;
        }

        // if input is not WETH buy WETH
        if(_inputToken != address(WETH)) {
            uint256 wethAmount = getPrice(address(WETH), _outputToken, _outputAmount);
            swapUniOrSushi(_inputToken, address(WETH), wethAmount);
            swap(address(WETH), _outputToken, _outputAmount);
            return;
        }

        if(smartPoolRegistry.inRegistry(_outputToken)) {
            swapSmartPool(_outputToken, _outputAmount);
            return;
        }

        // else normal swap
        swapUniOrSushi(_inputToken, _outputToken, _outputAmount);
    }

    function swapSmartPool(address _smartPool, uint256 _outputAmount) internal {
        ISmartPool smartPool = ISmartPool(_smartPool);
        (address[] memory tokens, uint256[] memory amounts) = smartPool.calcTokensForAmount(_outputAmount);

        for(uint256 i = 0; i < tokens.length; i ++) {
            swap(address(WETH), tokens[i], amounts[i]);
            IERC20 token = IERC20(tokens[i]);
            token.approve(_smartPool, 0);
            token.approve(_smartPool, amounts[i]);
        }
        uint256[] memory maxAmountsIn = new uint256[](amounts.length);
        for(uint256 i = 0; i < amounts.length; i ++) {
            maxAmountsIn[i] = bmul(amounts[i], 1.1 ether);
        }
        smartPool.joinPool(_outputAmount, maxAmountsIn);
    }

    function swapUniOrSushi(address _inputToken, address _outputToken, uint256 _outputAmount) internal {
        (uint256 inputAmount, DexChoice dex) = getBestPriceSushiUni(_inputToken, _outputToken, _outputAmount);

        address[] memory route = getRoute(_inputToken, _outputToken);

        IERC20 _inputToken = IERC20(_inputToken);

        CustomHop memory customHop = customHops[_outputToken];

        if(address(_inputToken) == _outputToken) {
            return;
        }

        _inputToken.approve(address(uniRouter), 0);
        _inputToken.approve(address(uniRouter), type(uint256).max);
        uniRouter.swapTokensForExactTokens(_outputAmount, type(uint256).max, route, address(this), block.timestamp + 1);
    }

    function swapUniOrSushi2(address _inputToken, address _outputToken, uint256 _inputAmount) internal returns (uint[] memory amounts){

        uint256 outputAmount = getPriceUniLike2(_inputToken, _outputToken, _inputAmount, uniRouter);

        address[] memory route = getRoute(_inputToken, _outputToken);

        IERC20 _inputToken = IERC20(_inputToken);

        if(address(_inputToken) == _outputToken) {
            return amounts;
        }

        _inputToken.approve(address(uniRouter), 0);
        _inputToken.approve(address(uniRouter), type(uint256).max);
        return uniRouter.swapExactTokensForTokens(_inputAmount, outputAmount, route, address(this), block.timestamp + 1);
    }

    function setCustomHop(address _token, address _hop) external onlyOwner {
        customHops[_token] = CustomHop({
            hop: _hop
            // dex: _dex
        });
    }

    function saveToken(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }

    function saveEth(address payable _to, uint256 _amount) external onlyOwner {
        _to.call{value: _amount}("");
    }

    function getPrice(address _inputToken, address _outputToken, uint256 _outputAmount) public view returns(uint256)  {
        if(_inputToken == _outputToken) {
            return _outputAmount;
        }

        // check if token is smartPool
        if(smartPoolRegistry.inRegistry(_outputToken)) {
            uint256 ethAmount =  getPriceSmartPool(_outputToken, _outputAmount);

            // if input was not WETH
            if(_inputToken != address(WETH)) {
                return getPrice(_inputToken, address(WETH), ethAmount);
            }

            return ethAmount;
        }

        // if input and output are not WETH (2 hop swap)
        if(_inputToken != address(WETH) && _outputToken != address(WETH)) {
            (uint256 middleInputAmount,) = getBestPriceSushiUni(address(WETH), _outputToken, _outputAmount);
            (uint256 inputAmount,) = getBestPriceSushiUni(_inputToken, address(WETH), middleInputAmount);

            return inputAmount;
        }

        // else single hop swap
        (uint256 inputAmount,) = getBestPriceSushiUni(_inputToken, _outputToken, _outputAmount);

        return inputAmount;
    }

    function getBestPriceSushiUni(address _inputToken, address _outputToken, uint256 _outputAmount) internal view returns(uint256, DexChoice) {
        uint256 uniAmount = getPriceUniLike(_inputToken, _outputToken, _outputAmount, uniRouter);
        return (uniAmount, DexChoice.Uni);
    }

    function getRoute(address _inputToken, address _outputToken) internal view returns(address[] memory route) {
        // if both input and output are not WETH
        if(_inputToken != address(WETH) && _outputToken != address(WETH)) {
            route = new address[](3);
            route[0] = _inputToken;
            route[1] = address(WETH);
            route[2] = _outputToken;
            return route;
        }

        route = new address[](2);
        route[0] = _inputToken;
        route[1] = _outputToken;

        return route;
    }

    function getPriceUniLike(address _inputToken, address _outputToken, uint256 _outputAmount, IUniRouter _router) internal view returns(uint256) {
        if(_inputToken == _outputToken) {
            return(_outputAmount);
        }

        try _router.getAmountsIn(_outputAmount, getRoute(_inputToken, _outputToken))  returns(uint256[] memory amounts) {
            return amounts[0];
        } catch {
            return type(uint256).max;
        }
        return type(uint256).max;
    }

    function getPriceUniLike2(address _inputToken, address _outputToken, uint256 _inputAmount, IUniRouter _router) internal view returns(uint256) {
        if(_inputToken == _outputToken) {
            return(_inputAmount);
        }

        try _router.getAmountsOut(_inputAmount, getRoute(_inputToken, _outputToken))  returns(uint256[] memory amounts) {
            return amounts[1];
        } catch {
            return type(uint256).max;
        }
        return type(uint256).max;
    }

    // NOTE input token must be WETH
    function getPriceSmartPool(address _smartPool, uint256 _smartPoolAmount) public view returns(uint256) {
        ISmartPool smartPool = ISmartPool(_smartPool);
        (address[] memory tokens, uint256[] memory amounts) = smartPool.calcTokensForAmount(_smartPoolAmount);

        uint256 inputAmount = 0;

        for(uint256 i = 0; i < tokens.length; i ++) {
            inputAmount += getPrice(address(WETH), tokens[i], amounts[i]);
        }

        return inputAmount;
    }


    function encodeData(uint256 _outputAmount) external pure returns(bytes memory){
        return abi.encode((_outputAmount));
    }

    function bmul(uint a, uint b)
    public pure
    returns (uint)
    {
        uint c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint c1 = c0 + (BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint c2 = c1 / BONE;
        return c2;
    }
}