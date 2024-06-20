#!/bin/bash

echo "Passed argument: $1"
if [[ ! -f "$1" ]]; then
	echo "ERROR: File does not exist: ($1). Exiting..."
	exit 1;
else
	echo "FILE EXISTS"
	if [[ "$1" =~ (.+)\.([^.]+)$ ]]; then
		echo "${BASH_REMATCH[*]}"
		pathAndFileBaseName="${BASH_REMATCH[1]}"
		fileExtension="${BASH_REMATCH[2]}"
		outFile="${pathAndFileBaseName}.nppLog"
		# echo "path + basename: $pathAndFileBaseName"
		# echo "fileExtension: $fileExtension"
		echo "outFile: $outFile"

		dos2unix -n "$1" "$outFile"

		SECTION=`echo -e "\0247"`
		PARAGRAPH=`echo -e "\0266"`
		LOG_HEADER="^(FATAL|ERROR|WARNING|INFO|DEBUG|TRACE)"
		sedExpression="1s/${LOG_HEADER}/${SECTION}\\{ \\1/g;2,\$s/${LOG_HEADER}/${PARAGRAPH} \\}${SECTION}\\n${SECTION}\\{ \\1/g"
		# echo -e "sedExpression:\n$sedExpression"
		sed -Ei "$sedExpression" "$outFile"
		echo "${PARAGRAPH} }${SECTION}" >> "$outFile"
	else
		echo "NO MATCH"
	fi
	
fi


