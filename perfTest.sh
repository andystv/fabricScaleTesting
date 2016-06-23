#!/bin/bash 

test -d node_modules/request || (echo -n "npm install request... "; npm install request &> /dev/null ; echo "OK")

if [ "$1" == "50ms" ];then
	echo "$1 skipping"
	exit 1
fi

function printChaincodeSequences() {
for m in `seq 1 10`; do
        sleep 5
        for n in 2 3 4 5; do
                curl http://172.17.0.${n}:5000/chain
        done
done
}

mkdir logs &> /dev/null

delay=$1
CONSENSUS_FLAG="CORE_PEER_VALIDATOR_CONSENSUS_PLUGIN"
CONSENSUS_ALG="pbft"
CONSENSUS_MODE="classic"

if [[ "$2" == "--batch="* ]];then
	CONSENSUS_MODE="batch"
	BATCHSIZE=`echo $2 | cut -d= -f2`
	echo "Executing PBFT batch with batch size of $BATCHSIZE"
else 
	echo "Executing PBFT classic"
fi

RUN_CMD="node start --logging-level=debug"


if [ $# -eq 0 ];then
	delay="1ms"
fi

if [ "$2" == "old" ];then
	CONSENSUS_FLAG="CORE_PEER_VALIDATOR_CONSENSUS"
	RUN_CMD="peer"
fi

function logName() {
	echo "logs/vp$1-${delay}-${WORKERNUM}w-${ITERATIONS}xs-${CLUSTER_SIZE}n.log"
}

instanceCount=`docker ps -q | wc -l | sed "s/ //g"`
if [ $instanceCount -ne 0 ];then
        echo "Killing all docker containers..."
        docker ps -q | xargs docker kill
fi

echo "Running peers..."
echo "Running root peer"


docker run --cap-add=NET_ADMIN --rm -e CORE_PBFT_GENERAL_MODE=$CONSENSUS_MODE -e CORE_PBFT_GENERAL_BATCHSIZE=$BATCHSIZE -e CORE_PBFT_GENERAL_N=${CORE_PBFT_GENERAL_N:-4} -e CORE_PBFT_GENERAL_F=${CORE_PBFT_GENERAL_F:-1} -e CORE_VM_ENDPOINT=http://172.17.0.1:2375 -e CORE_PEER_LISTENADDRESS=172.17.0.2:30303 -e CORE_PEER_PORT=30303 -e CORE_PEER_ADDRESS=172.17.0.2:30303 -e CORE_PEER_ID=vp0 -e CORE_PEER_ADDRESSAUTODETECT=true -e $CONSENSUS_FLAG=$CONSENSUS_ALG hyperledger/fabric-peer  peer $RUN_CMD  &> `logName 0`  &
sleep 10
root=`docker ps -q`
echo "Root container is $root"
[ $# -eq 0 ] && tail -10 vp0.log
clusterSize=${CLUSTER_SIZE:-3}
for i in `seq $clusterSize`; do
        echo "Running peer $i"
        docker run --cap-add=NET_ADMIN --rm -e CORE_PBFT_GENERAL_MODE=$CONSENSUS_MODE -e CORE_PBFT_GENERAL_BATCHSIZE=$BATCHSIZE -e CORE_PBFT_GENERAL_N=${CORE_PBFT_GENERAL_N:-4} -e CORE_PBFT_GENERAL_F=${CORE_PBFT_GENERAL_F:-1} -e CORE_PEER_LISTENADDRESS=172.17.0.$(( i + 2 )):30303 -e CORE_PEER_PORT=30303 -e CORE_PEER_ADDRESS=172.17.0.$(( i + 2 )):30303 -e CORE_VM_ENDPOINT=http://172.17.0.1:2375 -e CORE_PEER_ID=vp$i -e CORE_PEER_DISCOVERY_ROOTNODE=172.17.0.2:30303 -e CORE_PEER_ADDRESSAUTODETECT=true -e $CONSENSUS_FLAG=$CONSENSUS_ALG hyperledger/fabric-peer  peer $RUN_CMD  &> `logName $i` &
        sleep 5
        [ $# -eq 0 ] && tail -10 `logName $i`
done

#echo "Running non validating peer"
#docker run --cap-add=NET_ADMIN --rm -e CORE_PEER_LOGGING_LEVEL=debug -e CORE_PEER_VALIDATOR_ENABLED=false -e CORE_VM_ENDPOINT=http://172.17.0.1:2375 -e CORE_PEER_ID=nvp0 -e CORE_PEER_DISCOVERY_ROOTNODE=172.17.0.2:30303,172.17.0.3:30303,172.17.0.4:30303,172.17.0.5:30303 -e CORE_PEER_ADDRESSAUTODETECT=true hyperledger-peer peer --logging-level=debug &> nvp.log &

#sleep 3

#export NVPADDR=`grep "using peerAddress:" ~/perfTest/nvp.log | awk '{print $NF}' | sed "s/30303/5000/g"`
#echo "NVP address is $NVPADDR"

echo "Sleeping 20 seconds"
sleep 20


export PEERS=`curl http://172.17.0.2:5000/network/peers 2> /dev/null`
echo $PEERS

function waitForStabilization() {
nodejs << EOF
var request = require('request');
var heights = {}
var start = new Date().getTime();
var lastHeight = 0;
var timesLastHeight = 0;
function query(uri) {
	request('http://' + uri + '/chain', function (error, response, body) {
	  if (!error && response.statusCode == 200) {
		heights[uri] = JSON.parse(body).height;
		setTimeout(query,1000,uri);
		if (uri.indexOf('0.2') == -1) {
			return;
		}
		//console.log(heights);
		var same = true;
		for (i in heights) {
			var url = i;
			if (heights[url] !== heights[uri])  {
				same = false;
			}
		}
		if (! same) {
			return;
		}
		if (lastHeight === heights[uri]) {
			timesLastHeight++;
			if (timesLastHeight > 30) {
				console.log(heights);
				process.exit(0);
			}	
		} else {
			lastHeight = heights[uri];
			timesLastHeight = 0;
		}
	  }
	});
}
JSON.parse(process.env.PEERS).peers.map(function(p) { query(p.address.replace("30303","5000"));});
EOF
}


echo -n "Deploying chaincode... "

id=`nodejs bench.js`
echo "deployed, chain id is $id"


echo "Injecting network delays into containers"
docker ps -q | grep -v $root | while read container; do
	docker exec $container tc qdisc add dev eth0 root netem delay $1
done

echo "Running benchmark..."

tps=`nodejs bench.js $id | grep TPS | awk '{print $NF}' 2> err.log`



#cpuTime=0
#docker ps | grep peer | awk '{print $1}' | while read container; do 
#	docker exec $container cat /proc/1/stat  | awk '{printf("%d\n",$14/100)}'; 
#done 
export TRANS_ID=$id
nodejs << EOF > query.txt
var queryData  = require('fs').readFileSync('query.json');
var queryJSON  = JSON.parse(queryData);
queryJSON.params.chaincodeID.name = '$TRANS_ID';
console.log(JSON.stringify(queryJSON));
EOF

start=`date +%s`
peerNum=`echo $PEERS | grep -o -n ID | wc -l`
i=0
while :; do
	sleep 1
	(( i += 1 ))
	if [[ $i -eq 500 ]] ;then
		echo $1 $tps "replicationFailed"
		exit 1
	fi
	echo $PEERS | grep -Eo "172.17.0.[0-9]+" | while read ip; do
		curl -v -X POST -d @query.txt http://$ip:5000/chaincode &> /dev/null
	done
	n=`docker ps -q | head -1 | while read cont;do docker logs $cont 2>&1  | grep Amount | tail -1; done | cut -d: -f4 | sed "s/}//g; s/\"//g"`
	if [ "$n" == "" ];then
		docker ps -q | head -1 | while read cont;do docker logs $cont 2>&1 | tail -10; done
		continue;
	fi
	echo $n
	if [ $n -lt 1 ];then
		break;
	fi
done
end=`date +%s`

echo $1 $tps $(( $end - $start )) | tee -a tps.log

echo "Tearing down containers"
docker ps -q | xargs docker kill  &> /dev/null
docker ps -aq | xargs docker rm &> /dev/null


