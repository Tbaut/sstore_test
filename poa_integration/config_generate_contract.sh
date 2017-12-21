#!/bin/bash

# Deploys PoA network with next parameters:
# 1) NUM_AUTHORITIES authorities nodes
# 2) NUM_REGULAR regular nodes
# 3) every authority node is running a key server = single SS

function join_by { local IFS="$1"; shift; echo "$*"; }

NUM_AUTHORITIES=3
NUM_REGULAR=0
NUM_NODES=$(($NUM_AUTHORITIES+$NUM_REGULAR))
UI_PORT_BASE=8180
RPC_PORT_BASE=8545
WS_PORT_BASE=8600
NETWORK_PORT_BASE=10000
SSTORE_INTERNAL_PORT_BASE=12000
SSTORE_HTTP_PORT_BASE=13000

###############################################################################
### generate keys #############################################################
###############################################################################
rm -rf db.*
rm -rf *.toml
for i in `seq 1 $NUM_NODES`
do
	openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > key 2>/dev/null
	ui_port[i]=$(($UI_PORT_BASE+$i-1))
	rpc_port[i]=$(($RPC_PORT_BASE+$i-1))
	ws_port[i]=$(($WS_PORT_BASE+$i-1))
	network_port[i]=$(($NETWORK_PORT_BASE+$i-1))
	secret[i]=`cat key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//'|xargs -0 printf "%64s"|tr ' ' '0'`
	public[i]=`cat key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//'|xargs -0 printf "%64s"|tr ' ' '0'`
	enode[i]="\"enode://${public[i]}@127.0.0.1:${network_port[i]}\""
	if [ "$i" -le "$NUM_AUTHORITIES" ]; then
		sstore_internal_port[i]=$(($SSTORE_INTERNAL_PORT_BASE+$i-1))
		sstore_http_port[i]=$(($SSTORE_HTTP_PORT_BASE+$i-1))
		if [ "$i" -eq 1 ]; then
			sstore_http_port[i]=8082
		fi
		ssnode[i]="\"${public[i]}@127.0.0.1:${sstore_internal_port[i]}\""
	fi

	openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > key 2>/dev/null
	account_secret[i]=`cat key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//'|xargs -0 printf "%64s"|tr ' ' '0'`
	account_public[i]=`cat key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//'|xargs -0 printf "%64s"|tr ' ' '0'`
done
rm key

###############################################################################
### insert accounts && password file ##########################################
###############################################################################
solidity_validators_list=""
json_validators_list=""
json_acccounts_list=""
echo password>password_file
for i in `seq 1 $NUM_NODES`
do
	address=`../ethstore insert ${secret[i]} password_file --dir db.poa_ss${i}/keys/POA`
	addresses[i]=$address
	comma=","
	if [ "$i" -eq 1 ]; then
		comma=""
	fi
	if [ "$i" -le "$NUM_AUTHORITIES" ]; then
		solidity_validators_list="${solidity_validators_list}${comma}${address}"
		json_validator="\"${address}\""
		json_validators_list="${json_validators_list}${comma}${json_validator}"
		json_account="\"${address}\": { \"balance\": \"1000\" }"
		json_acccounts_list="${json_acccounts_list}${comma}${json_account}"
	fi

	address=`../ethstore insert ${account_secret[i]} password_file --dir db.poa_ss${i}/keys/POA`
	account_address[i]=address
	json_account="\"${address}\": { \"balance\": \"10000000000000000000000000000000000000000000000000\" }"
	json_acccounts_list="${json_acccounts_list},${json_account}"
done

###############################################################################
### generate config files for authorities nodes ###############################
###############################################################################
for i in `seq 1 $NUM_AUTHORITIES`
do
	self_enode=${enode[i]}
	bootnodes=("${enode[@]/$self_enode}")
	bootnodes=$(join_by , ${bootnodes[@]})
	self_ssnode=${ssnode[i]}
	ssnodes=("${ssnode[@]/$self_ssnode}")
	ssnodes=$(join_by , ${ssnodes[@]})
	disable_ui="false"
	force_ui="true"
#	if [ "$i" -eq 1 ]; then
#		disable_ui="false"
#		force_ui="true"
#	fi
	config_contents="
# node#$i
# self_secret: ${secret[i]}
# self_public: ${public[i]}

[parity]
chain = \"poa_chain.json\"
base_path = \"db.poa_ss${i}\"

[ui]
force = $force_ui
disable = $disable_ui
port = ${ui_port[i]}

