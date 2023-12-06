import json
import sys
import os
import subprocess
import time

# verifies already-deployed contracts using the foundry broadcast file

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
        print("Usage: python script/verify.py ./broadcast/DeployScript.s.sol/5/run-latest.json")
        sys.exit(1)

    if not verify_env_var("ETHERSCAN_API_KEY"):
        print("Error: ETHERSCAN_API_KEY environment variable not set.")
        sys.exit(1)
    if not verify_env_var("CHAIN_ID"):
        print("Error: CHAIN_ID environment variable not set.")
        sys.exit(1)

    chain_id = os.getenv("CHAIN_ID")
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

            fn_sig_arg = f"contructor({abi_types_str})".strip()
            command = f"cast abi-encode \"{fn_sig_arg}\" {arg_str}".strip()
            res = subprocess.run(command, shell=True, text=True, capture_output=True)
            constructor_args = f"--constructor-args {res.stdout}".strip()

        addr = tx['contractAddress']
        contract_name = tx['contractName']
        command = f"forge verify-contract --chain {chain_id} {constructor_args} {addr} {contract_name}"
        print("\n", "Sending verification for: " + addr)
        res = subprocess.run(command, shell=True, text=True, capture_output=True)
        print("Output: ", "\n", res.stdout, "\n")
        if len(res.stderr) != 0:
            print("Error: ", res.stderr, "\n")
        time.sleep(10)

    print("done")
