import json
import sys
import os
import subprocess
import time

# verifies already-deployed contracts using the foundry broadcast file and the output of gen_deploy.py


def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8') as file:
            return json.load(file)
    except FileNotFoundError:
        print(f'Error reading the file: {path} does not exist')
    except json.JSONDecodeError as e:
        print(f'Error decoding JSON: {e}')
    except Exception as e:
        print(f'An unexpected error occurred: {e}')

def verify_env_var(var_name):
    return os.environ.get(var_name) is not None

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python ./broadcast/DeployScript.s.sol/5/run-latest.json")
        sys.exit(1)

    if not verify_env_var("ETHERSCAN_API_KEY"):
        print("Error: ETHERSCAN_API_KEY environment variable not set.")
        sys.exit(1)
    if not verify_env_var("CHAIN_ID"):
        print("Error: CHAIN_ID environment variable not set.")
        sys.exit(1)

    broadcast_file = read_file(sys.argv[1])
    

    for tx in broadcast_file['transactions']:
        constructor_args = "" 
        if tx["transactionType"] != "CREATE":
            continue 

        if tx["arguments"] != None:
            contract_name = tx["contractName"]
            f = read_file(f"out/{contract_name}.sol/{contract_name}.json")

            abi_types = []
            
            for item in f["abi"][0]["inputs"]:
                abi_types.append(item["type"])
            
            abi_types_str = ','.join(abi_types)
            
            arg_str = ""
            for arg in tx["arguments"]:
                arg_str += f"{arg} "

            fn_sig_arg = f"contructor({abi_types_str})"
            command = f"cast abi-encode \"{fn_sig_arg}\" {arg_str}"
            res = subprocess.run(command, shell=True, text=True, capture_output=True)
            constructor_args = f"--constructor-args {res.stdout}"

        addr = tx['contractAddress']
        contract_name = tx['contractName']
        command = f"forge verify-contract --chain-id $CHAIN_ID {constructor_args} {addr} {contract_name}"
        print("sent verification for " + addr)
        res = subprocess.run(command, shell=True, text=True, capture_output=True)
        print(res.stdout)
        time.sleep(5)

    print("done")
