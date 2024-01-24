Run Processing Monitor
======================

This nextflow workflow manages the monitoring and automates launch of run
processing jobs following the completion of a run provided by the sequencing
laboratory at McGill Genome Center. Launches rely on Freezeman for their inputs
and outputs. There is also a some legacy code that managed the same but from
runs that were managed through Clarity (Illumina's proprietary Freezeman
equivalent).

Install
-------

Make sure to clone the repository along with its submodule.

```
git clone --recurse-submodules git@github.com:c3g/monitor.git

or

git clone --recurse-submodules https://github.com/c3g/monitor.git
```

Usage
-----

The monitor is dependant on the local McGill University cluster, Abacus. Make
sure to load the required modules before launching it.

```
module purge && module load mugqic/java/openjdk-jdk-17.0.1 mugqic/nextflow/22.10.6 mugqic/python/3.10.2
```

The simplest usage of the monitor is to run `main.nf` along with

```
nextflow run main.nf -profile [production,debug,dev] -entry [Monitor,Launch,MonitorAndLaunch]   
```

Redirecting the logs is recommended.

```
nextflow -log [filepath].log run main.nf -profile [production,debug,dev] -entry [Monitor,Launch,MonitorAndLaunch]
```

Remember to keep the nextflow logs tidy with

```
nextflow log

and 

nexflow clean
```

Notes
-----

### Particular set-up

The monitor is highly dependant on a number of softwares, env variables, ssh
keys, paths and network access that are only avaible on Abacus. It was not
designed to be run outside of the freezeman-[lims,qc,dev] users environment and
relies on some of their specific set-up. Notable examples of required set-up:

1. The runinfofiles are dumped by the Freezeman interface when an experiment is
   "Launched" to be processed and reingested to be added as a "Dataset" for run
   validation. They are copied via an rsync 5min cron job that relies on a
   unique ssh-key for each freezeman-[lims,qc,dev] to access the virtual
   machine under the "intermediary" user. A different user will have to move or
   copy these files themselves inside the directories set in `nextflow.config`
   under `neweventpath` & `newruninfopath`

2. Genpipes run_processing.py is using some software that are part of
   $MUGQIC_INSTALL_HOME_PRIVATE, such as bcl2fastq. To access these, one must
   set their environment using:

   ```
   export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
   module use $MUGQIC_INSTALL_HOME_PRIVATE/modulefiles
   ```

3. The user running the monitor should also have access to the run_processing
   directories: `/nb/Research/<platform>/<run_folder>`

4. Review the content of nextflow.config before launch. Paths listed in the
   configs should exist since the monitor will try to read from them in the
   early steps. There is also a final copy of the run_processing output files
   that is targeting a directory listed in the config parameter `custom_ini`
   files that should target one of the provided `.ini` files in the `assets`
   folder. Make sure that this folder exists before launching. In the `.ini`,
   search for

   ```
   [copy]
   destination_folder=/lb/project/mugqic/projects/[...]
   ```

### Launch delays

The Launch part of the monitor is particularly slow to be ready to receive
NovaSeq runs runinfofile. Even with the fzmn-child-process child config file
that reduce the glob pattern to check for `RTAComplete.txt` files, the launch
for Illumina takes at least 25 mins.

*The current version in production requires ~10 mins to be ready with MGI files
and a good 8 hours for Illumina files.*

Not only is the repo relying on Abacus' system and filesystem, the trigger that
launches the run processing relies on files dropped in the
`freezeman-lims-run-info` folder. In the current case, that is performed by a
5min cron job under freezeman-[lims,qc,dev] users that drops them in a folder
under freezeman-[lims,qc,dev] access.

I put some efforts on the bloating of the monitor and I will not put anymore.
Removing useless steps had an underwhelming impact on the overall monitor both
on time to run and memory usage. Reduced from ~40GB RAM to ~30GB in production
and similar impact on the launch of nextflow until all channels are up to
monitor. The only impactful changes would be to reduce the number of open
channels or limit the size of glob patterns and wildcards to match fewer
filepaths in the filesystem. Doing so would require to revisit the way
runinfofiles, RTAcomplete.txt and checkpoint files are monitored at the
filesystem level by the watchPatch channels.

### What is dependent on the monitor

Even though this monitor needs to be able to take care of Illumina & MGI
run_processing, at the moment, most run_processing is managed by Haig
Djambazian's pipeline which I believe is a set of bash scripts. However, it
seems that some of his processing relies on this monitor for complementary
steps, notably MultiQC and reporting emails. They are part of WatchCheckpoints
workflow in monitor.nf that manages the interface between Haig's stuff and this
monitor. It uses to run from the main branch of the repo, under the bravolims
user, but it hasn't been restarted since the last Abacus outages (2023/07/08 &
2023/08/05).
