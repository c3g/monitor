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

Not only is the repo relying on Abacus' system and filesystem, the trigger that
launches the run processing relies on files dropped in the
`freezeman-lims-run-info` folder. In the current case, that is performed by a
5min cron job under freezeman-[lims,qc,dev] users that drops them in a folder
under freezeman-[lims,qc,dev] access.
