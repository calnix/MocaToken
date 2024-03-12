// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Sphinx, Network} from "@sphinx-labs/contracts/SphinxPlugin.sol";

import {MocaToken} from "./../src/MocaToken.sol";
import {MocaOFT} from "./../src/MocaOFT.sol";
import {MocaTokenAdapter} from "./../src/MocaTokenAdapter.sol";


import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

abstract contract LZState is Sphinx, Script {
    
    //Note: LZV2 testnet addresses

    uint16 public sepoliaID = 40161;
    address public sepoliaEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 public mumbaiID = 40109;
    address public mumbaiEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 public arbSepoliaID = 40231;
    address public arbSepoliaEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 homeChainID = mumbaiID;
    address homeLzEP = mumbaiEP;

    uint16 remoteChainID = arbSepoliaID;
    address remoteLzEP = arbSepoliaEP;

    // Sphinx setup
    function setUp() public {

        sphinxConfig.owners = [address(0x5B7c596ef4804DC7802dB28618d353f7Bf14C619)]; // Add owner(s)
        sphinxConfig.orgId = "clszio7580001djh8pvnrbaka"; // Add Sphinx org ID
        
        sphinxConfig.testnets = [
            Network.arbitrum_sepolia,
            Network.polygon_mumbai
        ];

        sphinxConfig.projectName = "TestTokenV3";
        sphinxConfig.threshold = 1;
    }


}

contract DeployV2 is LZState {
    function run() public sphinx {
        
        //Pre-compile the `CREATE2` addresses of contracts

        // ------------- MOCA TOKEN ----------------------------------------------------------
        string memory name = "TestToken";
        string memory symbol = "TTv2";
        address treasury = safeAddress();

        bytes memory mocaTokenParams = abi.encode(name, symbol, treasury);

        MocaToken mocaToken = MocaToken(vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: keccak256(abi.encodePacked(type(MocaToken).creationCode, mocaTokenParams)),
            deployer: CREATE2_FACTORY
        }));


        // ------------- MOCA TOKEN ADAPTOR ----------------------------------------------------
        address token = address(mocaToken);
        address layerZeroEndpoint = homeLzEP;
        address delegate = safeAddress();
        address owner = safeAddress();

        bytes memory mocaAdaptorParams = abi.encode(token, layerZeroEndpoint, delegate, owner);
        
        MocaTokenAdapter mocaTokenAdapter = MocaTokenAdapter(vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: keccak256(abi.encodePacked(type(MocaTokenAdapter).creationCode, mocaAdaptorParams)),
            deployer: CREATE2_FACTORY
        }));


        // ------------- MOCA TOKEN OFT: REMOTE --------------------------------------------------

        address layerZeroEndpointRemote = remoteLzEP;
        //address deletate = safeAddress();
        //address owner = safeAddress();

        bytes memory mocaOFTparams = abi.encode(name, symbol, layerZeroEndpointRemote, delegate, owner);
        
        MocaOFT mocaOFT = MocaOFT(vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: keccak256(abi.encodePacked(type(MocaOFT).creationCode, mocaOFTparams)),
            deployer: CREATE2_FACTORY
        }));



        // Deploy and initialize the contracts. ContractA exists on Poly_Mumbai (80001), and ContractB exists on Arb_Sepolia (421614)
        if (block.chainid == 80001) { // Home: Mumbai

            new MocaToken{ salt: bytes32(0) }(name, symbol, treasury);
            new MocaTokenAdapter{ salt: bytes32(0) }(address(mocaToken), layerZeroEndpoint, delegate, owner);

        } else if (block.chainid == 421614) { // Remote
        
            new MocaOFT{ salt: bytes32(0) }(name, symbol, layerZeroEndpointRemote, delegate, owner);
        }

        // SETUP

        if (block.chainid == 80001) { // Home: Mumbai
        
            //............ Set peer on Home
            bytes32 peer = bytes32(uint256(uint160(address(mocaOFT))));
            mocaTokenAdapter.setPeer(remoteChainID, peer);

            //............ Set gasLimits on Home

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains         
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
            enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");
            
            // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
            enforcedOptionParams[1] = EnforcedOptionParam(remoteChainID, 2, hex"000301001303000000000000000000000000000000000000");
            
            mocaTokenAdapter.setEnforcedOptions(enforcedOptionParams);

            //........... Set rateLimits

            mocaTokenAdapter.setOutboundLimit(remoteChainID, 10 ether);
            mocaTokenAdapter.setInboundLimit(remoteChainID, 10 ether);

        } else if (block.chainid == 421614) { // Remote

            //............ Set peer on Remote

            bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdapter))));
            mocaOFT.setPeer(homeChainID, peer);
            

            //............ Set gasLimits on Remote

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
            enforcedOptionParams[0] = EnforcedOptionParam(homeChainID, 1, hex"00030100110100000000000000000000000000030d40");
        
            // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
            enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001303000000000000000000000000000000000000");
            mocaOFT.setEnforcedOptions(enforcedOptionParams);      

            //........... Set rateLimits

            mocaOFT.setOutboundLimit(homeChainID, 10 ether);
            mocaOFT.setInboundLimit(homeChainID, 10 ether);

        }

    }
}

// npx sphinx propose script/DeploySphinxV2.s.sol --networks testnets --tc DeployV2


/**
        // SEND SUM TOKENS
            
        //set approval for adaptor to spend tokens
        mocaToken.approve(address(mocaTokenAdapter), 1 ether);

        // send params
        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteChainID,
            to: bytes32(uint256(uint160(address(msg.sender)))),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: nullBytes,
            composeMsg: nullBytes,
            oftCmd: nullBytes
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaTokenAdapter.quoteSend(sendParam, false);

        // send tokens xchain
        mocaTokenAdapter.send{value: (messagingFee.nativeFee * 2) }(sendParam, messagingFee, payable(msg.sender));

 */