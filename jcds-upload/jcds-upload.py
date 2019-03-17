#!/usr/bin/python

'''
JCDS package upload script
    by G Pugh

Developed from an idea posted at
    https://www.jamf.com/jamf-nation/discussions/27869#responseChild166021

Usage:
    ./jcds_upload.py /path/to/package.pkg
'''


import sys
import os
import json
from base64 import b64encode
from xml.dom import minidom
import requests


# variables
jamf_url = "https://YOURJAMFCLOUDURL"
credentials = "YOURJAMFUSERNAME:YOURPJAMFASSWORD"

def check_pkg(filename, jamf_url, enc_creds):
    '''check if a package with the same name exists in the repo
    note that it is possible to have more than one with the same name
    which could mess things up'''
    headers = {
        'authorization': "Basic {}".format(enc_creds),
        'accept': "application/json",
    }
    url = "{}/JSSResource/packages/name/{}".format(jamf_url, filename)
    r = requests.get(url, headers=headers)
    if r.status_code == 200:
        obj = json.loads(r.text)
        try:
            obj_id = str(obj['package']['id'])
            print 'Existing ID found: {}'.format(obj_id)
        except KeyError:
            obj_id = '-1'
        return obj_id
    else:
        obj_id = '-1'
        return obj_id


def post_pkg(filename, jamf_url, enc_creds):
    '''sends the package'''
    # check for existing
    obj_id = check_pkg(filename, jamf_url, enc_creds)

    files = {
        'file': open(filepath, 'rb')
    }
    headers = {
        'authorization': "Basic {}".format(enc_creds),
        'content-type': "application/xml",
        'DESTINATION': '0',
        'OBJECT_ID': obj_id,
        'FILE_TYPE': '0',
        'FILE_NAME': filename
    }
    url = "{}/dbfileupload".format(jamf_url)
    r = requests.post(url, files=files, headers=headers)
    return r


# input for filepath
filepath = sys.argv[1]

# base64 encode the crednetials
enc_creds = b64encode(credentials)

# post the package
filename = os.path.basename(filepath)
post_pkg(filename, jamf_url, enc_creds)

# print various outputs from the request
print '\nHTTP Response Code: {}'.format(r.status_code)
print '\nHeaders:\n'
print(r.headers)
print '\nResponse:\n'
xml = minidom.parseString(r.text)
pretty_xml = xml.toprettyxml()
print pretty_xml