[rpc]
disable = $disable_ui
port = ${rpc_port[i]}
apis = [\"all\"]

[websockets]
disable = $disable_ui
port = ${ws_port[i]}
apis = [\"all\"]

[ipc]
disable = true

[dapps]
disable = $disable_ui

[network]
port = ${network_port[i]}
node_key = \"${secret[i]}\"
bootnodes = [$bootnodes]

[ipfs]
enable = false

[snapshots]
disable_periodic = true

[secretstore]
disable = false
disable_acl_check = true
self_secret = \"${secret[i]}\"
nodes = [$ssnodes]
interface = \"local\"
port = ${sstore_internal_port[i]}
http_interface = \"local\"
http_port = ${sstore_http_port[i]}
path = \"db.poa_ss${i}/secretstore\"
service_contract = \"registry\"

[mining]
author = \"${addresses[i]}\"
engine_signer = \"${addresses[i]}\"
force_sealing = true

[account]
unlock = [\"${addresses[i]}\"]
password = [\"password_file\"]
"
	echo "$config_contents" >"poa_ss${i}.toml"
done

###############################################################################
### generate config files for regular nodes ###################################
###############################################################################

for i in `seq 1 $NUM_REGULAR`
do
	j=$(($NUM_AUTHORITIES+$i))
	self_enode=${enode[j]}
	bootnodes=("${enode[@]/$self_enode}")
	bootnodes=$(join_by , ${bootnodes[@]})
	disable_ui="true"
	force_ui="false"
	config_contents="
# node#$j
# self_secret: ${secret[j]}
# self_public: ${public[j]}

[parity]
chain = \"poa_chain.json\"
base_path = \"db.poa_ss${j}\"

[ui]
force = $force_ui
disable = $disable_ui
port = ${ui_port[j]}

[rpc]
disable = $disable_ui
port = ${rpc_port[i]}
apis = [\"all\"]

[websockets]
disable = $disable_ui
port = ${ws_port[i]}
apis = [\"all\"]

[ipc]
disable = true

[dapps]
disable = $disable_ui

[network]
port = ${network_port[j]}
node_key = \"${secret[j]}\"
bootnodes = [$bootnodes]

[ipfs]
enable = false

[snapshots]
disable_periodic = true
"
	echo "$config_contents" >"poa_ss${j}.toml"
done

###############################################################################
### create validators set contract ############################################
###############################################################################

validators_set_contract='
pragma solidity ^0.4.8;

contract ValidatorSet {
    event InitiateChange(bytes32 indexed _parent_hash, address[] _new_set);

    function getValidators() constant returns (address[] _validators);
    function finalizeChange();
}

// Existing validators can give support to addresses.
// Support can not be added once MAX_VALIDATORS are present.
// Once given, support can be removed.
// Addresses supported by more than half of the existing validators are the validators.
// Malicious behaviour causes support removal.
// Benign misbehaviour causes supprt removal if its called again after MAX_INACTIVITY.
// Benign misbehaviour can be absolved before being called the second time.

contract MajorityList is ValidatorSet {

    // EVENTS

    event Report(address indexed reporter, address indexed reported, bool indexed malicious);
    event Support(address indexed supporter, address indexed supported, bool indexed added);
    event ChangeFinalized(address[] current_set);

    struct ValidatorStatus {
        // Is this a validator.
        bool isValidator;
        // Index in the validatorList.
        uint index;
        // Validator addresses which supported the address.
        AddressSet.Data support;
        // Keeps track of the votes given out while the address is a validator.
        address[] supported;
        // Initial benign misbehaviour time tracker.
        mapping(address => uint) firstBenign;
        // Repeated benign misbehaviour counter.
        AddressSet.Data benignMisbehaviour;
    }

    // System address, used by the block sealer.
    address SYSTEM_ADDRESS = 0xfffffffffffffffffffffffffffffffffffffffe;
    // Support can not be added once this number of validators is reached.
    uint public constant MAX_VALIDATORS = 30;
    // Time after which the validators will report a validator as malicious.
    uint public constant MAX_INACTIVITY = 6 hours;
    // Ignore misbehaviour older than this number of blocks.
    uint public constant RECENT_BLOCKS = 20;

    // STATE

    // Current list of addresses entitled to participate in the consensus.
    address[] public validatorsList;
    // Pending list of validator addresses.
    address[] pendingList;
    // Was the last validator change finalized.
    bool finalized;
    // Tracker of status for each address.
    mapping(address => ValidatorStatus) validatorsStatus;

    // CONSTRUCTOR

    // Used to lower the constructor cost.
    AddressSet.Data initialSupport;
    bool private initialized;

    // Each validator is initially supported by all others.
    function MajorityList() {
        pendingList = [validators_list];

        initialSupport.count = pendingList.length;
        for (uint i = 0; i < pendingList.length; i++) {
            address supporter = pendingList[i];
            initialSupport.inserted[supporter] = true;
        }
    }

    // Has to be called once before any other methods are called.
    function initializeValidators() uninitialized {
        for (uint j = 0; j < pendingList.length; j++) {
            address validator = pendingList[j];
            validatorsStatus[validator] = ValidatorStatus({
                isValidator: true,
                index: j,
                support: initialSupport,
                supported: pendingList,
                benignMisbehaviour: AddressSet.Data({ count: 0 })
            });
        }
        initialized = true;
        validatorsList = pendingList;
        finalized = false;
    }

    // CONSENSUS ENGINE METHODS

    // Called on every block to update node validator list.
    function getValidators() constant returns (address[]) {
        return validatorsList;
    }

    // Log desire to change the current list.
    function initiateChange() private when_finalized {
        finalized = false;
        InitiateChange(block.blockhash(block.number - 1), pendingList);
    }

    function finalizeChange() only_system_and_not_finalized {
        validatorsList = pendingList;
        finalized = true;
        ChangeFinalized(validatorsList);
    }

    // SUPPORT LOOKUP AND MODIFICATION

    // Find the total support for a given address.
    function getSupport(address validator) constant returns (uint) {
        return AddressSet.count(validatorsStatus[validator].support);
    }

    function getSupported(address validator) constant returns (address[]) {
        return validatorsStatus[validator].supported;
    }

    // Vote to include a validator.
    function addSupport(address validator) only_validator not_voted(validator) free_validator_slots {
        newStatus(validator);
        AddressSet.insert(validatorsStatus[validator].support, msg.sender);
        validatorsStatus[msg.sender].supported.push(validator);
        addValidator(validator);
        Support(msg.sender, validator, true);
    }

    // Remove support for a validator.
    function removeSupport(address sender, address validator) private {
        if (!AddressSet.remove(validatorsStatus[validator].support, sender)) { throw; }
        Support(sender, validator, false);
        // Remove validator from the list if there is not enough support.
        removeValidator(validator);
    }

    // MALICIOUS BEHAVIOUR HANDLING

    // Called when a validator should be removed.
    function reportMalicious(address validator, uint blockNumber, bytes proof) only_validator is_recent(blockNumber) {
        removeSupport(msg.sender, validator);
        Report(msg.sender, validator, true);
    }

    // BENIGN MISBEHAVIOUR HANDLING

    // Report that a validator has misbehaved in a benign way.
    function reportBenign(address validator, uint blockNumber) only_validator is_validator(validator) is_recent(blockNumber) {
        firstBenign(validator);
        repeatedBenign(validator);
        Report(msg.sender, validator, false);
    }

    // Find the total number of repeated misbehaviour votes.
    function getRepeatedBenign(address validator) constant returns (uint) {
        return AddressSet.count(validatorsStatus[validator].benignMisbehaviour);
    }

    // Track the first benign misbehaviour.
    function firstBenign(address validator) private has_not_benign_misbehaved(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = now;
    }

    // Report that a validator has been repeatedly misbehaving.
    function repeatedBenign(address validator) private has_repeatedly_benign_misbehaved(validator) {
        AddressSet.insert(validatorsStatus[validator].benignMisbehaviour, msg.sender);
        confirmedRepeatedBenign(validator);
    }

    // When enough long term benign misbehaviour votes have been seen, remove support.
    function confirmedRepeatedBenign(address validator) private agreed_on_repeated_benign(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = 0;
        AddressSet.remove(validatorsStatus[validator].benignMisbehaviour, msg.sender);
        removeSupport(msg.sender, validator);
    }

    // Absolve a validator from a benign misbehaviour.
    function absolveFirstBenign(address validator) has_benign_misbehaved(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = 0;
        AddressSet.remove(validatorsStatus[validator].benignMisbehaviour, msg.sender);
    }

    // PRIVATE UTILITY FUNCTIONS

    // Add a status tracker for unknown validator.
    function newStatus(address validator) private has_no_votes(validator) {
        validatorsStatus[validator] = ValidatorStatus({
            isValidator: false,
            index: pendingList.length,
            support: AddressSet.Data({ count: 0 }),
            supported: new address[](0),
            benignMisbehaviour: AddressSet.Data({ count: 0 })
        });
    }

    // ENACTMENT FUNCTIONS (called when support gets out of line with the validator list)

    // Add the validator if supported by majority.
    // Since the number of validators increases it is possible to some fall below the threshold.
    function addValidator(address validator) is_not_validator(validator) has_high_support(validator) {
        validatorsStatus[validator].index = pendingList.length;
        pendingList.push(validator);
        validatorsStatus[validator].isValidator = true;
        // New validator should support itself.
        AddressSet.insert(validatorsStatus[validator].support, validator);
        validatorsStatus[validator].supported.push(validator);
        initiateChange();
    }

    // Remove a validator without enough support.
    // Can be called to clean low support validators after making the list longer.
    function removeValidator(address validator) is_validator(validator) has_low_support(validator) {
        uint removedIndex = validatorsStatus[validator].index;
        // Can not remove the last validator.
        uint lastIndex = pendingList.length-1;
        address lastValidator = pendingList[lastIndex];
        // Override the removed validator with the last one.
        pendingList[removedIndex] = lastValidator;
        // Update the index of the last validator.
        validatorsStatus[lastValidator].index = removedIndex;
        delete pendingList[lastIndex];
        pendingList.length--;
        // Reset validator status.
        validatorsStatus[validator].index = 0;
        validatorsStatus[validator].isValidator = false;
        // Remove all support given by the removed validator.
        address[] toRemove = validatorsStatus[validator].supported;
        for (uint i = 0; i < toRemove.length; i++) {
            removeSupport(validator, toRemove[i]);
        }
        delete validatorsStatus[validator].supported;
        initiateChange();
    }

    // MODIFIERS

    modifier uninitialized() {
        if (initialized) { throw; }
        _;
    }

    function highSupport(address validator) constant returns (bool) {
        return getSupport(validator) > pendingList.length/2;
    }

    function firstBenignReported(address reporter, address validator) constant returns (uint) {
        return validatorsStatus[validator].firstBenign[reporter];
    }

    modifier has_high_support(address validator) {
        if (highSupport(validator)) { _; }
    }

    modifier has_low_support(address validator) {
        if (!highSupport(validator)) { _; }
    }

    modifier has_not_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) == 0) { _; }
    }

    modifier has_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) > 0) { _; }
    }

    modifier has_repeatedly_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) - now > MAX_INACTIVITY) { _; }
    }

    modifier agreed_on_repeated_benign(address validator) {
        if (getRepeatedBenign(validator) > pendingList.length/2) { _; }
    }

    modifier free_validator_slots() {
        if (pendingList.length >= MAX_VALIDATORS) { throw; }
        _;
    }

    modifier only_validator() {
        if (!validatorsStatus[msg.sender].isValidator) { throw; }
        _;
    }

    modifier is_validator(address someone) {
        if (validatorsStatus[someone].isValidator) { _; }
    }

    modifier is_not_validator(address someone) {
        if (!validatorsStatus[someone].isValidator) { _; }
    }

    modifier not_voted(address validator) {
        if (AddressSet.contains(validatorsStatus[validator].support, msg.sender)) {
            throw;
        }
        _;
    }

    modifier has_no_votes(address validator) {
        if (AddressSet.count(validatorsStatus[validator].support) == 0) { _; }
    }

    modifier is_recent(uint blockNumber) {
        if (block.number > blockNumber + RECENT_BLOCKS) { throw; }
        _;
    }

    modifier only_system_and_not_finalized() {
        if (msg.sender != SYSTEM_ADDRESS || finalized) { throw; }
        _;
    }

    modifier when_finalized() {
        if (!finalized) { throw; }
        _;
    }

    // Fallback function throws when called.
    function() {
        throw;
    }
}

