# ZFS Transaction Management - Quick Reference

## Emergency Recovery

### Power Loss / Script Crash Recovery
```bash
# Automatic recovery (run this first)
./zfs-auto-datasets-ubuntu.sh

# OR manual recovery
./manual-recovery.sh recover
```

### List Pending Transactions
```bash
./manual-recovery.sh list
```

### Show Transaction Details
```bash
./manual-recovery.sh show <transaction_id>
```

### Rollback Specific Transaction
```bash
./manual-recovery.sh rollback <transaction_id>
```

## Transaction States

| State | What It Means | What To Do |
|-------|---------------|------------|
| INITIATED | Just started, no changes | Safe to rollback or continue |
| RENAMED | Directory renamed to _temp | Rollback restores original |
| DATASET_CREATED | Dataset created, no data | Rollback destroys dataset |
| RSYNC_STARTED | Copying data | Rollback destroys dataset |
| RSYNC_COMPLETE | Data copied, not validated | Rollback destroys dataset |
| VALIDATED | Data verified, temp exists | Forward recovery (safe) |
| COMPLETED | All done | No action needed |
| FAILED | Error occurred | Review and rollback |

## Manual Recovery Procedures

### Scenario 1: Power Loss During Conversion
```bash
# 1. List pending transactions
./manual-recovery.sh list

# 2. Check filesystem
ls -la /mnt/tank/data/

# 3. Recover automatically
./manual-recovery.sh recover
```

### Scenario 2: Stuck Transaction
```bash
# 1. Show details
./manual-recovery.sh show tx_XXXXX

# 2. Check what exists
ls -la <source_path>
ls -la <temp_path>
zfs list | grep <dataset_name>

# 3. Rollback
./manual-recovery.sh rollback tx_XXXXX
```

### Scenario 3: Multiple Failures
```bash
# Recover all at once
./manual-recovery.sh recover
```

## Common Commands

### Check Status
```bash
# List all pending
./manual-recovery.sh list

# Count pending
./manual-recovery.sh list | grep -c "tx_"
```

### Cleanup Old Transactions
```bash
# Cleanup > 30 days (default)
./manual-recovery.sh cleanup

# Cleanup > 7 days
./manual-recovery.sh cleanup 7
```

### Interactive Mode
```bash
# Full menu interface
./manual-recovery.sh
```

## State File Locations

```bash
# Transaction state files
/var/lib/zfs-scripts/transactions/

# Lock files
/var/run/zfs-scripts/locks/

# View all transactions
ls -lh /var/lib/zfs-scripts/transactions/

# View a transaction
cat /var/lib/zfs-scripts/transactions/tx_XXXXX.json

# View with jq (if installed)
jq . /var/lib/zfs-scripts/transactions/tx_XXXXX.json
```

## Logs

```bash
# Main log
tail -f /var/log/zfs-scripts.log

# Filter for transactions
grep "Transaction" /var/log/zfs-scripts.log

# Today's transactions
grep "Transaction" /var/log/zfs-scripts.log | grep "$(date +%Y-%m-%d)"
```

## What NOT To Do

❌ Don't delete state files manually (use cleanup command)
❌ Don't delete _temp directories manually (use rollback)
❌ Don't destroy datasets without checking transactions
❌ Don't remove lock files if script is running

## Safe Operations

✅ Always list transactions first
✅ Check filesystem before rollback
✅ Use show command to see details
✅ Let automatic recovery run first
✅ Use interactive mode if unsure

## Troubleshooting

### Problem: Transaction Won't Rollback
```bash
# Check if locked
ls -l /var/run/zfs-scripts/locks/tx_XXXXX.lock

# Check PID in lock
cat /var/run/zfs-scripts/locks/tx_XXXXX.lock

# If process dead, remove lock
rm /var/run/zfs-scripts/locks/tx_XXXXX.lock

# Try rollback again
./manual-recovery.sh rollback tx_XXXXX
```

### Problem: Corrupted State File
```bash
# Backup corrupted file
cp /var/lib/zfs-scripts/transactions/tx_XXXXX.json \
   /root/backup-tx_XXXXX.json

# Manually check filesystem
ls -la <paths from transaction>

# Manual recovery based on what exists
# See lib/TRANSACTIONS.md for full procedures
```

### Problem: No Space Left
```bash
# Cleanup old transactions
./manual-recovery.sh cleanup 7

# Check disk space
df -h /var/lib/zfs-scripts/transactions/
```

## Cron Jobs

### Daily Cleanup
```bash
# Add to crontab
0 2 * * * /path/to/manual-recovery.sh cleanup 30 2>&1 | logger -t zfs-tx-cleanup
```

### Weekly Health Check
```bash
# Add to crontab
0 3 * * 1 /path/to/manual-recovery.sh list 2>&1 | logger -t zfs-tx-check
```

## Decision Tree

```
Power loss or crash?
├─ Yes → Run automatic recovery
│         ./zfs-auto-datasets-ubuntu.sh
│         OR ./manual-recovery.sh recover
│
└─ No → Transaction stuck?
          ├─ Yes → Show details
          │         ./manual-recovery.sh show tx_XXXXX
          │         Check filesystem
          │         Rollback if needed
          │
          └─ No → Just checking status?
                    ./manual-recovery.sh list
```

## Support

### Get Help
```bash
# Help message
./manual-recovery.sh help

# Read documentation
less lib/TRANSACTIONS.md

# View completion report
less STREAM_7_COMPLETION_REPORT.md
```

### Report Issues
Include:
1. Transaction ID
2. Output of: `./manual-recovery.sh show tx_XXXXX`
3. Output of: `ls -la <source_path>`
4. Output of: `ls -la <temp_path>`
5. Output of: `zfs list | grep <dataset>`
6. Relevant log entries from /var/log/zfs-scripts.log

## Quick Reference Card Summary

| Command | Purpose |
|---------|---------|
| `./manual-recovery.sh` | Interactive mode |
| `./manual-recovery.sh list` | List pending |
| `./manual-recovery.sh show <tx_id>` | Show details |
| `./manual-recovery.sh rollback <tx_id>` | Rollback one |
| `./manual-recovery.sh recover` | Recover all |
| `./manual-recovery.sh cleanup [days]` | Cleanup old |

---

**Print this card and keep it handy for emergency recovery!**

**More info:** lib/TRANSACTIONS.md
