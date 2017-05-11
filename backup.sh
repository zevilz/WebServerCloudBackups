#!/bin/bash
# 
# Web Server Cloud Backups
# Author: zEvilz
# License: MIT
# 

CUR_PATH=$(dirname $0)
. $CUR_PATH"/backup.conf"

if [ "Z$(ps o comm="" -p $(ps o ppid="" -p $$))" == "Zcron" -o \
     "Z$(ps o comm="" -p $(ps o ppid="" -p $(ps o ppid="" -p $$)))" == "Zcron" ]
then
	red=
	green=
	reset=
else
	red=$(tput setf 4)
	green=$(tput setf 2)
	reset=$(tput sgr0)
fi

if [[ $# -eq 2 && $1 == "files" || $# -eq 2 && $1 == "bases" ]]
then
	if [[ $2 == "daily" || $2 == "weekly" || $2 == "monthly" ]]
	then
		# period time postfix
		if [ $2 == "daily" ]
		then
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

			# files backup
			if [[ $PROJECT_FOLDER != "false" && $1 == "files" ]]
			then
				echo "# "$PROJECT_NAME" files backup"
				ARCHIVE_PATH=$TMP_PATH""$PROJECT_NAME"_files_"$PERIOD".7z"
				# archiving
				echo -n "Archiving..."

				if [ -d $PROJECT_FOLDER ]
				then
					if [ $PROJECT_ARCHIVE_PASS != "false" ]
					then
						7z a -mx7 -mhe=on -p$PROJECT_ARCHIVE_PASS $ARCHIVE_PATH $PROJECT_FOLDER > /dev/null
					elif [ $GLOBAL_ARCHIVE_PASS != "false" ]
					then
						7z a -mx7 -mhe=on -p$GLOBAL_ARCHIVE_PASS $ARCHIVE_PATH $PROJECT_FOLDER > /dev/null
					else
						7z a -mx7 $ARCHIVE_PATH $PROJECT_FOLDER > /dev/null
					fi
					if [ -f $ARCHIVE_PATH ]
					then
						echo -n "${green}[OK]"
						ARCHIVE=1
					else
						echo -n "${red}[fail]"
						ARCHIVE=0
					fi
					echo -n "${reset}"
					echo

					if [ $ARCHIVE == 1 ]
					then
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
			if [[ $PROJECT_DB != "false" && $1 == "bases" ]]
			then
				echo "# "$PROJECT_NAME" database backup"
				MYSQL_DUMP_PATH=$TMP_PATH""$PROJECT_NAME"_base_"$PERIOD".sql"
				ARCHIVE_PATH=$TMP_PATH""$PROJECT_NAME"_base_"$PERIOD".7z"

				# base dump
				echo -n "Dump creation..."
				mysqldump -u root --password=$MYSQL_PASS --databases $PROJECT_DB > $MYSQL_DUMP_PATH
				if [ $? == 0 ]
				then
					echo -n "${green}[OK]"
					DUMP=1
				else
					echo -n "${red}[fail]"
					DUMP=0
				fi
				echo -n "${reset}"
				echo

				if [ $DUMP == 1 ]
				then
					# archiving
					echo -n "Archiving..."
					if [ $PROJECT_ARCHIVE_PASS != "false" ]
					then
						7z a -mx7 -mhe=on -p$PROJECT_ARCHIVE_PASS $ARCHIVE_PATH $MYSQL_DUMP_PATH > /dev/null
					elif [ $GLOBAL_ARCHIVE_PASS != "false" ]
					then
						7z a -mx7 -mhe=on -p$GLOBAL_ARCHIVE_PASS $ARCHIVE_PATH $MYSQL_DUMP_PATH > /dev/null
					else
						7z a -mx7 $ARCHIVE_PATH $MYSQL_DUMP_PATH > /dev/null
					fi
					if [ -f $ARCHIVE_PATH ]
					then
						echo -n "${green}[OK]"
						ARCHIVE=1
					else
						echo -n "${red}[fail]"
						ARCHIVE=0
					fi
					echo -n "${reset}"
					echo

					if [ $ARCHIVE == 1 ]
					then
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
					fi
				fi

				# cleanup
				unlink $MYSQL_DUMP_PATH
				echo
			fi

		done
	else
		echo "usage : $0 files|bases daily|weekly|monthly"
	fi
else
	echo "usage : $0 files|bases daily|weekly|monthly"
fi