library AddressSet {
    // Tracks the number of votes from different addresses.
    struct Data {
        uint count;
        // Keeps track of who voted, prevents double vote.
        mapping(address => bool) inserted;
    }

    function count(Data storage self) constant returns (uint) {
        return self.count;
    }

    function contains(Data storage self, address voter) returns (bool) {
        return self.inserted[voter];
    }

    function insert(Data storage self, address voter) returns (bool) {
        if (self.inserted[voter]) { return false; }
        self.count++;
        self.inserted[voter] = true;
        return true;
    }

    function remove(Data storage self, address voter) returns (bool) {
        if (!self.inserted[voter]) { return false; }
        self.count--;
        self.inserted[voter] = false;
        return true;
    }
}
'
validators_set_contract="${validators_set_contract/validators_list/$solidity_validators_list}"

echo "$validators_set_contract" > "validators_set_contract.sol"
solcjs --optimize --bin validators_set_contract.sol >/dev/null
validators_set_contract_bin=`cat validators_set_contract_sol_MajorityList.bin`

###############################################################################
### create chain config file ##################################################
###############################################################################
poa_chain_contents='
{
	"name": "POA",
	"dataDir": "POA",
	"engine": {
		"authorityRound": {
			"params": {
			"stepDuration": "4",
			"blockReward": "0x4563918244F40000",
				"validators" : {
					"contract": "0x0000000000000000000000000000000000000006"
				},
				"validateScoreTransition": 1000000,
				"validateStepTransition": 1500000
			}
		}
	},
	"params": {
		"gasLimitBoundDivisor": "0x400",
		"registrar" : "0x0000000000000000000000000000000000000005",
		"maximumExtraDataSize": "0x20",
		"minGasLimit": "0x1388",
		"networkID" : "0x2A",
		"validateReceiptsTransition" : 1000000,
		"eip155Transition": 1000000,
		"validateChainIdTransition": 1000000
	},
	"genesis": {
		"seal": {
			"authorityRound": {
				"step": "0x0",
				"signature": "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
			}
		},
		"difficulty": "0x20000",
		"gasLimit": "0x5B8D80"
	},
	"accounts": {
		"0x0000000000000000000000000000000000000001": { "balance": "1", "builtin": { "name": "ecrecover", "pricing": { "linear": { "base": 3000, "word": 0 } } } },
		"0x0000000000000000000000000000000000000002": { "balance": "1", "builtin": { "name": "sha256", "pricing": { "linear": { "base": 60, "word": 12 } } } },
		"0x0000000000000000000000000000000000000003": { "balance": "1", "builtin": { "name": "ripemd160", "pricing": { "linear": { "base": 600, "word": 120 } } } },
		"0x0000000000000000000000000000000000000004": { "balance": "1", "builtin": { "name": "identity", "pricing": { "linear": { "base": 15, "word": 3 } } } },
		"0x0000000000000000000000000000000000000005": { "balance": "1", "constructor": "0x606060405233600060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff160217905550670de0b6b3a764000060035534610000575b612904806100666000396000f3006060604052361561013c576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806306b2ff471461014157806313af40351461018c57806319362a28146101bf5780633f3935d114610248578063432ced04146102b75780634f39ca59146102eb5780636795dbcd1461032457806369fe0e2d146103c857806379ce9fac146103fd5780638da5cb5b1461045557806390b97fc1146104a457806392698814146105245780639890220b1461055d578063ac4e73f914610584578063ac72c12014610612578063c3a358251461064b578063ddca3f43146106c3578063deb931a2146106e6578063df57b74214610747578063e30bd740146107a8578063eadf976014610862578063ef5454d6146108e7578063f25eb5c114610975578063f6d339e414610984575b610000565b3461000057610172600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610a1f565b604051808215151515815260200191505060405180910390f35b34610000576101bd600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610a81565b005b346100005761022e60048080356000191690602001909190803590602001908201803590602001908080601f0160208091040260200160405190810160405280939291908181526020018383808284378201915050505050509190803560001916906020019091905050610ba2565b604051808215151515815260200191505060405180910390f35b346100005761029d600480803590602001908201803590602001908080601f01602080910402602001604051908101604052809392919081815260200183838082843782019150505050505091905050610dc9565b604051808215151515815260200191505060405180910390f35b6102d1600480803560001916906020019091905050611035565b604051808215151515815260200191505060405180910390f35b346100005761030a60048080356000191690602001909190505061115f565b604051808215151515815260200191505060405180910390f35b346100005761038660048080356000191690602001909190803590602001908201803590602001908080601f01602080910402602001604051908101604052809392919081815260200183838082843782019150505050505091905050611378565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b34610000576103e3600480803590602001909190505061140d565b604051808215151515815260200191505060405180910390f35b346100005761043b60048080356000191690602001909190803573ffffffffffffffffffffffffffffffffffffffff169060200190919050506114b4565b604051808215151515815260200191505060405180910390f35b34610000576104626115fb565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b346100005761050660048080356000191690602001909190803590602001908201803590602001908080601f01602080910402602001604051908101604052809392919081815260200183838082843782019150505050505091905050611621565b60405180826000191660001916815260200191505060405180910390f35b34610000576105436004808035600019169060200190919050506116b2565b604051808215151515815260200191505060405180910390f35b346100005761056a611715565b604051808215151515815260200191505060405180910390f35b34610000576105f8600480803590602001908201803590602001908080601f0160208091040260200160405190810160405280939291908181526020018383808284378201915050505050509190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050611824565b604051808215151515815260200191505060405180910390f35b3461000057610631600480803560001916906020019091905050611d8b565b604051808215151515815260200191505060405180910390f35b34610000576106ad60048080356000191690602001909190803590602001908201803590602001908080601f01602080910402602001604051908101604052809392919081815260200183838082843782019150505050505091905050611dee565b6040518082815260200191505060405180910390f35b34610000576106d0611e83565b6040518082815260200191505060405180910390f35b3461000057610705600480803560001916906020019091905050611e89565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b3461000057610766600480803560001916906020019091905050611ed2565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b34610000576107d9600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050611f1b565b6040518080602001828103825283818151815260200191508051906020019080838360008314610828575b80518252602083111561082857602082019150602081019050602083039250610804565b505050905090810190601f1680156108545780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b34610000576108cd60048080356000191690602001909190803590602001908201803590602001908080601f0160208091040260200160405190810160405280939291908181526020018383808284378201915050505050509190803590602001909190505061200c565b604051808215151515815260200191505060405180910390f35b346100005761095b600480803590602001908201803590602001908080601f0160208091040260200160405190810160405280939291908181526020018383808284378201915050505050509190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050612236565b604051808215151515815260200191505060405180910390f35b3461000057610982612425565b005b3461000057610a0560048080356000191690602001909190803590602001908201803590602001908080601f0160208091040260200160405190810160405280939291908181526020018383808284378201915050505050509190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050612698565b604051808215151515815260200191505060405180910390f35b60006000600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020805460018160011615610100020316600290049050141590505b919050565b600060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16141515610add57610b9f565b8073ffffffffffffffffffffffffffffffffffffffff16600060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff167f70aea8d848e8a90fb7661b227dc522eb6395c3dac71b63cb59edd5c9899b236460405180905060405180910390a380600060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505b5b50565b6000833373ffffffffffffffffffffffffffffffffffffffff1660016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16141515610c1d57610dc1565b82600160008760001916600019168152602001908152602001600020600201856040518082805190602001908083835b60208310610c705780518252602082019150602081019050602083039250610c4d565b6001836020036101000a03801982511681845116808217855250505050505090500191505090815260200160405180910390208160001916905550836040518082805190602001908083835b60208310610cdf5780518252602082019150602081019050602083039250610cbc565b6001836020036101000a038019825116818451168082178552505050505050905001915050604051809103902085600019167fb829c3e412537bbe794c048ccb9e4605bb4aaaa8e4d4c15c1a6e0c2adc1716ea866040518080602001828103825283818151815260200191508051906020019080838360008314610d82575b805182526020831115610d8257602082019150602081019050602083039250610d5e565b505050905090810190601f168015610dae5780820380516001836020036101000a031916815260200191505b509250505060405180910390a3600191505b5b509392505050565b6000813373ffffffffffffffffffffffffffffffffffffffff1660016000836040518082805190602001908083835b60208310610e1b5780518252602082019150602081019050602083039250610df8565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390206000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16141515610ea45761102f565b82600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000209080519060200190828054600181600116156101000203166002900490600052602060002090601f016020900481019282601f10610f2d57805160ff1916838001178555610f5b565b82800160010185558215610f5b579182015b82811115610f5a578251825591602001919060010190610f3f565b5b509050610f8091905b80821115610f7c576000816000905550600101610f64565b5090565b50503373ffffffffffffffffffffffffffffffffffffffff16836040518082805190602001908083835b60208310610fcd5780518252602082019150602081019050602083039250610faa565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390207f098ae8581bb8bd9af1beaf7f2e9f51f31a8e5a8bfada4e303a645d71d9c9192060405180905060405180910390a3600191505b5b50919050565b600081600060016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614151561109b57611159565b6003543410156110aa57611158565b3360016000856000191660001916815260200190815260200160002060000160006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055503373ffffffffffffffffffffffffffffffffffffffff1683600019167f4963513eca575aba66fdcd25f267aae85958fe6fb97e75fa25d783f1a091a22160405180905060405180910390a3600191505b5b5b50919050565b6000813373ffffffffffffffffffffffffffffffffffffffff1660016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff161415156111da57611372565b6002600060016000866000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020805460018160011615610100020316600290046000825580601f1061127c57506112b3565b601f0160209004906000526020600020908101906112b291905b808211156112ae576000816000905550600101611296565b5090565b5b5060016000846000191660001916815260200190815260200160002060006000820160006101000a81549073ffffffffffffffffffffffffffffffffffffffff02191690556001820160006101000a81549073ffffffffffffffffffffffffffffffffffffffff021916905550503373ffffffffffffffffffffffffffffffffffffffff1683600019167fef1961b4d2909dc23643b309bfe5c3e5646842d98c3a58517037ef3871185af360405180905060405180910390a3600191505b5b50919050565b6000600160008460001916600019168152602001908152602001600020600201826040518082805190602001908083835b602083106113cc57805182526020820191506020810190506020830392506113a9565b6001836020036101000a0380198251168184511680821785525050505050509050019150509081526020016040518091039020546001900490505b92915050565b6000600060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614151561146b576114af565b816003819055507f6bbc57480a46553fa4d156ce702beef5f3ad66303b0ed1a5d4cb44966c6584c3826040518082815260200191505060405180910390a1600190505b5b919050565b6000823373ffffffffffffffffffffffffffffffffffffffff1660016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614151561152f576115f4565b8260016000866000191660001916815260200190815260200160002060000160006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1685600019167f7b97c62130aa09acbbcbf7482630e756592496f1759eaf702f469cf64dfb779460405180905060405180910390a4600191505b5b5092915050565b600060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6000600160008460001916600019168152602001908152602001600020600201826040518082805190602001908083835b602083106116755780518252602082019150602081019050602083039250611652565b6001836020036101000a03801982511681845116808217855250505050505090500191505090815260200160405180910390205490505b92915050565b6000600060016000846000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16141590505b919050565b6000600060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614151561177357611821565b7fdef931299fe61d176f949118058530c1f3f539dcb6950b4e372c9b835c33ca073073ffffffffffffffffffffffffffffffffffffffff16316040518082815260200191505060405180910390a13373ffffffffffffffffffffffffffffffffffffffff166108fc3073ffffffffffffffffffffffffffffffffffffffff16319081150290604051809050600060405180830381858888f19350505050151561181b57610000565b600190505b5b90565b60006000836040518082805190602001908083835b6020831061185c5780518252602082019150602081019050602083039250611839565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390203373ffffffffffffffffffffffffffffffffffffffff1660016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614151561190157611d83565b846040518082805190602001908083835b602083106119355780518252602082019150602081019050602083039250611912565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390209150600060016000846000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614158015611ab4575081600019166002600060016000866000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206040518082805460018160011615610100020316600290048015611aa15780601f10611a7f576101008083540402835291820191611aa1565b820191906000526020600020905b815481529060010190602001808311611a8d575b5050915050604051809103902060001916145b15611c79576002600060016000856000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020805460018160011615610100020316600290046000825580601f10611b5b5750611b92565b601f016020900490600052602060002090810190611b9191905b80821115611b8d576000816000905550600101611b75565b5090565b5b5060016000836000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16856040518082805190602001908083835b60208310611c1c5780518252602082019150602081019050602083039250611bf9565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390207f12491ad95fd945e444d88a894ffad3c21959880a4dcd8af99d4ae4ffc71d4abd60405180905060405180910390a35b8360016000846000191660001916815260200190815260200160002060010160006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508373ffffffffffffffffffffffffffffffffffffffff16856040518082805190602001908083835b60208310611d215780518252602082019150602081019050602083039250611cfe565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390207f728435a0031f6a04538fcdd24922a7e06bc7bc945db03e83d22122d1bc5f28df60405180905060405180910390a3600192505b5b505092915050565b6000600060016000846000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16141590505b919050565b6000600160008460001916600019168152602001908152602001600020600201826040518082805190602001908083835b60208310611e425780518252602082019150602081019050602083039250611e1f565b6001836020036101000a0380198251168184511680821785525050505050509050019150509081526020016040518091039020546001900490505b92915050565b60035481565b600060016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1690505b919050565b600060016000836000191660001916815260200190815260200160002060010160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1690505b919050565b6020604051908101604052806000815250600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000208054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015611fff5780601f10611fd457610100808354040283529160200191611fff565b820191906000526020600020905b815481529060010190602001808311611fe257829003601f168201915b505050505090505b919050565b6000833373ffffffffffffffffffffffffffffffffffffffff1660016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff161415156120875761222e565b82600102600160008760001916600019168152602001908152602001600020600201856040518082805190602001908083835b602083106120dd57805182526020820191506020810190506020830392506120ba565b6001836020036101000a03801982511681845116808217855250505050505090500191505090815260200160405180910390208160001916905550836040518082805190602001908083835b6020831061214c5780518252602082019150602081019050602083039250612129565b6001836020036101000a038019825116818451168082178552505050505050905001915050604051809103902085600019167fb829c3e412537bbe794c048ccb9e4605bb4aaaa8e4d4c15c1a6e0c2adc1716ea8660405180806020018281038252838181518152602001915080519060200190808383600083146121ef575b8051825260208311156121ef576020820191506020810190506020830392506121cb565b505050905090810190601f16801561221b5780820380516001836020036101000a031916815260200191505b509250505060405180910390a3600191505b5b509392505050565b6000600060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161415156122945761241f565b82600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000209080519060200190828054600181600116156101000203166002900490600052602060002090601f016020900481019282601f1061231d57805160ff191683800117855561234b565b8280016001018555821561234b579182015b8281111561234a57825182559160200191906001019061232f565b5b50905061237091905b8082111561236c576000816000905550600101612354565b5090565b50508173ffffffffffffffffffffffffffffffffffffffff16836040518082805190602001908083835b602083106123bd578051825260208201915060208101905060208303925061239a565b6001836020036101000a03801982511681845116808217855250505050505090500191505060405180910390207f098ae8581bb8bd9af1beaf7f2e9f51f31a8e5a8bfada4e303a645d71d9c9192060405180905060405180910390a3600190505b5b92915050565b3373ffffffffffffffffffffffffffffffffffffffff16600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060405180828054600181600116156101000203166002900480156124d65780601f106124b45761010080835404028352918201916124d6565b820191906000526020600020905b8154815290600101906020018083116124c2575b505091505060405180910390207f12491ad95fd945e444d88a894ffad3c21959880a4dcd8af99d4ae4ffc71d4abd60405180905060405180910390a360016000600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060405180828054600181600116156101000203166002900480156125b05780601f1061258e5761010080835404028352918201916125b0565b820191906000526020600020905b81548152906001019060200180831161259c575b505091505060405180910390206000191660001916815260200190815260200160002060010160006101000a81549073ffffffffffffffffffffffffffffffffffffffff0219169055600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020805460018160011615610100020316600290046000825580601f1061265d5750612694565b601f01602090049060005260206000209081019061269391905b8082111561268f576000816000905550600101612677565b5090565b5b505b565b6000833373ffffffffffffffffffffffffffffffffffffffff1660016000836000191660001916815260200190815260200160002060000160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16141515612713576128d0565b8273ffffffffffffffffffffffffffffffffffffffff16600102600160008760001916600019168152602001908152602001600020600201856040518082805190602001908083835b6020831061277f578051825260208201915060208101905060208303925061275c565b6001836020036101000a03801982511681845116808217855250505050505090500191505090815260200160405180910390208160001916905550836040518082805190602001908083835b602083106127ee57805182526020820191506020810190506020830392506127cb565b6001836020036101000a038019825116818451168082178552505050505050905001915050604051809103902085600019167fb829c3e412537bbe794c048ccb9e4605bb4aaaa8e4d4c15c1a6e0c2adc1716ea866040518080602001828103825283818151815260200191508051906020019080838360008314612891575b8051825260208311156128915760208201915060208101905060208303925061286d565b505050905090810190601f1680156128bd5780820380516001836020036101000a031916815260200191505b509250505060405180910390a3600191505b5b5093925050505600a165627a7a7230582066b2da4773a0f1d81efe071c66b51c46868a871661efd18c0f629353ff4c1f9b0029" },
		"0x0000000000000000000000000000000000000006": { "balance": "1", "constructor" : "0xvalidators_set_contract_bin" },
		accounts_list
	}
}
'
poa_chain_contents="${poa_chain_contents/accounts_list/$json_acccounts_list}"
poa_chain_contents="${poa_chain_contents/validators_set_contract_bin/$validators_set_contract_bin}"

echo "$poa_chain_contents" > "poa_chain.json"
