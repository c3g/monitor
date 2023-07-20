Run Processing Monitor
======================

This nextflow workflow manages the monitoring and automates launch of run
processing jobs following the completion of a run provided by the sequencing
laboratory at McGill Genome Center. Launches rely on Freezeman for their inputs
and outputs.

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

The monitor is dependant on the local McGill University cluster, Abacus.

Make sure to load the required modules before launching it.

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

The Launch part of the monitor is particularly slow to be ready to receive
NovaSeq runs runinfofile. Even with the fzmn-child-process child config file
that reduce the glob pattern to check for `RTAComplete.txt` files, the Launch
for NovaSeq takes at least 25 mins.

*The current version in production requires ~10 mins to be ready with MGI files
and a good 8 hours for Illumina files.*

Not only is the repo relying on Abacus' system and filesystem, the trigger that
launches the run processing relies on files dropped in the
`freezeman-lims-run-info` folder. In the current case, that is performed by a
5min cron job under freezeman-[lims,qc,dev] users that drops them in a folder
under freezeman-[lims,qc,dev] access.


