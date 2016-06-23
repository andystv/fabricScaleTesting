var fs = require('fs');
var deployData = fs.readFileSync('deploy.json');
var invokeData = fs.readFileSync('invoke.json');
var request = require('request');
var ID = null;

//HOSTS=process.env.HOSTS || '{172.17.0.2}'
//HOSTNAME='172.17.0.2:5000'

peers=JSON.parse(process.env.PEERS).peers.map(function(peer) {return peer.address.replace('30303','5000')});

var iterations=parseInt(process.env.ITERATIONS || "1000");
var workerNum = parseInt(process.env.WORKERNUM || "1");

var invokeJson = JSON.parse(invokeData);
var payload    = null;
var i = 0;
var start;


var fs = require('fs');
var invokeLog = 'invTime.iter=' + iterations + '.wn=' + workerNum + '.log';
var errLog = 'errors.wn=' + workerNum + '.log';

fs.writeFile(invokeLog,'n,duration\n',function() {});

function invoke(data,invocationTime) {
	var end = new Date().getTime();
	fs.appendFile(invokeLog,i + "," + new Date().toString() + "," + invocationTime + "\n", function() {
	});

        if (i++ >=  iterations) {
                var elapsed = end - start
		console.log("average TPS:",parseInt(i*1000/elapsed))
		process.exit(0);
                return;
	}
	var id = data.result.message;
	//console.log("Sending chaincode('" + id + "') invocation: " + payload);
	payload.id = i;
	sendChainRequest(payload,invoke,new Date().getTime());
}

	
function bench(data,workerIndex) {
	if (process.argv.length == 2) {
		console.log(data.result.message);
		return;
	}
	var id = data;
	//console.log("Deployed, id="+id);
	invokeJson.params.chaincodeID.name = id;
	
	payload = JSON.stringify(invokeJson);
	//console.log("Sending chaincode('" + id + "') invocation: " + payload);
	start = new Date().getTime();
	sendChainRequest(payload,invoke,new Date().getTime(),workerIndex);
}

function sendChainRequest(query,callback,invokeTime,workerIndex) {
	workerIndex = workerIndex || 0;
	var url='http://' + peers[workerIndex % peers.length] + '/chaincode';
	var t1 = new Date().getTime();
	//console.log("Sending to",url);
	request({
	    url: url,
	    method: 'POST',
	    headers: {
	        'Content-Type': 'application/json'
	    },
	    body: query
	}, function(error, response, body){
	    if(error) {
	            fs.appendFile(errLog,error, function() {
                    });
	    } else {
		if (response.statusCode != 200) {
		        fs.appendFile(errLog,body, function() {
		        });
			return;
		}
		callback(JSON.parse(body),new Date().getTime() - t1,workerIndex);
	    }
	});
}

function stuck() {
	console.log("TPS: stuck");
	process.exit(3);
}

if (process.argv.length > 2) {
	for (var i=0; i<workerNum; i++) {
		setTimeout(bench,100,process.argv[2],i);
	}
	setTimeout(stuck,1000 * 60 * 10);
	return;
}

sendChainRequest(deployData,bench);
