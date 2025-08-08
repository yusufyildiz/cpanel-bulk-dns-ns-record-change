# BIND Batch Zone Updater

A powerful shell script designed to find and update BIND (DNS) zone files in batch based on a set of flexible criteria. This tool is ideal for system administrators needing to perform bulk migrations or updates of nameserver records across many domains.

## Features

-   **Targeted Selection**: Finds zone files to modify based on:
    -   A keyword search within the zone file (e.g., `cloudflare`).
    -   The domain's currently resolved A record IP address.
-   **Safe Operations**:
    -   **Dry Run Mode**: A `--dry-run` flag lets you preview all intended changes without modifying any files.
    -   **Automatic Backups**: Creates a timestamped `.bak` file for every zone before it's edited.
    -   **Syntax Validation**: Uses `named-checkzone` to verify the syntax of each modified file before committing.
    -   **Atomic Reload**: Reloads BIND using `rndc reload` only after all checks have passed.
-   **Intelligent SOA Updates**: Automatically increments the SOA serial number using the `YYYYMMDDNN` format, ensuring changes are propagated to secondary DNS servers.
-   **Direct Replacement**: Uses `sed` to perform direct, in-place replacement of nameserver hostnames, preserving zone file formatting.

## Configuration

All user-configurable parameters are located at the top of the `update_zones.sh` script. You must edit these variables to match your environment and needs before running.

-   `ZONE_DIR`: The directory where your BIND zone files are stored (e.g., `/var/named`).
-   `SEARCH_PATTERN`: A keyword to find in zones you want to target.
-   `TARGET_IP1`, `TARGET_IP2`: The IP addresses to filter domains by.
-   `OLD_NS1`, `NEW_NS1`, etc.: The nameserver records to be found and replaced.

## Usage

**1. Make the script executable:**

```sh
chmod +x update_zones.sh
```

**2. Perform a Dry Run (Highly Recommended):**

Run the script with the `--dry-run` or `-d` flag to see which files would be changed and what modifications would be made. **No files will be altered.**

```sh
sudo ./update_zones.sh --dry-run
```

**3. Execute the Live Run:**

After verifying the output of the dry run and **ensuring you have a complete backup of your BIND data**, run the script without any flags to apply the changes.

```sh
sudo ./update_zones.sh
```

The script will ask for final confirmation before proceeding with the live run.

## Disclaimer

This is a powerful script that makes direct changes to your DNS configuration. The author is not responsible for any data loss or service disruption. **Always back up your data and test thoroughly with `--dry-run` before use.**
