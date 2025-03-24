
#!/bin/bash
# ==============================
# :small_blue_diamond: CONFIGURATION SECTION
# ==============================
# Prompt for Slack Workflow Webhook URL
read -p "Enter Slack Webhook URL: " SLACK_WEBHOOK_URL
# Prompt for Box API Credentials
read -p "Enter Box Access Token: " ACCESS_TOKEN
read -p "Enter Box Folder ID: " BOX_FOLDER_ID
# Prompt for username
read -p "Enter your username: " username
# Prompt for the desired kernel version
read -p "Enter the desired kernel version (e.g., 5.4.0-91-generic): " desired_kernel_version
# Get current date details
current_month=$(date +%b)
current_year=$(date +%Y)
# Define the output file
filename="${current_month}${current_year}datalog.csv"
# Add CSV header
echo "Hostname,IP_Address,Date,Kernel_Version,Installed_Packages,Uptime" > "$filename"
# Initialize arrays for servers
latest_kernels=()
outdated_kernels=()
# ==============================
# :small_blue_diamond: LOOP THROUGH SERVERS
# ==============================
for server in $(cat servers.txt); do
    echo "Collecting data from $server..."
    # Get Kernel Version
    ssh_output=$(ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$root@$server" "uname -r" 2>&1)
    if [ $? -ne 0 ]; then
        echo ":x: Failed to connect to $server"
        continue
    fi
    ssh_output1=$(ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$username@$server" \
    "hostname; ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+'; date; uname -r; uptime -p; echo '---END_UPTIME---'; rpm -qa --last | grep -i '$current_month $current_year'" 2>&1)
    kernel_version=$(echo "$ssh_output")
    # Compare kernel version
    if [[ "$kernel_version" == "$desired_kernel_version" ]]; then
        latest_kernels+=("$server")
    else
        outdated_kernels+=("$server")
    fi
    # Extract server details
    hostname=$(echo "$ssh_output1" | sed -n '1p')
    ip_address=$(echo "$ssh_output1" | sed -n '2p')
    server_date=$(echo "$ssh_output1" | sed -n '3p')
    kernel_version=$(echo "$ssh_output1" | sed -n '4p')
    uptime=$(echo "$ssh_output1" | sed -n '5,/---END_UPTIME---/p' | head -n -1 | tr '\n' ' ' | sed 's/ $//')
    installed_packages=$(echo "$ssh_output1" | sed -n '/---END_UPTIME---/,$p' | sed '1d' | tr '\n' '; ' | sed 's/; $//')
    # Append to CSV (IP address moved after Hostname)
    echo "$hostname,$ip_address,$server_date,$kernel_version,\"$installed_packages\",\"$uptime\"" >> "$filename"
done
# Handle empty arrays
if [ ${#latest_kernels[@]} -eq 0 ]; then
    latest_kernels=("None")
fi
if [ ${#outdated_kernels[@]} -eq 0 ]; then
    outdated_kernels=("None")
fi
# ==============================
# :small_blue_diamond: FORMAT SLACK WORKFLOW MESSAGE (JSON)
# ==============================
json_payload=$(jq -n \
    --arg latest_kernels "$(IFS=$'\n'; echo "${latest_kernels[*]}")" \
    --arg outdated_kernels "$(IFS=$'\n'; echo "${outdated_kernels[*]}")" \
    --arg desired_kernel_version "$desired_kernel_version" \
    '{ "message": ("*Kernel Update Report:*\n\n:white_check_mark: *Servers with Latest Kernel (" + $desired_kernel_version + "):*\n```" + $latest_kernels + "```\n\n:warning: *Servers Without Latest Kernel:*\n```" + $outdated_kernels + "```") }')
# Debug JSON payload
echo "JSON Payload: $json_payload"
# ==============================
# :small_blue_diamond: SEND TO SLACK WORKFLOW WEBHOOK
# ==============================
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    response=$(curl -s -X POST -H 'Content-type: application/json' --data "$json_payload" "$SLACK_WEBHOOK_URL")
    echo "Slack Response: $response"
    echo ":white_check_mark: Message sent to Slack Workflow."
else
    echo ":x: Error: No Slack Webhook URL provided!"
    exit 1
fi
# ==============================
# :small_blue_diamond: UPLOAD CSV TO BOX
# ==============================
# Upload CSV to Box
curl -X POST "https://upload.box.com/api/2.0/files/content" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: multipart/form-data" \
    -F "attributes={\"name\":\"$filename\", \"parent\":{\"id\":\"$BOX_FOLDER_ID\"}};type=application/json" \
    -F "file=@$filename"
echo ":white_check_mark: CSV file uploaded to Box."
echo ":white_check_mark: Report completed!" 
