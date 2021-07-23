#!/bin/bash

if [[ ! -d .virtualbmc ]]; then
    virtualenv -ppython3 .virtualbmc
fi

source .virtualbmc/bin/activate
pip install virtualbmc
vbmcd
vbmc add baremetal1 --port 6230
vbmc start baremetal1

echo -e "\nTo interact with vbmc:"
echo "source $(pwd)/.virtualbmc/bin/activate"
echo "vbmc list"
