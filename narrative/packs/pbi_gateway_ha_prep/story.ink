// Power BI Gateway HA Prep - Metra Narrative lesson (Ink)
// Non-bracket choices so # move: tags attach to Choice.tags.
// Metra-visible runtime tags: # move:<id> on choices, # terminal:success|fail on endings

VAR nodes_online = false
VAR spn_valid = false
VAR backup_confirmed = false
VAR change_window_open = false
VAR ready_to_update = false

-> intake

=== intake ===
You are at the operations desk preparing a Power BI Gateway high-availability cluster update. Confirm health before you change anything.

* Verify both gateway nodes are online # move:check_nodes
    ~ nodes_online = true
    Both HA members respond healthy.
    -> checks
* Skip node health and jump to update # move:skip_node_check
    You skip the health check and push toward the change. The lesson ends - prep was incomplete. # terminal:fail
    -> END

=== checks ===
Cluster checks are underway. Nodes online: {nodes_online}. SPN valid: {spn_valid}. Backup confirmed: {backup_confirmed}. Window open: {change_window_open}.

* { nodes_online && not spn_valid } Validate gateway service account / SPN # move:validate_spn
    ~ spn_valid = true
    The gateway service account and SPN check out.
    -> checks
* { spn_valid && not backup_confirmed } Confirm recovery / backup path # move:confirm_backup
    ~ backup_confirmed = true
    You confirm a restore or failover path if the update goes badly.
    -> checks
* { not backup_confirmed } Force update before backup confirmation # move:force_update_early
    You push the change without a recovery path. The lesson ends - unsafe. # terminal:fail
    -> END
* { backup_confirmed && not change_window_open } Confirm change window is open # move:open_window
    ~ change_window_open = true
    ~ ready_to_update = true
    The approved maintenance window is open. Prep looks complete.
    -> ready

=== ready ===
All prep checks passed. Nodes, SPN, backup, and change window are green.

* Begin gateway cluster update # move:begin_update
    You begin the cluster update with prep complete. # terminal:success
    -> END
