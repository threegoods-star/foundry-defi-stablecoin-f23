//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSECngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public USER2 = makeAddr("user2");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_MINTED = 4 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER2, STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    ///Constructor Tests /////
    //////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////
    ///Price Tests /////
    ////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }
    ////////////////////////////////
    ///depositCollateral Tests /////
    ////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ////////////////////////////////
    ///healthFastor Tests/// ///////
    ////////////////////////////////

    function testHealthFactor() public depositedCollateral {
        uint256 healthFactorOfUser = dsce.getHealthFactor(USER);
        console.log(healthFactorOfUser);
    }

    ////////////////////////////////
    ///mintDsc Tests         ///////
    ////////////////////////////////

    function testMintedDscNmuber() public {
        vm.startPrank(USER);
        uint256 expectedDscMinted = 0;
        uint256 antualDscMinted = dsce.getDSCMinted(USER);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        assertEq(expectedDscMinted, antualDscMinted);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.mintDsc(1);
        vm.stopPrank();
    }

    function testMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 AccountCollateralValueInUsd = dsce.getAccountCollateralValue(USER);
        // uint256 userHealthFactor = dsce.getHealthFactor(USER);
        // vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, userHealthFactor));
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.mintDsc(AccountCollateralValueInUsd);

        uint256 DscMintedValue = AccountCollateralValueInUsd / 2;
        dsce.mintDsc(AccountCollateralValueInUsd / 2);
        uint256 dscMintedAnctual = dsce.getDSCMinted(USER);
        assertEq(DscMintedValue, dscMintedAnctual);
        console.log(DscMintedValue);
        console.log(dscMintedAnctual);
        uint256 healthNumber = ((DscMintedValue) * 1e18) / (dscMintedAnctual + 1);
        console.log("healthNumber", healthNumber);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, healthNumber));
        dsce.mintDsc(1);
        vm.stopPrank();
    }

    ////////////////////////////////
    ///burnDsc   Tests       ///////
    ////////////////////////////////
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); //10 ether
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_MINTED); //4 ether
        vm.stopPrank();
        _;
    }

    function testBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(address(USER));
        dsc.approve(address(dsce), AMOUNT_MINTED / 2);
        vm.startPrank(address(dsce));
        dsce.burnDsc(AMOUNT_MINTED / 2, USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        assertEq(totalDscMinted, AMOUNT_MINTED / 2);
        assertEq(collateralValueInUsd, collateralValue);
        vm.stopPrank();
        vm.stopPrank();
    }

    ////////////////////////////////
    ///redeemCollateral   Tests/////
    ////////////////////////////////

    function testRedeemCollateralSuccess() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 qwe = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        console.log(qwe);
        dsce.redeemCollateral(weth, AMOUNT_MINTED / 2);
        (uint256 dsc, uint256 collateral) = dsce.getAccountInformation(USER);
        console.log(dsc, collateral);
        console.log(dsce.getHealthFactor(USER));
        vm.stopPrank();
    }

    function testRedeemCollateralsuccess1() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 qwe = 19992 ether;
        uint256 asd = dsce.getTokenAmountFromUsd(weth, qwe);
        console.log(asd);
        dsce.redeemCollateral(weth, asd);
        (uint256 dsc, uint256 collateral) = dsce.getAccountInformation(USER);
        console.log(dsc, collateral);
        console.log(dsce.getHealthFactor(USER));
        vm.stopPrank();
    }

    function testRedeemCollateralFail() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        uint256 qwe = 19993 ether;
        uint256 asd = dsce.getTokenAmountFromUsd(weth, qwe);
        console.log(asd);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 875000000000000000));
        dsce.redeemCollateral(weth, asd);

        (uint256 dsc, uint256 collateral) = dsce.getAccountInformation(USER);
        console.log(dsc, collateral);
        console.log(dsce.getHealthFactor(USER));
        vm.stopPrank();
    }
    ////////////////////////////////
    ///liquidate Tests       ///////
    ////////////////////////////////

    modifier userAndUser2depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); //10 ether
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_MINTED); //4 ether
        vm.stopPrank();
        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); //10 ether
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_MINTED); //4 ether
        vm.stopPrank();
        _;
    }

    function testZeroOutCollateral() public userAndUser2depositedCollateralAndMintedDsc {
        // 1. 验证初始状态
        uint256 initialCollateral = dsce.getCollateralDeposited(USER, address(weth));
        assertEq(initialCollateral, AMOUNT_COLLATERAL);

        // 2. 使用Foundry的作弊码直接获取存储布局
        // 首先获取s_collateralDeposited的基准slot
        uint256 baseSlot = 2; // 根据合约状态变量顺序确认

        // 3. 精确计算嵌套映射存储位置
        bytes32 userPosition = keccak256(abi.encode(USER, baseSlot));
        bytes32 wethPosition = keccak256(abi.encode(address(weth), uint256(userPosition)));

        // 4. 调试输出关键信息
        console.log("User position:", uint256(userPosition));
        console.log("WETH final position:", uint256(wethPosition));

        // 5. 直接读取和修改存储
        bytes32 currentValue = vm.load(address(dsce), wethPosition);
        console.log("Current collateral value:", uint256(currentValue));
        uint256 asd = 7 ether;
        uint256 qwe = dsce.getTokenAmountFromUsd(weth, asd);
        // 6. 修改存储（清零）
        vm.store(address(dsce), wethPosition, bytes32(qwe));

        // 7. 双重验证
        bytes32 updatedValue = vm.load(address(dsce), wethPosition);
        assertEq(uint256(updatedValue), qwe, "Storage value not updated correctly");

        // 8. 通过合约函数验证
        uint256 contractView = dsce.getCollateralDeposited(USER, address(weth));
        assertEq(contractView, qwe, "Contract view not matching storage update");
        uint256 asd1 = 4 ether;
        uint256 qwe1 = dsce.getTokenAmountFromUsd(weth, asd1);
        uint256 zxc = qwe1 + (qwe1 * 10 / 100);
        console.log(zxc);
        vm.startPrank(USER2);
        dsc.approve(address(dsce), AMOUNT_MINTED);
        dsce.liquidate(weth, USER, AMOUNT_MINTED);
        vm.stopPrank();
        uint256 u1 = 0.0013 ether;
        uint256 u2 = 0.0022 ether;
        uint256 u3 = 4 ether;
        uint256 wethBalance = ERC20Mock(weth).balanceOf(USER2);
        assertEq(u1, dsce.getCollateralDeposited(USER, weth));
        assertEq(u2, wethBalance);
        assertEq(0, dsce.getDSCMinted(USER));
        uint256 dscBalance = dsc.balanceOf(USER2);
        console.log("USER2 DSC Balance:", dscBalance);
        assertEq(u3, dsce.getDSCMinted(USER2));
    }

    function testDebugStorage() public {
        // 打印基础槽位值
        for (uint256 slot = 0; slot < 10; slot++) {
            bytes32 value = vm.load(address(dsce), bytes32(slot));
            console.log("Slot", slot, ":", uint256(value));
        }

        // 打印映射键的存储值
        bytes32 calculatedSlot = keccak256(abi.encode(USER, keccak256(abi.encode(weth, uint256(2)))));
        console.log("Calculated slot value:", uint256(vm.load(address(dsce), calculatedSlot)));
    }

    function findRealSlot(address user, address token)
        public
        userAndUser2depositedCollateralAndMintedDsc
        returns (uint256)
    {
        uint256 target = dsce.getCollateralDeposited(user, token);

        // 扩展搜索范围（包含可能的代理模式偏移）
        for (uint256 i = 0; i < 256; i++) {
            // 标准映射计算
            bytes32 standardSlot = keccak256(abi.encode(user, keccak256(abi.encode(token, i))));

            // 代理模式可能偏移（EIP-1967）
            bytes32 proxySlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1 + i);

            if (uint256(vm.load(address(dsce), standardSlot)) == target) {
                console.log("Found standard slot at:", i);
                return i;
            }

            if (uint256(vm.load(address(dsce), proxySlot)) == target) {
                console.log("Found proxy slot at:", i);
                return i;
            }
        }
        revert("Real slot not found after full search");
    }

    function testdebugAdvanced() public userAndUser2depositedCollateralAndMintedDsc {
        bytes32 slot4 = bytes32(uint256(4));
        // 检查映射指针位置
        console.log("Slot 4 (mapping pointer):", uint256(vm.load(address(dsce), slot4)));

        // 检查可能的动态数组
        bytes32 arrLengthSlot = bytes32(uint256(4)); // 假设槽位4是数组长度
        uint256 arrLength = uint256(vm.load(address(dsce), arrLengthSlot));
        console.log("Possible array length:", arrLength);

        // 检查数组元素
        for (uint256 i = 0; i < arrLength; i++) {
            bytes32 element = vm.load(address(dsce), bytes32(uint256(keccak256(abi.encode(4))) + i));
            console.log("Array element", i, ":", uint256(element));
        }
    }

    function testdebugRealSlots() public userAndUser2depositedCollateralAndMintedDsc {
        // 用户地址数组位置（槽位4）
        bytes32 usersSlot = bytes32(uint256(4));
        uint256 usersLength = uint256(vm.load(address(dsce), usersSlot));
        console.log("User addresses array length:", usersLength);

        // 遍历用户数组
        bytes32 usersDataStart = keccak256(abi.encode(uint256(4)));
        for (uint256 i = 0; i < usersLength; i++) {
            address user = address(uint160(uint256(vm.load(address(dsce), bytes32(uint256(usersDataStart) + i)))));
            console.log("User", i, ":", user);

            // 获取该用户的抵押品存储槽
            bytes32 collateralSlot = keccak256(
                abi.encode(
                    user,
                    keccak256(abi.encode(weth, uint256(5))) // 假设基础槽位5
                )
            );
            console.log("Collateral amount:", uint256(vm.load(address(dsce), collateralSlot)));
        }
    }

    function testdebugStorageSlots() public userAndUser2depositedCollateralAndMintedDsc {
        // 1. 检查动态数组长度
        bytes32 arrayLengthSlot = bytes32(uint256(4));
        uint256 arrayLength = uint256(vm.load(address(dsce), arrayLengthSlot));
        console.log("Collateral tokens array length:", arrayLength);

        // 2. 检查数组元素
        bytes32 arrayStart = keccak256(abi.encode(uint256(4)));
        for (uint256 i = 0; i < arrayLength; i++) {
            address token = address(uint160(uint256(vm.load(address(dsce), bytes32(uint256(arrayStart) + i)))));
            console.log("Token", i, ":", token);
        }

        // 3. 检查用户抵押品（示例用户USER和第一个代币）
        address user = USER;
        address token = address(uint160(uint256(vm.load(address(dsce), bytes32(uint256(arrayStart))))));

        bytes32 collateralSlot = keccak256(
            abi.encode(keccak256(abi.encode(user, uint256(2))), uint256(keccak256(abi.encode(token, uint256(0)))))
        );
        uint256 amount = uint256(vm.load(address(dsce), collateralSlot));
        console.log("User collateral amount:", amount);
    }
}
