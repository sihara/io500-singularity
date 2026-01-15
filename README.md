# IO500 on EXAScaler with Singularity
Singularity provides isolated user namespaces, enabling secure and portable execution of applications.
DDN EXAScaler also supports multiple mount points on client nodes, which can be associated with each Singularity namespace for both security and performance purposes.  
This guide provides a step-by-step workflow for running the IO500 benchmark on DDN EXAScaler using Singularity containers.

## Overview
- Run IO500 using Singularity containers  
- Integrate `lipe_scan` to accelerate the "find" phase of the IO500 benchmark  
- Provide configuration templates for `lipe_scan` and Singularity-based execution
- Associate each Singularity namespace with a unique EXAScaler mount point for secure and optimized data access  
- Build and configure Singularity images for benchmark workloads

## Prerequisites
- An HPC cluster with MPI and a job scheduler (this guide assumes SLURM, but other schedulers should work)
- Singularity installed on all compute nodes
- EXAScaler filesystem mounted on each node

## Quick Start
### 1. Verify the cluster and run a sample MPI program using Singularity
#### 1.1 Check cluster status
```bash
[bmuser@src01-c0-n0 ~]$ sinfo 
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
src          up   infinite     16   idle src01-c0-n0,src02-c0-n0,src03-c0-n0,src04-c0-n0,src05-c0-n0,src06-c0-n0,src07-c0-n0,src08-c0-n0,src09-c0-n0,src10-c0-n0,src11-c0-n0,src12-c0-n0,src13-c0-n0,src14-c0-n0,src15-c0-n0,src16-c0-n0
```

#### 1.2 Download a base Singularity image and run a sample MPI program
```bash
# Download the same OS image as the host (Rocky Linux 9)
[bmuser@src01-c0-n0 ~]$ singularity pull --arch amd64 library://library/default/rockylinux:9

# Copy the image and sample MPI binary to the shared EXAScaler directory
[bmuser@src01-c0-n0 ~]$ cp rockylinux_9.sif /exafs/io500/
[bmuser@src01-c0-n0 ~]$ mpicc -o hello <path>/io500-singularity/hello.c
[bmuser@src01-c0-n0 ~]$ cp hello /exafs/io500/

# Run the MPI program inside the Singularity container across 10 nodes
[bmuser@src01-c0-n0 ~]$ salloc -p src -N 10 --ntasks-per-node=1 mpirun singularity exec -B /exafs -B /usr /exafs/io500/rockylinux_9.sif /exafs/io500/hello
salloc: Granted job allocation 117268
salloc: Nodes src01-c0-n0,src02-c0-n0,src03-c0-n0,src04-c0-n0,src05-c0-n0,src06-c0-n0,src07-c0-n0,src08-c0-n0,src09-c0-n0,src10-c0-n0 are ready for job
Hello from task 6 of 10 on src07-c0-n0!
Hello from task 4 of 10 on src05-c0-n0!
Hello from task 1 of 10 on src02-c0-n0!
Hello from task 0 of 10 on src01-c0-n0!
Hello from task 3 of 10 on src04-c0-n0!
Hello from task 7 of 10 on src08-c0-n0!
Hello from task 5 of 10 on src06-c0-n0!
Hello from task 9 of 10 on src10-c0-n0!
Hello from task 2 of 10 on src03-c0-n0!
Hello from task 8 of 10 on src09-c0-n0!
salloc: Relinquishing job allocation 117268
[bmuser@src01-c0-n0 ~]$ 
```

### 2. Run IO500
#### 2.1 Download and Configure IO500
Clone the IO500 repository and build the required binaries:
```bash
[bmuser@src01-c0-n0 ~]$ cd /exafs/io500
[bmuser@src01-c0-n0 io500]$ git clone https://github.com/IO500/io500.git io500.git
[bmuser@src01-c0-n0 io500]$ cd io500.git
[bmuser@src01-c0-n0 io500.git]$ git checkout -b io500-isc25 io500-isc25
[bmuser@src01-c0-n0 io500.git]$ ./prepare.sh
```

After successful build, you should see the following:
```bash
[bmuser@src01-c0-n0 io500.git]$ ls io500 bin
io500

bin:
ior  mdtest  md-workbench  pfind
```

Create your custom run script and configuration file. 
```bash
[bmuser@src01-c0-n0 io500.git]$ cp io500.sh myio500.sh
[bmuser@src01-c0-n0 io500.git]$ ./io500 --list > myio500.ini
```

