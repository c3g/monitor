#!/bin/bash

for i in "$@"; do
  case $i in
    -j|--jsons)
      JSONS=YES
      shift # past argument with no value
      ;;
    -e|--events)
      EVENTS=YES
      shift # past argument with no value
      ;;
    -c|--checkpoint)
      CHECKPOINT=YES
      shift # past argument with no value
      ;;
    -*|--*)
      echo "Unknown option $i"
      exit 1
      ;;
    *)
      ;;
  esac
done

sleep=3

if [[ -v JSONS ]];
then
    (
        echo "Queuing JSON flag files"
        for json in testing/holding/*.json; do
            mv $json testing/flag/
        done
        echo "Sleeping..."
        sleep $sleep
        echo "Moving JSONS back"
        mv testing/flag/*.json testing/holding
    ) &
fi


if [[ -v EVENTS ]];
then
    (
        echo "Queuing event files"
        for evt in testing/holding/*.txt; do
            mv $evt testing/events/
        done
        echo "Sleeping..."
        sleep $sleep
        echo "Moving event files back"
        mv testing/events/*.txt testing/holding
    ) &
fi

if [[ -v CHECKPOINT ]];
then
    (
        echo "Queuing checkpoint files"
        mv testing/holding/dummy.done /nb/Research/processingmgiscratch/processing/E100029251/job_output/checkpoint/
        echo "Sleeping..."
        sleep $sleep
        echo "Moving checkpoint file back"
        mv /nb/Research/processingmgiscratch/processing/E100029251/job_output/checkpoint/dummy.done testing/holding
    ) &
fi

wait

