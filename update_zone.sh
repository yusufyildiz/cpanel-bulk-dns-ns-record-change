#!/bin/bash

######################################################################
# CAUTION! THIS SCRIPT AUTOMATICALLY MODIFIES BIND ZONE FILES.
# ALWAYS TEST WITH --dry-run FIRST.
# ALWAYS BACK UP YOUR ZONE FILE DIRECTORY BEFORE RUNNING IN LIVE MODE.
# USE AT YOUR OWN RISK.
######################################################################

# --- CONFIGURATION ---
ZONE_DIR="/var/named"
SEARCH_PATTERN="cloudflare"
TARGET_IP1="85.95.243.11"
TARGET_IP2="85.95.243.47"

# NS records to be replaced
OLD_NS1="zara.ns.cloudflare.com"
NEW_NS1="ns1.2727836.com"

OLD_NS2="clay.ns.cloudflare.com"
NEW_NS2="ns2.2727836.com"

# --- SCRIPT LOGIC ---
# Mode control variable (0 = Live Run, 1 = Dry Run)
DRY_RUN=0
if [[ "$1" == "--dry-run" || "$1" == "-d" ]]; then
    DRY_RUN=1
    echo "#############################################"
    echo "#         DRY RUN MODE ENABLED          #"
    echo "#      No files will be modified.       #"
    echo "#############################################"
fi

# Counter for modified files
changed_files_count=0
MODIFIED_ZONES=()

# --- SAFETY CHECKS ---
# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root."
   exit 1
fi

# Check for required command dependencies
for cmd in dig sed grep basename named-checkzone rndc; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found. Is 'bind-utils' installed?"
        exit 1
    fi
done

# --- MAIN OPERATION ---
echo "------------------------------------------------------------------"
echo "Starting operation: Searching for target domains..."

TARGET_FILES=$(
    for zone_file in $(find "$ZONE_DIR" -type f -name "*.db" -exec grep -l "$SEARCH_PATTERN" {} +); do
        domain_name=$(basename "$zone_file" .db)
        resolved_ip=$(dig +short "$domain_name" A | head -n 1)
        if [[ "$resolved_ip" == "$TARGET_IP1" || "$resolved_ip" == "$TARGET_IP2" ]]; then
            echo "$zone_file"
        fi
    done
)

if [[ -z "$TARGET_FILES" ]]; then
    echo "No zone files matching the specified criteria were found."
    exit 0
fi

echo "The following files have been targeted for modification:"
echo "$TARGET_FILES"
echo "------------------------------------------------------------------"

if [ "$DRY_RUN" -eq 0 ]; then
    echo "WARNING! The script will run in live mode and make permanent changes."
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

for zone_file in $TARGET_FILES; do
    domain_name=$(basename "$zone_file" .db)
    echo "=> Processing: $domain_name ($zone_file)"

    # --- Get and calculate SOA Serial ---
    current_serial=$(grep -E '\sIN\s+SOA\s' "$zone_file" | awk '{print $7}')
    today_serial_part=$(date +%Y%m%d)
    
    if [[ "${current_serial:0:8}" == "$today_serial_part" ]]; then
        # If serial is from today, increment the counter (NN)
        counter=$(printf "%02d" $(( 10#${current_serial:8:2} + 1 )) )
        new_serial="${today_serial_part}${counter}"
    else
        # If serial is from a previous day, start with today's date and 01
        new_serial="${today_serial_part}01"
    fi
    
    if [ "$DRY_RUN" -eq 1 ]; then
        # DRY RUN MODE: Only show what would be done
        echo "   [DRY RUN] Would create backup file: $zone_file.bak_$(date +%F)"
        echo "   [DRY RUN] Would update SOA Serial: $current_serial -> $new_serial"
        echo "   [DRY RUN] Would replace NS record: $OLD_NS1 -> $NEW_NS1"
        echo "   [DRY RUN] Would replace NS record: $OLD_NS2 -> $NEW_NS2"
        echo "   [DRY RUN] Would perform zone syntax check."
    else
        # LIVE RUN MODE: Apply the changes
        backup_file="${zone_file}.bak_$(date +%Y-%m-%d_%H%M%S)"
        echo "   1. Creating backup -> $backup_file"
        cp "$zone_file" "$backup_file"

        echo "   2. Updating SOA Serial: $current_serial -> $new_serial"
        sed -i "s/$current_serial/$new_serial/" "$zone_file"

        echo "   3. Replacing NS records..."
        # Use -e for multiple commands. Escape dots in the search pattern for literal matching.
        sed -i -e "s/${OLD_NS1//./\\.}/${NEW_NS1}/g" -e "s/${OLD_NS2//./\\.}/${NEW_NS2}/g" "$zone_file"
        
        echo "   4. Checking zone syntax..."
        if ! named-checkzone "$domain_name" "$zone_file" > /dev/null; then
            echo "   ERROR: Syntax check failed for $domain_name! Reverting changes from backup."
            mv "$backup_file" "$zone_file" # Revert on failure
            continue # Skip to the next file
        fi
    fi

    echo "   => Operation planned/completed for $domain_name."
    ((changed_files_count++))
    MODIFIED_ZONES+=("$domain_name")
done

echo "------------------------------------------------------------------"

# --- FINAL REPORT ---
if [ "$changed_files_count" -gt 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY RUN finished."
        echo "$changed_files_count zone file(s) would be modified."
        echo "Target domains: ${MODIFIED_ZONES[*]}"
        echo "No files were changed and BIND was not reloaded."
    else
        echo "$changed_files_count zone file(s) updated successfully."
        echo "Modified domains: ${MODIFIED_ZONES[*]}"
        echo "Sending reload command to BIND..."
        
        if rndc reload; then
            echo "BIND reloaded successfully."
        else
            echo "ERROR: BIND reload failed. Please check logs (e.g., 'journalctl -u named')."
        fi
    fi
else
    echo "No files were modified / nothing to do."
fi

echo "Operation complete."