#### 2.2 Copy lipe_scan scripts for io500 integration
On the EXAScaler MDS nodes, copy lipe_scan_io500.json.template and lipe_scan_io500.sh to /tmp/io500, and sync to other MDSs:
```bash
[root@ai400x2-2-vm1 ~]# mkdir /tmp/io500
[root@ai400x2-2-vm1 ~]# cp <path>/io500-singularity/lipe_scan_io500.json.template \
  io500-singularity/lipe_scan_io500.sh /tmp/io500/
[root@ai400x2-2-vm1 ~]# sync-file -g mds /tmp/io500/
```

On the compute node, copy lipe_scan_wrapper.sh to bin/ directory under io500.git:
```bash
[bmuser@src01-c0-n0 io500.git]$ cp <path>/io500-singularity/lipe_scan_wrapper.sh bin/
```

#### 2.3 Modify myio500.sh and myio500.ini
Shorten the stonewall time for quick testing, and configure the external find script:
```bash
# myio500.ini
stonewall-time = 30

[find]
# Set to an external script to perform the find phase
external-script = ./bin/lipe_scan_wrapper.sh
```

Set the MDS nodes and user in lipe_scan_wrapper.sh, as lipe_scan requires root privileges to run on MDS nodes.
```bash
EXA_USER=root
EXA_MDS=ai400x2-2-vm[1-4]
```

Update myio500.sh to run inside the Singularity container:
```bash
io500_mpirun="mpirun"
io500_mpiargs="singularity exec -B /exafs -B /usr /exafs/io500/rockylinux_9.sif"
```

#### 2.4 Create a SLURM job script to run IO500
Here’s an example SLURM job script (run_io500.sh):
```bash
[bmuser@src01-c0-n0 io500.git]$ cp <path>/io500-singularity-draft/run-io500.sh
[bmuser@src01-c0-n0 io500.git]$ sbatch run_io500.sh
```
Be sure to customize the number of nodes and tasks per node in run-io500.sh according to your system configuration.
```bash
[bmuser@src01-c0-n0 io500.git]$ cat results/2025.05.11-11.02.49/result_summary.txt 
[RESULT]       ior-easy-write       10.608264 GiB/s : time 35.013 seconds [INVALID]
[RESULT]    mdtest-easy-write       29.244625 kIOPS : time 33.941 seconds [INVALID]
[      ]            timestamp        0.000000 kIOPS : time 0.001 seconds
[RESULT]       ior-hard-write        0.381392 GiB/s : time 599.690 seconds
[RESULT]    mdtest-hard-write       19.860258 kIOPS : time 36.082 seconds [INVALID]
[RESULT]                 find    24346.302247 kIOPS : time 4.760 seconds
[RESULT]        ior-easy-read       18.397064 GiB/s : time 19.701 seconds
[RESULT]     mdtest-easy-stat       36.866300 kIOPS : time 27.141 seconds
[RESULT]        ior-hard-read        6.904673 GiB/s : time 31.825 seconds
[RESULT]     mdtest-hard-stat       39.002295 kIOPS : time 18.877 seconds
[RESULT]   mdtest-easy-delete       33.458041 kIOPS : time 29.804 seconds
[RESULT]     mdtest-hard-read       15.063562 kIOPS : time 47.240 seconds
[RESULT]   mdtest-hard-delete       34.007658 kIOPS : time 21.507 seconds
[      ]  ior-rnd4K-easy-read        0.134469 GiB/s : time 30.157 seconds
[SCORE ] Bandwidth 4.761314 GiB/s : IOPS 65.731505 kiops : TOTAL 17.690911 [INVALID]
```

lipe_scan successfully replaced the default pfind in the find phase.
```bash
[bmuser@src01-c0-n0 io500.git]$ cat results/2025.05.11-11.02.49/result.txt
-- snip --
[find]
t_start         = 2025-05-11 02:14:34
exe             =  ./bin/lipe_scan_wrapper.sh  ./datafiles/2025.05.11-11.02.49 -newer ./results/2025.05.11-11.02.49/timestampfile -size 3901c -name "*01*"
last-output     = "MATCHED 327094/115846524"
total-files     = 115846524
found           = 327094
score           = 24346.302247
t_delta         = 4.7598
t_end           = 2025-05-11 02:14:39
```
All lipe_scan results are also stored under results/.../lipe_scan_results.

Once lipe_scan successfully replaces the find phase and results are correctly stored, you are ready to run the full IO500 benchmark.
You should also review Section 3. Further optimizations to tune I/O performance for IO500 workloads.

### 3. Further optimizations
#### 3.1 Enable O_DIRECT for ior-easy
```bash
[ior-easy]
# The API to be used
API = POSIX --posix.odirect
# Transfer size
transferSize = 1m
```

