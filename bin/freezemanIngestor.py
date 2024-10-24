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

def execute(base_url,
            user,
            password,
            filepath,
            proxy = False,
            cert = False, # Certificate CA_BUNDLE location
            ):
    """
    JSON submission for Freezeman to ingest the run processing report.
    """
    # Set up proxies to access internet : uncomment the 2 following lines to
    # run the script from inside the center.
    #os.environ["http_proxy"] = "http://192.168.32.1:3128"
    #os.environ["https_proxy"] = "http://192.168.32.1:3128"
    if proxy:
        os.environ["http_proxy"] = proxy
        os.environ["https_proxy"] = proxy
    else:
        os.environ["http_proxy"] = ""
        os.environ["https_proxy"] = ""
    # Get jwt token
    print("".join(["Requesting authorization @ ",
                   base_url,
                   AUTH_TOKEN_ENDPOINT,
                   "..."]))
    auth = requests.post("".join([base_url, AUTH_TOKEN_ENDPOINT]),
                         data = {"username": user,
                                 "password": password},
                         verify = cert)
    print("Requesting authorization passed: Status", auth.status_code)
    if auth.status_code == 200:
        access_token = auth.json()["access"]
        headers = {"Authorization": " ".join(["Bearer", access_token])}
        print(headers)

        # Extract json from file
        for iterfile in filepath:
            with open(iterfile, 'r') as inputfile:
                data = inputfile.read()
            data = json.loads(data)

            print("Submitting json file to Freezeman", iterfile)
            response = requests.post(args.url + DATASETS_ENDPOINT,
                                     json = data,
                                     headers = headers,
                                     verify = cert)

            if response.status_code == 200:
                print("Receiving data...")
                try:
                    print(response.content.decode('utf-8'))
                except Exception as e:
                    print("Failed writing result file : ", str(e.message))
                    raise e

                print("Operation complete!")
            else:
                print("Failed call to Freezeman API : ",
                      str(response.status_code),
                      "\n", response.text)
                sys.exit(1)
    else:
        print("Failed to authenticate...", file = sys.stderr)
        print(auth.text)
        sys.exit(1)

if __name__ == '__main__':
    # Get parameters from command line
    parser = argparse.ArgumentParser()
    parser.add_argument("--url",
                        default = "https://f5kvm-biobank-qc.genome.mcgill.ca/api/",
                        help = "Freezeman API base url")
    parser.add_argument("--proxy",
                        default= False,
                        help = "Local proxy when needed")
    parser.add_argument("-c", "--certificate",
                        metavar = "CERT",
                        default = False, #"../assets/ca-bundle.pem",
                        help = "Freezeman certificate")
    parser.add_argument("-u", "--user", help="Freezeman User")
    parser.add_argument("-p", "--password",
                        metavar = "PWD",
                        help = "Password (CAUTION plain text, omit and use \
                        --user alone for secure prompt)")
    parser.add_argument("filepath",
                        nargs='+',
                        metavar = "JSON",
                        help = "Run Processing json file path")
    args = parser.parse_args()
    # Passwd can be prompted instead of supplied as plain text
    if args.user != None and args.password == None:
        args.password = getpass()

    execute(args.url,
            args.user,
            args.password,
            args.filepath,
            args.proxy,
            args.certificate,
            )
