#!/bin/bash

echo "clusterSize ,delay, workers, iterations, tps";
for clusterSize in 4 7 10 13 16 19 22; do
	for delay in 1 5 10 20 50 ; do
		for workerNum in 1 ; do 
			for iter in 5000 ; do 
				export WORKERNUM=$workerNum; 
				export ITERATIONS=$iter; 
				export CORE_PBFT_GENERAL_N=$clusterSize
				export CORE_PBFT_GENERAL_F=$(( $((  clusterSize - 1 )) / 3 ))
				export CLUSTER_SIZE=$(( clusterSize - 1 ))
				tps=`./perfTest.sh ${delay}ms | grep ms`; 
				echo  "$clusterSize, $delay, $workerNum, $iter, $tps"; 
			done
		done
	done
done