#### 3.2 Customize the IO500 output directories to optimize performance with EXAScaler.
```bash
function setup(){
  local workdir="$1"
  local resultdir="$2"
  mkdir -p $workdir $resultdir

  mkdir $workdir/ior-easy $workdir/ior-hard
  mkdir $workdir/mdtest-easy $workdir/mdtest-hard
  lfs setstripe -C 1280 $workdir/ior-hard

  lfs setdirstripe -D -c -1 $workdir/mdtest-hard
  lfs setdirstripe -D --max-inherit-rr 2 $workdir/mdtest-easy
  # Example commands to create output directories for Lustre.  Creating
  # top-level directories is allowed, but not the whole directory tree.
}
```
The stripe count (-C 1280) for ior-hard should ideally equal to the total number of MPI processes (NP) used in the IO500 run.

If you want to enable DoM (Data on Metadata), you can further optimize small file access with the following settings:
```bash
  lfs setstripe -E 64k -L mdt $workdir/mdtest-easy
  lfs setstripe -E 64k -L mdt $workdir/mdtest-hard
```

#### 3.3 Applied Parameters for EXAScaler
##### EXAScaler Servers: Disable T10PI
EXAScaler may enable T10PI (Data Integrity Extensions) by default, which can introduce performance overhead. You can check whether `write_generate` or `read_verify` is enabled using the following commands:

```bash
[root@ai400x2-2-vm1 ~]# clush -a 'for dev in /sys/block/*/integrity/write_generate; do cat $dev; done'

[root@ai400x2-2-vm1 ~]# clush -a 'for dev in /sys/block/*/integrity/read_verify; do cat $dev; done'
```
If either returns 1, T10PI is enabled.

To disable T10PI and reduce extra I/O overheads:
```bash
[root@ai400x2-2-vm1 ~]# clush -a 'for dev in /sys/block/*/integrity/write_generate; do echo 0 > $dev; done'

[root@ai400x2-2-vm1 ~]# clush -a 'for dev in /sys/block/*/integrity/read_verify; do echo 0 > $dev; done'
```

##### EXAScaler clients
Disable checksums
```bash
[bmuser@src01-c0-n0 io500.git]$ clush -g myclient sudo lctl set_param osc.*.checksums=0
```

Reduce lock cache lifetime (LDLM LRU max age):
```bash
[bmuser@src01-c0-n0 io500.git]$ clush -g myclient sudo lctl set_param ldlm.namespaces.*.lru_max_age=5000
# Default lru_max_age is 3900000
```
In IO500, lock cache entries are not reused, so shortening the LRU max age allows acquired locks to be cancelled immediately after use.

#### 3.4 Enabling multiple mount points 
EXAScaler supports multiple client-side mount points based on separate Lustre export/import, which are useful in several scenarios:
- Mounting specific subdirectories for isolation or access control (e.g. /home, /app, /work)
- Multi-tenancy environments using sub-volume exports with Lustre Nodemap (e.g. /tenant1, /tenant2)
- Mount filesystem as a separate PVC in Kubernetes
- Performance acceleration, for example, mapping per-GPU workloads to different mount points (e.g. /exafs/gpu-0, /exafs/gpu-1..)

Here is how to use multiple mount points for io500 to accelarte the IO performance
##### Create multiple mount points
```bash
[bmuser@src01-c0-n0 io500.git]$ clush -g myclient 'for i in `seq 0 7`; do sudo mkdir /exafs_$i; done'
[bmuser@src01-c0-n0 io500.git]$ clush -g myclient 'for i in `seq 0 7`; do sudo mount -t lustre 10.0.11.244@o2ib12:10.0.11.245@o2ib12:/exafs /exafs_$i; done'
[bmuser@src01-c0-n0 io500.git]$ clush -g myclient -B "mount -t lustre | wc -l"
---------------
src[01-10]-c0-n0 (10)
---------------
9
```
##### Copy singularity.sh and Modify myio500.sh
```bash
[bmuser@src01-c0-n0 io500.git]$ cp <path>/io500-singularity-draft/singularity.sh .
```

myio500.sh 
```bash
io500_mpiargs="singularity.sh /exafs 8 -B /usr /exafs/io500/rockylinux_9.sif"
```

##### Re-run io500 and confirm all mount points are used in RoundRobin manner
```bash
[bmuser@src01-c0-n0 io500.git]$ sbatch run_io500.sh
```

NOTE: Avoid using a large number of mount points without proper tuning.
Each mount point consumes memory and system resources. When deploying multiple mount points in production, it is essential to adjust relevant Lustre client parameters to avoid performance degradation.





