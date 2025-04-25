#!/bin/bash

# Set cron job
# nano /etc/crontab
# */5 * * * * root /path/to/cloudflare.sh 'your_auth_token' 'your_zone_id' 'home.example.com'

# Check if required arguments are provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 <auth_token> <zone_identifier> <record_name>"
    echo "Example: $0 'your_auth_token' 'your_zone_id' 'home.example.com'"
    exit 1
fi

# auth_token this is either your global API key, or an API token. If you are using an API token, it must have the permissions "Zone - DNS - Edit" and "Zone - Zone - Read". The Zone resources must be "Include - All zones".
# https://dash.cloudflare.com/profile/api-tokens
auth_token="$1"

# zone_identifier Can be found in the "Overview" tab of your domain
# https://dash.cloudflare.com/zones
zone_identifier="$2"

# DNS record for synchronization
# https://dash.cloudflare.com/dns 
record_name="$3"

# DO NOT CHANGE LINES BELOW

# SCRIPT START
echo -e "Check Initiated"

# Check for current external network IP
ip=$(curl -s4 https://ifconfig.me/ip)
if [[ ! -z "${ip}" ]]; then
  echo -e "  > Fetched current external network IP: ${ip}"
else
  >&2 echo -e "Network error, cannot fetch external network IP."
fi

# The execution of update
if [[ ! -z "${auth_token}" ]]; then
  header_auth_paramheader=( -H '"Authorization: Bearer '${auth_token}'"' )
else
  header_auth_paramheader=( -H '"X-Auth-Email: '${auth_email}'"' -H '"X-Auth-Key: '${auth_key}'"' )
fi

# Seek for the record
seek_current_dns_value_cmd=( curl -s -X GET '"https://api.cloudflare.com/client/v4/zones/'${zone_identifier}'/dns_records?name='${record_name}'&type=A"' "${header_auth_paramheader[@]}" -H '"Content-Type: application/json"' )
record=`eval ${seek_current_dns_value_cmd[@]}`

# Can't do anything without the record
if [[ -z "${record}" ]]; then
  >&2 echo -e "Network error, cannot fetch DNS record."
  exit 1
elif [[ "${record}" == *'"count":0'* ]]; then
  >&2 echo -e "Record does not exist, perhaps create one first?"
  exit 1
fi

# Set the record identifier from result
record_identifier=`echo "${record}" | sed 's/.*"id":"//;s/".*//'`

# Set existing IP address from the fetched record
old_ip=`echo "${record}" | sed 's/.*"content":"//;s/".*//'`
echo -e "  > Fetched current DNS record value   : ${old_ip}"

# Compare if they're the same
if [ "${ip}" == "${old_ip}" ]; then
  echo -e "Update for A record '${record_name} (${record_identifier})' cancelled.\\n  Reason: IP has not changed."
  exit 0
else
  echo -e "  > Different IP addresses detected, synchronizing..."
fi

# The secret sause for executing the update
# json_data_v4="'"'{"id":"'${zone_identifier}'","type":"A","proxied":true,"name":"'${record_name}'","content":"'${ip}'","ttl":120}'"'"
json_data_v4="'"'{"id":"'${zone_identifier}'","type":"A","name":"'${record_name}'","content":"'${ip}'"}'"'"
update_cmd=( curl -s -X PUT '"https://api.cloudflare.com/client/v4/zones/'${zone_identifier}'/dns_records/'${record_identifier}'"' "${header_auth_paramheader[@]}" -H '"Content-Type: application/json"' )

# Execution result
update=`eval ${update_cmd[@]} --data $json_data_v4`

# The moment of truth
case "$update" in
*'"success":true'*)
  echo -e "Update for A record '${record_name} (${record_identifier})' succeeded.\\n  - Old value: ${old_ip}\\n  + New value: ${ip}";;
*)
  >&2 echo -e "Update for A record '${record_name} (${record_identifier})' failed.\\nDUMPING RESULTS:\\n${update}"
  exit 1;;
esac