#/usr/bin/env python

# Call to Freezeman API to ingest the Run Processing JSON report

import argparse
import subprocess
import os
import requests
import json
import sys
from getpass import getpass

AUTH_TOKEN_ENDPOINT = "token/"
DATASETS_ENDPOINT = "datasets/add_run_processing/"

def execute(fms_base_url, fms_user, fms_password, filepath):
    # Set up proxies to access internet : uncomment the 2 following lines to run the script from inside the center.
    #os.environ["http_proxy"] = "http://192.168.32.1:3128"
    #os.environ["https_proxy"] = "http://192.168.32.1:3128"
    
    # Setup Certificate CA_BUNDLE location
    PATH_TO_CERT = "./ca-bundle.pem"

    # Get jwt token
    print("Requesting authorization...")
    auth = requests.post(fms_base_url + AUTH_TOKEN_ENDPOINT, data={"username": fms_user, "password": fms_password}, verify=PATH_TO_CERT)
    if auth.status_code == 200:
        access_token = auth.json()["access"]
        headers = {"Authorization": "Bearer " + access_token}

        # Extract json from file
        with open(filepath, 'r') as inputfile:
            data = inputfile.read()
        data = json.loads(data)
        
        print("Submitting the json file to Freezeman")
        response = requests.post(args.url + DATASETS_ENDPOINT, json=data, headers=headers, verify=PATH_TO_CERT)

        if response.status_code == 200:
            print("Receiving data...")
            try:
                print(response.content.decode('utf-8'))
            except Exception as e:
                print("Failed writing result file : " + str(e.message))

            print("Operation complete!")
        else:
            print("Failed call to Freezeman API : " + str(response.status_code) + " (" + response.text + ")")
    else:
        print("Failed to authenticate...", file=sys.stderr)
        print(auth.text)

if __name__ == '__main__':
    # Get parameters from command line
    parser = argparse.ArgumentParser()
    parser.add_argument("--url",
                        default="http://f5kvm-biobank-qc.genome.mcgill.ca/api/",
                        help="Freezeman QC API base url")
    parser.add_argument("-u", "--user", help="Freezeman User")
    parser.add_argument("-p", "--password",
                        metavar = "PWD",
                        help = "Freezeman Password (Caution plain text, use \
                        --user alone for secure prompt)")
    parser.add_argument("filepath",
                        metavar = "JSON",
                        help = "Run Processing json file path")
    args = parser.parse_args()
    # Passwd can be prompted instead of supplied as plain text
    if args.user != None and args.password == None:
        args.password = getpass()

    execute(args.url, args.user, args.password, args.filepath)
