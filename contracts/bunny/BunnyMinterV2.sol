// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/// https://bscscan.com/address/0x8cb88701790f650f273c8bb2cc4c5f439cd65219#readProxyContract
/// ->
/// https://bscscan.com/address/0xc31b712bad4326227ee93e88c0e6b1839be35fc0#code

/*
  ___                      _   _
 | _ )_  _ _ _  _ _ _  _  | | | |
 | _ \ || | ' \| ' \ || | |_| |_|
 |___/\_,_|_||_|_||_\_, | (_) (_)
                    |__/

*
* MIT License
* ===========
*
* Copyright (c) 2020 BunnyFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../interfaces/IBunnyMinterV2.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IPriceCalculator.sol";

import "../zap/ZapBSC.sol";
import "../library/SafeToken.sol";

contract BunnyMinterV2 is IBunnyMinterV2, OwnableUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BUNNY = 0xe5f34811956b3aeF599bdA00Bbd4BEB690C6644F;
    address public constant BUNNY_BNB = 0xE5B7F0651D579c30Ee58CDD62EF41Ac293e5ca90;
    address public constant BUNNY_POOL = 0x443F54A24774435f743b62888E47163d8a4682E0;

    address public constant DEPLOYER = 0x4BEF8eD46a3Cb6bD9aEDEcEf5CfD11EF73da3D11;
    address private constant TIMELOCK = 0xEA00ADa0c77394d58e9cc83FC69ca2C2C84a6116;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint public constant FEE_MAX = 10000;

    ZapBSC public constant zapBSC = ZapBSC(0x46822E8585e07E81E95154D1E49d07048941Ca72);
    IPriceCalculator public constant priceCalculator = IPriceCalculator(0xC825637C56A6267960473E29976fC1DE02Df0fd1);

    IPancakeRouter02 private constant router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    /* ========== STATE VARIABLES ========== */

    address public bunnyChef;
    mapping(address => bool) private _minters;
    address public _deprecated_helper; // deprecated

    uint public PERFORMANCE_FEE;
    uint public override WITHDRAWAL_FEE_FREE_PERIOD;
    uint public override WITHDRAWAL_FEE;

    uint public override bunnyPerProfitBNB;
    uint public bunnyPerBunnyBNBFlip;   // will be deprecated

    /* ========== MODIFIERS ========== */

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "BunnyMinterV2: caller is not the minter");
        _;
    }

    modifier onlyBunnyChef {
        require(msg.sender == bunnyChef, "BunnyMinterV2: caller not the bunny chef");
        _;
    }

    receive() external payable {}

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        WITHDRAWAL_FEE_FREE_PERIOD = 3 days;
        WITHDRAWAL_FEE = 50;
        PERFORMANCE_FEE = 3000;

        bunnyPerProfitBNB = 5e18;
        bunnyPerBunnyBNBFlip = 6e18;

        __Ownable_init(); ///I add this line

        IBEP20(BUNNY).approve(BUNNY_POOL, uint(- 1));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function transferBunnyOwner(address _owner) external onlyOwner {
        Ownable(BUNNY).transferOwnership(_owner);
    }

    function setWithdrawalFee(uint _fee) external onlyOwner {
        require(_fee < 500, "wrong fee");
        // less 5%
        WITHDRAWAL_FEE = _fee;
    }

    function setPerformanceFee(uint _fee) external onlyOwner {
        require(_fee < 5000, "wrong fee");
        PERFORMANCE_FEE = _fee;
    }

    function setWithdrawalFeeFreePeriod(uint _period) external onlyOwner {
        WITHDRAWAL_FEE_FREE_PERIOD = _period;
    }

    function setMinter(address minter, bool canMint) external override onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }

    function setBunnyPerProfitBNB(uint _ratio) external onlyOwner {
        bunnyPerProfitBNB = _ratio;
    }

    function setBunnyPerBunnyBNBFlip(uint _bunnyPerBunnyBNBFlip) external onlyOwner {
        bunnyPerBunnyBNBFlip = _bunnyPerBunnyBNBFlip;
    }

    function setBunnyChef(address _bunnyChef) external onlyOwner {
        require(bunnyChef == address(0), "BunnyMinterV2: setBunnyChef only once");
        bunnyChef = _bunnyChef;
    }

    /* ========== VIEWS ========== */

    function isMinter(address account) public view override returns (bool) {
        if (IBEP20(BUNNY).getOwner() != address(this)) {
            return false;
        }
        return _minters[account];
    }

    function amountBunnyToMint(uint bnbProfit) public view override returns (uint) {
        return bnbProfit.mul(bunnyPerProfitBNB).div(1e18);
    }

    function amountBunnyToMintForBunnyBNB(uint amount, uint duration) public view override returns (uint) {
        return amount.mul(bunnyPerBunnyBNBFlip).mul(duration).div(365 days).div(1e18);
    }

    function withdrawalFee(uint amount, uint depositedAt) external view override returns (uint) {
        if (depositedAt.add(WITHDRAWAL_FEE_FREE_PERIOD) > block.timestamp) {
            return amount.mul(WITHDRAWAL_FEE).div(FEE_MAX);
        }
        return 0;
    }

    function performanceFee(uint profit) public view override returns (uint) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    /* ========== V1 FUNCTIONS ========== */

    function mintFor(address asset, uint _withdrawalFee, uint _performanceFee, address to, uint) public payable override onlyMinter {
        uint feeSum = _performanceFee.add(_withdrawalFee);
        _transferAsset(asset, feeSum);

        if (asset == BUNNY) {
            IBEP20(BUNNY).safeTransfer(DEAD, feeSum);
            return;
        }

        uint bunnyBNBAmount = _zapAssetsToBunnyBNB(asset, feeSum);
        if (bunnyBNBAmount == 0) return;

        IBEP20(BUNNY_BNB).safeTransfer(BUNNY_POOL, bunnyBNBAmount);
        IStakingRewards(BUNNY_POOL).notifyRewardAmount(bunnyBNBAmount);

        if (_performanceFee > 0) {
            (uint contribution, ) = priceCalculator.valueOfAsset(asset, _performanceFee);
            uint mintBunny = amountBunnyToMint(contribution);
            if (mintBunny == 0) return;
            _mint(mintBunny, to);
        }
    }

    /* ========== PancakeSwap V2 FUNCTIONS ========== */

    function mintForV2(address asset, uint _withdrawalFee, uint _performanceFee, address to, uint timestamp) external payable override onlyMinter {
        mintFor(asset, _withdrawalFee, _performanceFee, to, timestamp);
    }

    /* ========== BunnyChef FUNCTIONS ========== */

    function mint(uint amount) external override onlyBunnyChef {
        if (amount == 0) return;
        _mint(amount, address(this));
    }

    function safeBunnyTransfer(address _to, uint _amount) external override onlyBunnyChef {
        if (_amount == 0) return;

        uint bal = IBEP20(BUNNY).balanceOf(address(this));
        if (_amount <= bal) {
            IBEP20(BUNNY).safeTransfer(_to, _amount);
        } else {
            IBEP20(BUNNY).safeTransfer(_to, bal);
        }
    }

    // @dev should be called when determining mint in governance. Bunny is transferred to the timelock contract.
    function mintGov(uint amount) external override onlyOwner {
        if (amount == 0) return;
        _mint(amount, TIMELOCK);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _transferAsset(address asset, uint amount) private {
        if (asset == address(0)) {
            // case) transferred BNB
            require(msg.value >= amount);
        } else {
            IBEP20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _zapAssetsToBunnyBNB(address asset, uint amount) private returns (uint bunnyBNBAmount) {
        uint _initBunnyBNBAmount = IBEP20(BUNNY_BNB).balanceOf(address(this));

        if (asset == address(0)) {
            zapBSC.zapIn{ value : amount }(BUNNY_BNB);
        }
        else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IBEP20(asset).allowance(address(this), address(router)) == 0) {
                IBEP20(asset).safeApprove(address(router), uint(- 1));
            }

            IPancakePair pair = IPancakePair(asset);
            address token0 = pair.token0();
            address token1 = pair.token1();

            (uint amountToken0, uint amountToken1) = router.removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);

            if (IBEP20(token0).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(token0).safeApprove(address(zapBSC), uint(- 1));
            }
            if (IBEP20(token1).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(token1).safeApprove(address(zapBSC), uint(- 1));
            }

            zapBSC.zapInToken(token0, amountToken0, BUNNY_BNB);
            zapBSC.zapInToken(token1, amountToken1, BUNNY_BNB);
        }
        else {
            if (IBEP20(asset).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(asset).safeApprove(address(zapBSC), uint(- 1));
            }

            zapBSC.zapInToken(asset, amount, BUNNY_BNB);
        }

        bunnyBNBAmount = IBEP20(BUNNY_BNB).balanceOf(address(this)).sub(_initBunnyBNBAmount);
    }

    function _mint(uint amount, address to) private {
        BEP20 tokenBUNNY = BEP20(BUNNY);

        tokenBUNNY.mint(amount);
        if (to != address(this)) {
            tokenBUNNY.transfer(to, amount);
        }

        uint bunnyForDev = amount.mul(15).div(100);
        tokenBUNNY.mint(bunnyForDev);
        IStakingRewards(BUNNY_POOL).stakeTo(bunnyForDev, DEPLOYER);
    }
}
