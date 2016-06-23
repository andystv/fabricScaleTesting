#!/bin/bash

echo "clusterSize ,delay, workers, iterations, batchSize, tps";
for clusterSize in 4 7 10 13 16 19 22; do
	for delay in 1 5 10 ; do
		for workerNum in 1 ; do 
			for iter in 1000 ; do 
				for batchSize in 1  5 10 20 50 100 ; do
					export WORKERNUM=$workerNum; 
					export ITERATIONS=$iter; 
					export CORE_PBFT_GENERAL_N=$clusterSize
					export CORE_PBFT_GENERAL_F=$(( $((  clusterSize - 1 )) / 3 ))
					export CLUSTER_SIZE=$(( clusterSize - 1 ))
					for attempt in 1 2 3 4 5 6 7 8 9 10; do
						tps=`./perfTest.sh ${delay}ms --batch=$batchSize | grep ms`; 
						echo $tps | grep -q "replicationFailed" && continue;
						echo  "$clusterSize, $delay, $workerNum, $iter, $batchSize, $tps"; 
						break;
					done
				done
			done
		done
	done
done
