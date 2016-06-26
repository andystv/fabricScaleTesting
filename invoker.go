package main

import (
	"fmt"
	"net/http"
	"io/ioutil"
	"strings"
	"encoding/json"
	"time"
	"os"
	"sync"
	"strconv"
)

var restEndpointURI = "http://172.17.0.2:5000/chaincode"
var invokeEndpointURI = restEndpointURI + "?wait=20s"
var okString = `status":"OK"`

func main() {
	args := os.Args[1:]
	var chainId string
	if len(args) > 0 {
		chainId = args[0]
		fmt.Printf("Deploying to chainId %s\n",chainId);
	} else {
		chainId = deploy();
		fmt.Printf("Deployed ChainCode, id is '%s'\n", chainId)
	}

	var inc int
	if len(args) > 1 {
		inc, _ = strconv.Atoi(args[1])
	} else {
		inc = 1
	}

	iMax := 0
	i := inc
	if i < 2 {
		i = 10
	}
	j := 0
	tpsArr := make([]int, 50)
	for k := range tpsArr {
		tpsArr[k] = 999999
	}
	max := 0
	for {
		tps := calcThroughput(chainId, i)
		if tps == 0 {
			break
		}
		if tps > max {
			max = tps
			iMax = i
			fmt.Println("Found new max: ",max);
			j = 0
		} else {
			j = (j+1) % 50
			tpsArr[j] = tps
		}

		allSmaller := true
		for _, k := range tpsArr {
			if k > max {
				allSmaller = false
			}
		}	

		i += inc

		if allSmaller {
			fmt.Println("Found local maxima:",max);
			break;
		}

		fmt.Println(i,tps)

		time.Sleep(time.Duration(5000) * time.Millisecond)
	}
	fmt.Println(iMax,max)
}

type Ack struct{}

func calcThroughput(chainId string, parallelism int) int {
	var payload string
	var err error
	payload, err = prepareInvokePayload(chainId)
	if err != nil {
		fmt.Errorf("Failed creating invoke payload: %v", err)
		return 0
	}
	acks := make(chan Ack, parallelism);
	var wg sync.WaitGroup
	start := time.Now()
	for i := 0; i < parallelism; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s, err := send(invokeEndpointURI, payload)
			if err != nil {
				return
			}
			if strings.Index(s, okString) == -1 {
				return
			}
			acks <- Ack{}
		}()
	}
	wg.Wait()
	if len(acks) != parallelism {
		return 0
	}
	elapsed := time.Since(start)
	timeInSeconds := elapsed.Seconds()
	return int(float64(parallelism) / timeInSeconds)
}

func deploy() string {
	var deployPayload = `{
 	 "jsonrpc": "2.0",
  	"method": "deploy",
  	"params": {
    	"type": 1,
   	 "chaincodeID":{
  	      "path":"github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02"
 	   },
    	"ctorMsg": {
	        "function":"init",
	        "args":["a", "1000", "b", "0"]
    	}
  	},
  	"id": 1
	}`
	resp, _ := send(restEndpointURI, deployPayload)
	var jsonObj map[string]string
	json.Unmarshal([]byte(resp), &jsonObj)
	return jsonObj["message"]
}

func prepareInvokePayload(chainId string) (string, error) {
	var invokeString = ` {
	  "jsonrpc": "2.0",
  	"method": "invoke",
  	"params": {
	      "type": 1,
	      "chaincodeID":{
          	"name":"ID"
	      },
	      "ctorMsg": {
         	"function":"invoke",
	         "args":["a", "b","1"]
	      }
	  },
	  "id": 3
	} `
	var jsonObj map[string]interface{}
	json.Unmarshal([]byte(invokeString), &jsonObj)
	jsonObj["params"].(map[string]interface{})["chaincodeID"].(map[string]interface{})["name"] = chainId
	s, err := json.Marshal(&jsonObj)
	return string(s), err
}

func send(url string, payload string) (string, error) {
	if resp, err := http.Post(url, "application/json", strings.NewReader(payload)); err == nil {
		defer resp.Body.Close()
		if body, err := ioutil.ReadAll(resp.Body); err != nil {
			fmt.Errorf("Failed reading response", err)
			return "", err
		} else {
			return (string(body)), nil
		}
	} else {
		return "", err
	}
}

