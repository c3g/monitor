Run Processing Monitor
======================

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
nextflow -log [file].log run main.nf -profile [production,debug,dev] -entry [Monitor,Launch,MonitorAndLaunch]
```

Remember to keep the nextflow logs tidy with

```
nextflow log

and 

nexflow clean
```
