#!/bin/bash

mysql="/home/medsrv/component/mysql/bin/mysql"
database="imagemedical"
query="
SELECT
  Target.id AS NAME,
  Target.host AS IP,
  Target.port AS PORT,
  Target.AE AS AE,
  Target.type AS TYPE,
  IFNULL(GROUP_CONCAT(DevServ.SERVICE), 'NULL (No Rights Assigned)') AS RIGHTS
FROM Target LEFT JOIN DevServ
  ON Target.id = DevServ.DEVICE
WHERE
  DevServ.SERVICE LIKE '%AFwd%'
GROUP BY NAME;"

function showForwardDevices() {
    echo "Executing query to fetch forward devices..."
    # Run query without table formatting to check for output
    result=$(echo "$query" | $mysql -N "$database")
    if [ -z "$result" ]; then
        echo "No forward devices configured on the device table."
    else
        echo "$query" | $mysql -t "$database"
    fi
}

showForwardDevices
