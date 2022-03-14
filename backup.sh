#!/bin/bash
# Web Server Cloud Backups Main Script
# URL: https://github.com/zevilz/WebServerCloudBackups
# Author: zEvilz
# License: MIT
# Version: 1.6.0

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
	echo "Usage: bash $0 files|bases hourly|daily|weekly|monthly 0|1|3|5|7|9(optional)"
	exit 1
fi

if [[ $1 != "files" && $1 != "bases" ]]; then
	echo "Wrong type set!"
	echo "Type must be set to \"files\" or \"bases\""
	exit 1
fi

if [[ $2 != "hourly" && $2 != "daily" && $2 != "weekly" && $2 != "monthly" ]]; then
	echo "Wrong period set!"
	echo "Period must be set to \"hourly\" or \"daily\" or \"weekly\" or \"monthly\""
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

if [ -z "$CLOUD_PROTO" ]; then
	CLOUD_PROTO="webdav"
fi

if [[ "$CLOUD_PROTO" != "webdav" && "$CLOUD_PROTO" != "s3" ]]; then
	echo "Wrong cloud protocol given!"
	echo "Protocol must be set to webdav or s3 (webdav by default)"
	exit 1
fi

# period time postfix
if [ $2 == "hourly" ]; then
	PERIOD=$2_$(date +"%H")
elif [ $2 == "daily" ]; then
	PERIOD=$(date +"%u")_$(date +"%A")
else
	PERIOD=$2
fi

