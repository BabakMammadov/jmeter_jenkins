#!/bin/bash

# bash executejmeter.sh  branch_name jmx_name

# Define variables
currentDate=$(date +%Y/%m/%d)
currentTime=$(date +%H%M%S)
currentDir=$(pwd)
branchName=$1
jmxFileName=$2
reportDir='/opt/nginx'
jmeterDir='/etc/jmeter/bin'
projectReportDir="$reportDir/$branchName/$currentDate/report-$currentTime"
reportURL="http://reportloadtest.example.az/$branchName/$currentDate/report-$currentTime/index.html"
getRemoteIpsCommaSeparated=$(cat ip.txt | awk '{r=r s $1;s=","} END{print r}')
getRemoteIpsSpaceSeparated=$(cat ip.txt | awk '{r=r s $1;s=" "} END{print r}')

# Check argument size correctly set
if [ "$#" -ne 2 ]; then
    echo "Illegal number of parameters, you must use as below"
    echo "Example:  ./script.sh  branch_Name jmxFileName "
    exit 0
fi

# parsing csv files for distributing load testing - Importanf if you use unique body or header data in your post/get/put/delete  for every request, needs to be parsed files based count of slave server and copy every parse file to slave server
function parsecsv {
    fileName=$1
    filePath='./parsedfiles'
    countOfServers=$(cat  ./ip.txt | wc -l)
    firstStringOfLine=$(head -1 $filePath/$fileName)
    countLines=$(cat $filePath/$fileName | grep -v "$firstStringOfLine" | wc -l)
    resultLine=$(($countLines/$countOfServers))    
    startOfLine='2'
    for i in $(seq 1 $countOfServers);
    do 
        ipaddr=$(sed -n "$i"p  ip.txt)
        endOfLine=$(($i*$resultLine));
        echo $firstStringOfLine > $filePath/$ipaddr-$fileName
        awk "NR >= $startOfLine && NR <= $(($endOfLine-1))" $filePath/$fileName  >> $filePath/$ipaddr-$fileName
        startOfLine=$(($i*$resultLine));
    done    
}

# Copy or delete jmeter csv files/parsedfiles to/from jmeter slave servers
function copy_delete_remote_files  {
    operation=$1
    fileType=$2

    if [ $fileType == 'files' ]
    then
        iterFiles=$(ls ./files 2> /dev/null)
    elif [ $fileType == 'parsedfiles' ]
    then
        iterFiles=$(ls ./parsedfiles 2> /dev/null)
        if [ $operation == 'copy' ]
        then
            for filename in $iterFiles
            do
                # call parse function  and copy parsed files to aproprietly servers  
                parsecsv $filename
            done
        fi

    else    
        echo "You don't set true file type"
        exit 0
    fi

    if [ -d ./$fileType ]
    then
        for i in $iterFiles
        do
            if [[ -f "./$fileType/$i" ]]; then
                for ip in $getRemoteIpsSpaceSeparated
                do
                    if [ $operation == 'copy' ]
                    then
                        ssh root@$ip "mkdir -p $jmeterDir/$fileType"
                        if [ $fileType == 'files' ]
                        then
                            echo "Copy files $i to remote $ip server jmeter bin/$fileType directory"
                            scp ./$fileType/$i root@$ip:$jmeterDir/$fileType
                        else    
                            ls ./$fileType
                            echo "Copy parsed files $i to remote $ip server jmeter bin/$fileType directory"
                            scp ./$fileType/$ip-$i root@$ip:$jmeterDir/$fileType/$i
                        fi
                    fi
                    if [ $operation == 'delete' ]
                    then
                        echo "Delete $fileType from remote $ip server"
                        ssh root@$ip "rm -rf $jmeterDir/$fileType"
                    fi
                done
            fi
        done
    fi
}

# Copy  files and parsed files to jenkins slave servers before jmeter load script executed
copy_delete_remote_files copy  files && copy_delete_remote_files copy  parsedfiles

# Create dynamic web server directory for jmeter html reporting
mkdir -p  $projectReportDir

# Change directory to Jmeter bin for executing script and taking csv files path truely 
if [ -d $jmeterDir ]
then
   pushd $jmeterDir
fi

# Execute Jmeter Script ang generate load test report in web server directory
sh jmeter.sh -n -t $currentDir/$jmxFileName  -j $reportDir/$branchName/$currentDate/$currentTime.log -l $reportDir/$branchName/$currentDate/report-$currentTime.csv  -e -o $projectReportDir/  -R$getRemoteIpsCommaSeparated
result=$(echo $?)
if [ "$result" == "0" ];
then
    # Delete files  and parsed files from jenkins slave servers  after jmeter load script finished
    copy_delete_remote_files delete files && copy_delete_remote_files delete parsedfiles
fi

# Generate report, you will see this url  in Jenkins Pipeline job output
echo "Report Url:"  $reportURL
echo -e  "\n"
exit 0
