# Collect Azure VM disk information with Resource Graph

Two Azure Resource Graph queries that inventory managed disks across every
subscription you can read. Use the output to size an Everpure Cloud (Cloud Block
Store) deployment: which data disks exist, how big they are, what they cost to
run today, and which VNets they would need to be reachable from.

Run these in [Azure Resource Graph Explorer](https://portal.azure.com/#blade/HubsExtension/ArgQueryBlade)
in the Azure portal, then export to CSV.

![Resource Graph Explorer showing the query and results](screenshot.png)

## Which query to run

| File | Scope | Extra data |
| --- | --- | --- |
| `QueryDataDisks` | Data disks only (`properties.osType` is null) | Subscription name, full resource ID, snapshot rollup |
| `QueryAllDisks` | Every managed disk, OS and data | None. Returns `subscriptionId` rather than the subscription name |

`QueryDataDisks` is the one you want for sizing. OS disks stay on Azure managed
disks; only data disks are candidates to move to Everpure Cloud, so filtering
them out up front keeps the capacity totals honest.

`QueryAllDisks` is the same query with the OS-disk filter commented out at line
24 and the subscription and snapshot joins removed. Reach for it when you need
a full disk inventory rather than a migration candidate list.

## Running it

1. Open Resource Graph Explorer in the Azure portal.
2. Set the scope with the **Subscriptions** picker above the editor. It defaults
   to every subscription your account can read, which is usually what you want.
3. Paste the query and select **Run query**.
4. Select **Download as CSV**.

You need `Microsoft.Compute/disks/read`, `Microsoft.Network/networkInterfaces/read`,
and `Microsoft.Compute/snapshots/read` on the subscriptions in scope. Reader at
subscription level covers all three. Reader on only the compute resource groups
returns the disks but not the NICs, which shows up as an empty `vnetName`. See
the next section.

## Reading the output

`osDisk` is empty for a data disk and holds `Windows` or `Linux` for an OS disk.
In `QueryDataDisks` every row is a data disk, so the column is always empty; it
is kept so the two queries produce the same schema.

`diskState` distinguishes an attached disk from one that is provisioned and
billed but connected to nothing. `Unattached` disks bill at full provisioned
capacity and are worth calling out separately in a sizing conversation.

`snapshotBilledCapacityGB` sums only full (non-incremental) snapshots, which bill
at the source disk's provisioned size. Incremental snapshots bill on written
delta, and Resource Graph does not expose that delta, so this column is a floor
rather than a total. `incrementalSnapshotCount` tells you how many snapshots are
missing from the figure. `snapshotProvisionedCapacityGB` counts both kinds at
source-disk size, which is the upper bound.

`diskIOPS` and `diskBW` are the values the disk resource reports. Premium SSD v2
and Ultra Disk set these explicitly per disk; other SKUs report the tier default
for their size. They are not observed throughput. Pull that from Azure Monitor if
you need it.

### When vnetName is empty

`vnetName` comes from the subnet ID on the VM's network interface, reached by
joining `disk.managedBy` to `nic.properties.virtualMachine.id`. Several things
break that join, and the old version of this query returned a blank cell for all
of them. `QueryDataDisks` now reports which one applies in `vnetLookupStatus`:

- **`ok`** - a NIC matched. `vnetName`, `subnetName`, and `nicNames` are
  populated. A VM with more than one NIC produces a semicolon-delimited list.
- **`unattached-disk`** - `managedBy` is empty because the disk is not attached
  to anything. There is no VNet to report. Expected.
- **`vmss-managed-nic`** - the disk belongs to a Virtual Machine Scale Set
  instance. Under Uniform orchestration the NIC is a child of the scale set
  rather than a standalone `Microsoft.Network/networkInterfaces` resource, so it
  is not in the `resources` table and cannot be joined. `VmName` is reported as
  `scaleSetName_instanceId`. Flexible orchestration VMSS resolve normally and
  return `ok`.
- **`no-nic-matched`** - a VM ID is present but no NIC matched it. Almost always
  RBAC: you can read the compute resource group but not the network resource
  group holding the NIC. Common in hub-and-spoke tenants where networking is
  owned by a separate team. Widen the subscription scope or get Reader on the
  network resource groups, then rerun.

## Limits

CSV export from Resource Graph Explorer stops at **55,000 rows**. This is a
platform cap and cannot be raised through a support ticket. Past that, split the
run by subscription or management group using the scope picker.

These queries do not run under `Search-AzGraph` or `az graph query`. Resource
Graph allows three `join` or `union` operations per query and permits a table to
appear as the right-hand side of a join only once. `QueryDataDisks` uses
`resources` on the right twice, for network interfaces and for snapshots, which
returns `DisallowedMaxNumberOfRemoteTables` through the SDK. Resource Graph
Explorer runs under a higher limit, so the portal is the supported path. To
script it, split the snapshot rollup into a second query and join the two result
sets client-side.

Resource Graph data is eventually consistent. A disk attached or resized in the
last few minutes may not be reflected yet.