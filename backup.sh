#!/bin/bash
# Web Server Cloud Backups Main Script
# URL: https://github.com/zevilz/WebServerCloudBackups
# Author: zEvilz
# License: MIT
# Version: 1.1.0

CUR_PATH=$(dirname $0)
. $CUR_PATH"/backup.conf"

if [ "Z$(ps o comm="" -p $(ps o ppid="" -p $$))" == "Zcron" -o \
     "Z$(ps o comm="" -p $(ps o ppid="" -p $(ps o ppid="" -p $$)))" == "Zcron" ]; then
	red=
	green=
	reset=
else
	red=$(tput setf 4)
	green=$(tput setf 2)
	reset=$(tput sgr0)
fi

if [[ ! $# -eq 2 && ! $# -eq 3 ]]; then
	echo "Wrong number of parameters!"
	echo "Usage: bash $0 files|bases daily|weekly|monthly 0|1|3|5|7|9(optional)"
	exit 1
fi
if [[ $1 != "files" && $1 != "bases" ]]; then
	echo "Wrong type set!"
	echo "Type must be set to \"files\" or \"bases\""
	exit 1
fi
if [[ $2 != "daily" && $2 != "weekly" && $2 != "monthly" ]]; then
	echo "Wrong period set!"
	echo "Period must be set to \"daily\" or \"weekly\" or \"monthly\""
	exit 1
fi
if [ $3 ]; then
	if [[ $3 != 0 && $3 != 1 && $3 != 3 && $3 != 5 && $3 != 7 && $3 != 9 ]]; then
		echo "Wrong compression ratio set!"
		echo "Compression ratio must be set to 0|1|3|5|7|9"
		exit 1
	else
		COMPRESS_RATIO=$3
	fi
else
	COMPRESS_RATIO=5
fi

# period time postfix
if [ $2 == "daily" ]; then
	PERIOD=$(date +"%u")_$(date +"%A")
else
	PERIOD=$2
fi

# projects loop
for i in "${!projects[@]}"
do
	# vars
	PROJECT_NAME=`echo ${projects[$i]} | cut -f 1 -d ' '`
	PROJECT_DB=`echo ${projects[$i]} | cut -f 2 -d ' '`
	PROJECT_FOLDER=`echo ${projects[$i]} | cut -f 3 -d ' '`
	PROJECT_ARCHIVE_PASS=`echo ${projects[$i]} | cut -f 4 -d ' '`
	PROJECT_CLOUD_PATH=$CLOUD_PATH$PROJECT_NAME"/"

	if [ $PROJECT_ARCHIVE_PASS != "false" ]; then
		ARCHIVE_PASS=" -p$PROJECT_ARCHIVE_PASS"
	elif [ $GLOBAL_ARCHIVE_PASS != "false" ]; then
		ARCHIVE_PASS=" -p$GLOBAL_ARCHIVE_PASS"
	else
		ARCHIVE_PASS=""
	fi

	# files backup
	if [[ $PROJECT_FOLDER != "false" && $1 == "files" ]]; then

		echo "# "$PROJECT_NAME" files backup"
		ARCHIVE_PATH=$TMP_PATH""$PROJECT_NAME"_files_"$PERIOD".7z"
		# archiving
		echo -n "Archiving..."

		if [ -d $PROJECT_FOLDER ]; then

			if ! [ -z "$EXCLUDE" ]; then
				EXCLUDE_7Z=" -xr!"$(echo $EXCLUDE | sed 's/\ /\ -xr!/g')
			else
				EXCLUDE_7Z=""
			fi
			if ! [ -z "$EXCLUDE_RELATIVE" ]; then
				EXCLUDE_RELATIVE_7Z=" -x!$(basename "$PROJECT_FOLDER")/"$(echo $EXCLUDE_RELATIVE | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
			else
				EXCLUDE_RELATIVE_7Z=""
			fi

			7z a -mx$COMPRESS_RATIO -mhe=on$ARCHIVE_PASS $ARCHIVE_PATH $PROJECT_FOLDER$EXCLUDE_7Z$EXCLUDE_RELATIVE_7Z > /dev/null

			if [ -f $ARCHIVE_PATH ]; then
				echo -n "${green}[OK]"
				ARCHIVE=1
			else
				echo -n "${red}[fail]"
				ARCHIVE=0
			fi
			echo -n "${reset}"
			echo

			if [ $ARCHIVE == 1 ]; then
				# upload to cloud
				echo -n "Uploading to the cloud..."
				curl -fsS --user $CLOUD_USER:$CLOUD_PASS -T $ARCHIVE_PATH $PROJECT_CLOUD_PATH
				if [ $? == 0 ]; then
					echo -n "${green}[OK]"
				else
					echo -n "${red}[fail]"
				fi
				echo -n "${reset}"
				echo

				# cleanup
				unlink $ARCHIVE_PATH
			else
				echo "Try lower compress ratio."
			fi

		else

			echo -n "Project folder not found!"
			echo -n "${red}[fail]"
			echo -n "${reset}"
			echo

		fi
		echo

	fi

	# bases backup
	if [[ $PROJECT_DB != "false" && $1 == "bases" ]]; then

		echo "# "$PROJECT_NAME" database backup"
		MYSQL_DUMP_PATH=$TMP_PATH""$PROJECT_NAME"_base_"$PERIOD".sql"
		ARCHIVE_PATH=$TMP_PATH""$PROJECT_NAME"_base_"$PERIOD".7z"

		# base dump
		echo -n "Dump creation..."
		mysqldump -u root --password=$MYSQL_PASS --databases $PROJECT_DB > $MYSQL_DUMP_PATH

		if [ $? == 0 ]; then
			echo -n "${green}[OK]"
			DUMP=1
		else
			echo -n "${red}[fail]"
			DUMP=0
		fi
		echo -n "${reset}"
		echo

		if [ $DUMP == 1 ]; then
			# archiving
			echo -n "Archiving..."
			7z a -mx$COMPRESS_RATIO -mhe=on$ARCHIVE_PASS $ARCHIVE_PATH $MYSQL_DUMP_PATH > /dev/null

			if [ -f $ARCHIVE_PATH ]; then
				echo -n "${green}[OK]"
				ARCHIVE=1
			else
				echo -n "${red}[fail]"
				ARCHIVE=0
			fi
			echo -n "${reset}"
			echo

			if [ $ARCHIVE == 1 ]; then
				# upload to cloud
				echo -n "Uploading to the cloud..."
				curl -fsS --user $CLOUD_USER:$CLOUD_PASS -T $ARCHIVE_PATH $PROJECT_CLOUD_PATH
				if [ $? == 0 ]
				then
					echo -n "${green}[OK]"
				else
					echo -n "${red}[fail]"
				fi
				echo -n "${reset}"
				echo

				# cleanup
				unlink $ARCHIVE_PATH
			else
				echo "Try lower compress ratio."
			fi
		fi

		# cleanup
		unlink $MYSQL_DUMP_PATH
		echo

	fi
done
