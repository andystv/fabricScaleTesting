#!/bin/bash
cat out.log| head -1 | awk -F, '{ printf "|   "; for (i=1; i<=NF; i++) {printf "     %s    |", $i} ; print ""}' > table.md
cat out.log| head -1 | awk -F, '{ printf "|   "; for (i=1; i<=NF; i++) {printf " ------------------:|"} ; print ""}' >> table.md
cat out.log | grep "," | sed "s/ [0-9]*ms//g; s/,//g" | awk '{ printf "|   "; for (i=1; i<=NF; i++) {printf "%d    |", $i} ; print ""}' |  tail -n +2 | sed "s/|0/|FAILURE/g" >> table.md
cat table.md