# projects loop
for i in "${!projects[@]}"
do
	# vars
	PROJECT_NAME=$(echo ${projects[$i]} | cut -f 1 -d ' ')
	PROJECT_DB=$(echo ${projects[$i]} | cut -f 2 -d ' ')
	PROJECT_FOLDER=$(echo ${projects[$i]} | cut -f 3 -d ' ' | sed "s/\/$//g")
	PROJECT_ARCHIVE_PASS=$(echo ${projects[$i]} | cut -f 4 -d ' ')
	PROJECT_CLOUD_PATH=$(echo $CLOUD_PATH | sed "s/\/$//g")"/$PROJECT_NAME"
	if [ $PROJECT_ARCHIVE_PASS != "false" ]; then
		ARCHIVE_PASS=" -p$PROJECT_ARCHIVE_PASS"
	elif [ $GLOBAL_ARCHIVE_PASS != "false" ]; then
		ARCHIVE_PASS=" -p$GLOBAL_ARCHIVE_PASS"
	else
		ARCHIVE_PASS=""
	fi
	if [ $SPLIT != "false" ]; then
		SPLIT_7Z=" -v$SPLIT"
	else
		SPLIT_7Z=""
	fi
	if [ -z $LAST_BACKUPS_PATH ]; then
		LAST_BACKUPS_PATH=$CUR_PATH"/last_backups"
	else
		LAST_BACKUPS_PATH=$(echo $LAST_BACKUPS_PATH | sed "s/\/$//g")
	fi

	# create dir for last backups listings if not exists
	if ! [ -d $LAST_BACKUPS_PATH ]; then
		mkdir $LAST_BACKUPS_PATH
	fi

	# check/create project folder in cloud (webdav)
	if [[ $CLOUD_PROTO == "webdav" ]]; then
		CHECK_FILE=$(echo $TMP_PATH | sed "s/\/$//g")"/check_folder_in_cloud"
		touch "$CHECK_FILE"
		CLOUD_FOLDER_CHECK=$(curl -fsS --user $CLOUD_USER:$CLOUD_PASS -T "$CHECK_FILE" $PROJECT_CLOUD_PATH"/" 2>&1 >/dev/null)
		if ! [ -z "$CLOUD_FOLDER_CHECK" ]; then
			curl -fsS --user $CLOUD_USER:$CLOUD_PASS -X MKCOL $PROJECT_CLOUD_PATH > /dev/null
		else
			curl -fsS --user $CLOUD_USER:$CLOUD_PASS -X DELETE $PROJECT_CLOUD_PATH"/check_folder_in_cloud" > /dev/null
		fi
		rm "$CHECK_FILE"
	fi

	# files backup
	if [[ $PROJECT_FOLDER != "false" && $1 == "files" ]]; then

		# get last backup files list
		if [[ -f $LAST_BACKUPS_PATH"/"$PROJECT_NAME"_files_"$PERIOD ]]; then
			LAST_BACKUP_FILES=$(cat $LAST_BACKUPS_PATH"/"$PROJECT_NAME"_files_"$PERIOD)
		else
			LAST_BACKUP_FILES=
		fi

		# archiving
		echo "# "$PROJECT_NAME" files backup"
		ARCHIVE_PATH=$(echo $TMP_PATH | sed "s/\/$//g")"/"$PROJECT_NAME"_files_"$PERIOD".7z"
		echo -n "Archiving..."

		if [ -d $PROJECT_FOLDER ]; then

			EXCLUDE_7Z=""
			EXCLUDE_RELATIVE_7Z=""

			# exclude folders
			if ! [ -z "$EXCLUDE" ]; then
				EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo $EXCLUDE | sed 's/\ /\ -xr!/g')
			fi
			if ! [ -z "$EXCLUDE_RELATIVE" ]; then
				EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo $EXCLUDE_RELATIVE | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
			fi

			# hourly exclude folders
			if [[ $2 == 'hourly' ]]; then
				if ! [ -z "$HOURLY_EXCLUDE" ]; then
					EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo $HOURLY_EXCLUDE | sed 's/\ /\ -xr!/g')
				fi
				if ! [ -z "$HOURLY_EXCLUDE_RELATIVE" ]; then
					EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo $HOURLY_EXCLUDE_RELATIVE | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
				fi
			fi

			# daily exclude folders
			if [[ $2 == 'daily' ]]; then
				if ! [ -z "$DAILY_EXCLUDE" ]; then
					EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo $DAILY_EXCLUDE | sed 's/\ /\ -xr!/g')
				fi
				if ! [ -z "$DAILY_EXCLUDE_RELATIVE" ]; then
					EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo $DAILY_EXCLUDE_RELATIVE | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
				fi
			fi

			# weekly exclude folders
			if [[ $2 == 'weekly' ]]; then
				if ! [ -z "$WEEKLY_EXCLUDE" ]; then
					EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo $WEEKLY_EXCLUDE | sed 's/\ /\ -xr!/g')
				fi
				if ! [ -z "$WEEKLY_EXCLUDE_RELATIVE" ]; then
					EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo $WEEKLY_EXCLUDE_RELATIVE | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
				fi
			fi

			# monthly exclude folders
			if [[ $2 == 'monthly' ]]; then
				if ! [ -z "$MONTHLY_EXCLUDE" ]; then
					EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo $MONTHLY_EXCLUDE | sed 's/\ /\ -xr!/g')
				fi
				if ! [ -z "$MONTHLY_EXCLUDE_RELATIVE" ]; then
					EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo $MONTHLY_EXCLUDE_RELATIVE | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
				fi
			fi

			7z a -mx$COMPRESS_RATIO -mhe=on$SPLIT_7Z$ARCHIVE_PASS $ARCHIVE_PATH $PROJECT_FOLDER$EXCLUDE_7Z$EXCLUDE_RELATIVE_7Z > /dev/null

			# remove part postfix if only one part
			if [[ $(ls $ARCHIVE_PATH.* 2>/dev/null | wc -l) -eq 1 ]]; then
				mv $ARCHIVE_PATH".001" $ARCHIVE_PATH
			fi

			if [ -f $ARCHIVE_PATH ]; then
				echo -n "${green}[OK]"
				ARCHIVE=1
			elif [ -f $ARCHIVE_PATH".001" ]; then
				echo -n "${green}[OK]"
				ARCHIVE=1
			else
				echo -n "${red}[fail]"
				ARCHIVE=0
			fi
			echo -n "${reset}"
			echo

			if [ $ARCHIVE == 1 ]; then

				# remove old files from cloud
				if ! [ -z $LAST_BACKUP_FILES ]; then
					if [[ $CLOUD_PROTO == "webdav" ]]; then
						curl -fsS --user $CLOUD_USER:$CLOUD_PASS -X DELETE "{$LAST_BACKUP_FILES}" 2>/dev/null > /dev/null
					elif [[ $CLOUD_PROTO == "s3" ]]; then
						LAST_BACKUP_FILES=$(echo "$LAST_BACKUP_FILES" | sed 's/,/ /g')
						for FILE in $LAST_BACKUP_FILES
						do
							s3cmd rm "$FILE" 2>/dev/null > /dev/null
						done
					fi
				fi

				# upload new files to cloud
				echo -n "Uploading to the cloud..."
				if [[ $CLOUD_PROTO == "webdav" ]]; then
					curl -fsS --user $CLOUD_USER:$CLOUD_PASS -T "{$(ls $ARCHIVE_PATH* | tr '\n' ',' | sed 's/,$//g')}" $PROJECT_CLOUD_PATH"/" > /dev/null
				elif [[ $CLOUD_PROTO == "s3" ]]; then
					s3cmd put $(ls "$ARCHIVE_PATH"* | tr '\n' ' ') $PROJECT_CLOUD_PATH"/" > /dev/null
				fi
				if [ $? == 0 ]; then
					echo -n "${green}[OK]"
					NEW_BACKUP_FILES=$PROJECT_CLOUD_PATH"/"$(ls $ARCHIVE_PATH* | sed 's/.*\///g' | tr '\n' ',' | sed 's/,$//g' | sed "s|,|,$PROJECT_CLOUD_PATH/|g")
					echo $NEW_BACKUP_FILES > $LAST_BACKUPS_PATH"/"$PROJECT_NAME"_files_"$PERIOD
				else
					echo -n "${red}[fail]"
				fi
				echo -n "${reset}"
				echo

				# cleanup
				rm $ARCHIVE_PATH*

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

		# get last backup files list
		if [[ -f $LAST_BACKUPS_PATH"/"$PROJECT_NAME"_base_"$PERIOD ]]; then
			LAST_BACKUP_FILES=$(cat $LAST_BACKUPS_PATH"/"$PROJECT_NAME"_base_"$PERIOD)
		else
			LAST_BACKUP_FILES=
		fi

		echo "# "$PROJECT_NAME" database backup"
		MYSQL_DUMP_PATH=$(echo $TMP_PATH | sed "s/\/$//g")"/"$PROJECT_NAME"_base_"$PERIOD".sql"
		ARCHIVE_PATH=$(echo $TMP_PATH | sed "s/\/$//g")"/"$PROJECT_NAME"_base_"$PERIOD".7z"

		# base dumping
		echo -n "Dump creation..."
		mysqldump -u $MYSQL_USER --password=$MYSQL_PASS --insert-ignore --skip-lock-tables --single-transaction=TRUE $PROJECT_DB > $MYSQL_DUMP_PATH

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
			7z a -mx$COMPRESS_RATIO -mhe=on$SPLIT_7Z$ARCHIVE_PASS $ARCHIVE_PATH $MYSQL_DUMP_PATH > /dev/null

			# remove part postfix if only one part
			if [[ $(ls $ARCHIVE_PATH.* 2>/dev/null | wc -l) -eq 1 ]]; then
				mv $ARCHIVE_PATH".001" $ARCHIVE_PATH
			fi

			if [ -f $ARCHIVE_PATH ]; then
				echo -n "${green}[OK]"
				ARCHIVE=1
			elif [ -f $ARCHIVE_PATH".001" ]; then
				echo -n "${green}[OK]"
				ARCHIVE=1
			else
				echo -n "${red}[fail]"
				ARCHIVE=0
			fi
			echo -n "${reset}"
			echo

			if [ $ARCHIVE == 1 ]; then

				# remove old files from cloud
				if ! [ -z $LAST_BACKUP_FILES ]; then
					if [[ $CLOUD_PROTO == "webdav" ]]; then
						curl -fsS --user $CLOUD_USER:$CLOUD_PASS -X DELETE "{$LAST_BACKUP_FILES}" 2>/dev/null > /dev/null
					elif [[ $CLOUD_PROTO == "s3" ]]; then
						LAST_BACKUP_FILES=$(echo "$LAST_BACKUP_FILES" | sed 's/,/ /g')
						for FILE in $LAST_BACKUP_FILES
						do
							s3cmd rm "$FILE" 2>/dev/null > /dev/null
						done
					fi
				fi

				# upload new files to cloud
				echo -n "Uploading to the cloud..."
				if [[ $CLOUD_PROTO == "webdav" ]]; then
					curl -fsS --user $CLOUD_USER:$CLOUD_PASS -T "{$(ls $ARCHIVE_PATH* | tr '\n' ',' | sed 's/,$//g')}" $PROJECT_CLOUD_PATH"/" > /dev/null
				elif [[ $CLOUD_PROTO == "s3" ]]; then
					s3cmd put $(ls "$ARCHIVE_PATH"* | tr '\n' ' ') $PROJECT_CLOUD_PATH"/" > /dev/null
				fi
				if [ $? == 0 ]
				then
					echo -n "${green}[OK]"
					NEW_BACKUP_FILES=$PROJECT_CLOUD_PATH"/"$(ls $ARCHIVE_PATH* | sed 's/.*\///g' | tr '\n' ',' | sed 's/,$//g' | sed "s|,|,$PROJECT_CLOUD_PATH/|g")
					echo $NEW_BACKUP_FILES > $LAST_BACKUPS_PATH"/"$PROJECT_NAME"_base_"$PERIOD
				else
					echo -n "${red}[fail]"
				fi
				echo -n "${reset}"
				echo

				# cleanup
				rm $ARCHIVE_PATH*
			else
				echo "Try lower compress ratio."
			fi
		fi

		# cleanup
		unlink $MYSQL_DUMP_PATH
		echo

	fi
done
