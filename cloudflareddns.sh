#!/bin/bash
set -e;

# DSM Config
username="$1" # Zone ID
password="$2" # API Token
hostname="$3" # www.example.com
ipAddr="$4"   # IPv4 Address

# Cloudflare API-Calls for listing entries
listDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=A&name=${hostname}"

res=$(curl -s -X GET "$listDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $resSuccess != "true" ]]; then
    echo "badparam";
    exit 1;
fi

recordId=$(echo "$res" | jq -r ".result[0].id")
recordIp=$(echo "$res" | jq -r ".result[0].content")
recordProx=$(echo "$res" | jq -r ".result[0].proxied")

# API-Calls for creating DNS-Entries
createDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records"

# API-Calls for update DNS-Entries
updateDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordId}" # for IPv4 or if provided IPv6

if [[ $recordIp = "$ipAddr" ]]; then
    echo "nochg";
    exit 0;
fi

if [[ $recordId = "null" ]]; then
    # Record not exists, create it
    res=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":false}")
else
    # Record exists, overwrite it
    res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$recordProx}")
fi
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $resSuccess = "true" ]]; then
    echo "good";
	exit 0;
else
    echo "badparam";
	exit 1;
fi
