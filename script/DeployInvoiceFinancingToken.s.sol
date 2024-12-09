// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {InvoiceFinancingToken} from "../src/InvoiceFinancingToken.sol";

contract DeployInvoiceFinancingToken is Script {
    function run() external returns (InvoiceFinancingToken) {
        vm.startBroadcast();
        InvoiceFinancingToken invoiceToken = new InvoiceFinancingToken();
        vm.stopBroadcast();
        return invoiceToken;
    }
}