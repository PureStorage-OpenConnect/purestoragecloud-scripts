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
| `QueryAllDisks` | Every managed disk, OS and data | Same columns as `QueryDataDisks` |

`QueryDataDisks` is the one you want for sizing. OS disks stay on Azure managed
disks; only data disks are candidates to move to Everpure Cloud, so filtering
them out up front keeps the capacity totals honest.

`QueryAllDisks` is the same query with the OS-disk filter removed. Every other
clause, join and output column is identical. Reach for it when you need a full
disk inventory rather than a migration candidate list.

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

`vmOsType` is the operating system of the **VM the disk is attached to**, which
is the column you want when you need to tell Windows and Linux workloads apart.
A data disk carries no OS type of its own, because `properties.osType` is what
Azure uses to mark a disk as an OS disk in the first place. `vmOsType` is read
from the VM resource, or from the scale set's `virtualMachineProfile` for disks
on scale set instances. It is empty only for unattached disks, which have no VM
to read it from.

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
  populated. A VM with more than one NIC produces a semicolon-delimited list of
  subnets. A VM cannot span virtual networks, so `vnetName` is effectively always
  single-valued; a semicolon there indicates a stale or duplicated NIC record.
- **`ok-vmss-instance-nic`** - the disk belongs to a Uniform Virtual Machine
  Scale Set instance and its VNet was resolved from the scale set's instance
  NIC. `vmssName` names the scale set. See the note below.
- **`unattached-disk`** - `managedBy` is empty because the disk is not attached
  to anything. There is no VNet to report. Expected.
- **`vmss-no-nic-matched`** - the disk belongs to a scale set instance but no
  instance NIC was readable, usually RBAC on the scale set's resource group.
- **`no-nic-matched`** - a VM ID is present but no NIC matched it. Almost always
  RBAC: you can read the compute resource group but not the network resource
  group holding the NIC. Common in hub-and-spoke tenants where networking is
  owned by a separate team. Widen the subscription scope or get Reader on the
  network resource groups, then rerun.

### Scale set disks

Under **Uniform** orchestration an instance NIC is a child of the scale set, not
a standalone `Microsoft.Network/networkInterfaces` resource, so it never appears
in the `resources` table. It does appear in the `ComputeResources` table as
`microsoft.compute/virtualmachinescalesets/virtualmachines/networkinterfaces`,
which is where these queries read it from.

Two identifier traps are worth knowing if you modify this. The disk's
`managedBy` names the instance by *name* (`myvmss_0`) while the NIC names it by
*index* (`0`), so the two cannot be joined directly. These queries sidestep that
by joining on the scale set path instead of the instance path, which is correct
because every instance in a scale set is stamped from one model and therefore
shares its virtual network. Separately, only disks **explicitly attached** to an
instance become real disk resources; disks declared in the scale set's
`virtualMachineProfile` are implicit and never appear in Resource Graph at all.

Under **Flexible** orchestration instances are ordinary
`Microsoft.Compute/virtualMachines` with standalone NICs, so they resolve
through the normal path and return `ok`.

## Limits

CSV export from Resource Graph Explorer stops at **55,000 rows**. This is a
platform cap and cannot be raised through a support ticket. Past that, split the
run by subscription or management group using the scope picker.

Resource Graph limits how many `join` and `union` operations a query may use,
and a non-default table may appear as the right-hand side of a join only once.
These queries reference `ComputeResources` exactly once for that reason;
referencing it twice returns `DisallowedMaxNumberOfRemoteTables`. Both queries
have been run successfully through the Resource Graph REST API as well as
Resource Graph Explorer.

If you extend them, count the operations first. The current shape is four joins
plus two unions, which is **above** the documented ceiling of three combined
`join` and `union` operations. Both queries execute today through Resource Graph
Explorer and the REST API, verified, but that extra headroom is undocumented and
Microsoft could tighten it. If a future change starts returning an operator or
remote-table error, the `vmOsType` join is the one to drop first: it is the only
clause that is nice-to-have rather than load-bearing.

Resource Graph data is eventually consistent. A disk attached or resized in the
last few minutes may not be reflected yet.