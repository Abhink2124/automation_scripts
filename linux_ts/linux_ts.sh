#!/bin/bash

# Define the file where the status report will be saved
output_file="pod_status_report.txt"
primary_log_file="/opt/cisco/tetration/log"
secondary_log_file="/usr/local/tet/log"

check_registration() {
    local log_file_name="csw-update.log"
    local log_files=("$primary_log_file/$log_file_name" "$secondary_log_file/$log_file_name")
    local search_string="register_sensor"
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            echo "Checking logs in $log_file..."
            last_entry=$(grep "$search_string" "$log_file" | tail -n 1)
            if [[ -n "$last_entry" ]]; then
                echo "Last log entry: $last_entry"
                if echo "$last_entry" | grep -qE "(200|201|302)"; then
                    echo "Agent registered successfully"
                    return 0
                elif echo "$last_entry" | grep -q "401"; then
                    echo "Agent Registration Failed. Reason:'Activation Key is missing/incorrect. Please ensure Activation Key is correctly entered in user.cfg file"
                    return 1
                elif echo "$last_entry" | grep -q "403"; then
                    echo " Error 403-Agent seems to be deleted from Cluster UI"
                    return 1
                else
                    echo "Known registration issue not found. Last entry: $last_entry"
                    return 1
                fi
            else
                echo "$search_string not found in $log_file."
                return 1
            fi
        else
            echo "Log file $log_file not found"
        fi
    done
    echo "Log files not found"
    return 2    
}


check_enforcement_status() {
	log_file_name="tet-enforcer.log"
    local log_files=("$primary_log_file/$log_file_name" "$secondary_log_file/$log_file_name")
    local search_string="Enforcement enabled"

    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            echo "Checking enforcement status"
            enf_enabled=$(grep "$search_string" "$log_file" | tail -n 1)
            if [[ -n "$enf_enabled" ]]; then
                if echo "$enf_enabled" | grep -q "enabled:1"; then
                    echo "Enforcement is enabled."
                    return 0
                else
                    echo "Enforcement is Disabled."
                    return 1
                fi
            else
                echo "$search_string not found in $log_file."
            fi
        else
            echo "Log file $log_file not found"
        fi
    done

    echo "No log files found for enforcement check."
    return 2
}

check_golden_rule() {
	linux_nodes=$(kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage | grep -i "linux" | awk '{print $1}')
	pod_list=$(kubectl get pods -n tetration -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName | grep "tetration-agent" | grep -v "tetration-agent-win" | grep -E "$(echo $linux_nodes | tr ' ' '|')" | awk '{print $1}')
	for pod in $pod_list; do

		  kubectl exec -n tetration $pod -- iptables -L TA_GOLDEN_OUTPUT &> /dev/null
                  if [ $? -ne 0 ]; then
                     echo "CSW Golden rules chain doesn't exist"
                     return 1
                  fi

                  kubectl exec -n tetration $pod -- iptables -L TA_GOLDEN_OUTPUT -v | grep -q "match-set ta_"
		  if [ $? -eq 0 ]; then
                     echo "CSW Golden rules exist"
                     return 0
                  else
                     echo "CSW Golden rules have not been programmed"
                     return 1
                  fi
	done
}

check_registration
check_enforcement_status
check_golden_rule
