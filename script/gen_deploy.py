import json
import sys
import os

# rewrites foundry's broadcast files to be more succinct and readable 
def parse(data):
    broadcast_json = json.loads(data)
    output = {}

    permission_list_address = None
    us_tb_address = None

    # find addresses so we know which proxy is which
    for tx in broadcast_json['transactions']:
        if tx['transactionType'] == "CREATE":
            if tx['contractName'] == "AllowList":
                permission_list_address = tx['contractAddress']
            if tx['contractName'] == "USTB":
                us_tb_address = tx['contractAddress']

    for tx in broadcast_json['transactions']:
        # only look for txs that deploy the contract 
        if tx['transactionType'] == "CREATE":
            # if its a proxy, name it based on which contract it proxies and based on deployment arg
            if tx['contractName'] == "TransparentUpgradeableProxy":
                if tx['arguments'][0] == permission_list_address:
                    contract_name = "AllowListProxy"
                elif tx['arguments'][0] == us_tb_address:
                    contract_name = "USTBProxy"
                else:
                    raise ValueError("Unknown proxy address")
            else:
                contract_name = tx['contractName']

            # block numbers are stored in receipts. match them up 
            for receipt in broadcast_json['receipts']:
                if receipt['transactionHash'] == tx['hash']:
                    # store human readable contract name and original contract name
                    output[contract_name] = {
                        'transactionHash': tx['hash'],
                        'address': tx['contractAddress'],
                        'deployBlock': int(receipt['blockNumber'], 16),
                        'contractName': tx['contractName']
                    }
    
    output["chain_id"] = broadcast_json["chain"]
    return output

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script/gen_deploy.py input_file.json output_file.json")
        print("eg: python script/gen_deploy.py broadcast/DeployScript.s.sol/11155111/run-latest.json sepolia.json")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    try:
        with open(input_file, 'r', encoding='utf-8') as file:
            data = file.read()
            output = parse(data)

    except FileNotFoundError:
        print(f'Error reading the file: {input_file} does not exist')
    except json.JSONDecodeError as e:
        print(f'Error decoding JSON: {e}')
    except Exception as e:
        print(f'An unexpected error occurred: {e}')

    dir_path = "contract_deployment"
    if not os.path.exists(dir_path):
        os.makedirs(dir_path)

    file_path = os.path.join(dir_path, output_file)

    try:
        with open(file_path, 'w') as f:
            json.dump(output, f, indent=4)
            print("sucess: wrote to file: ", file_path)
    except Exception as e:
        print(f"An unexpected error occurred: {str(e)}")

