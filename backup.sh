#!/bin/bash
# Web Server Cloud Backups Main Script
# URL: https://github.com/zevilz/WebServerCloudBackups
# Author: zEvilz
# License: MIT
# Version: 1.10.1

checkFilePermissions()
{
	if [ -w "$1" ] && ! [ -f "$1" ] || ! [ -f "$1" ] && ! [ -w "$(dirname $1)" ] || [ -f "$1" ] && ! [ -w "$1" ] || ! [ -d "$(dirname $1)" ] || [ -d "$1" ]; then
		echo "Can't write into $1 or it not a file!"
		exit 1
	fi
}

pushToLog()
{
	if [ -n "$SCRIPT_LOG_PATH" ]; then
		if [[ $# -eq 1 ]]; then
			echo -e "[$(date +%Y-%m-%d\ %H:%M:%S)] WebServerCloudBackups: $1" >> "$SCRIPT_LOG_PATH"
		fi

		if [ -f "$SCRIPT_ERRORS_TMP" ]; then
			cat "$SCRIPT_ERRORS_TMP" >> "$SCRIPT_LOG_PATH"
			rm "$SCRIPT_ERRORS_TMP"
		fi
	fi
}

CUR_PATH=$(dirname "$0")
SCRIPT_LOG_PATH=
SORT_BACKUPS=
CLOUD_SUBDIR_FILES=
CLOUD_SUBDIR_BASES=
SCRIPT_INSTANCE_KEY=$(tr -cd 'a-zA-Z0-9' < /dev/urandom | head -c 10)
SCRIPT_ERRORS_TMP="/tmp/wscb.tmp.${SCRIPT_INSTANCE_KEY}"
MYSQLDUMP="mysqldump"

. "${CUR_PATH}/backup.conf"

if [ "Z$(ps o comm="" -p $(ps o ppid="" -p $$))" == "Zcron" -o \
     "Z$(ps o comm="" -p $(ps o ppid="" -p $(ps o ppid="" -p $$)))" == "Zcron" ]; then
	SETCOLOR_SUCCESS=
	SETCOLOR_FAILURE=
	SETCOLOR_NORMAL=
	SETCOLOR_GREY=
	BOLD_TEXT=
	NORMAL_TEXT=
else
	SETCOLOR_SUCCESS="echo -en \\033[1;32m"
	SETCOLOR_FAILURE="echo -en \\033[1;31m"
	SETCOLOR_NORMAL="echo -en \\033[0;39m"
	SETCOLOR_GREY="echo -en \\033[0;2m"
	BOLD_TEXT=$(tput bold)
	NORMAL_TEXT=$(tput sgr0)
fi

if [ -n "$SCRIPT_LOG_PATH" ]; then
	checkFilePermissions "$SCRIPT_LOG_PATH"
fi

if [[ $# -lt 2 ]]; then
	pushToLog "[ERROR] - Wrong number of parameters"

	$SETCOLOR_FAILURE
	echo "Wrong number of parameters!"
	$SETCOLOR_NORMAL
	echo "Usage: bash $0 files|bases hourly|daily|daily_week|daily_month|weekly|monthly 0|1|3|5|7|9(optional) webdav|s3|ssh(optional)"

	exit 1
fi

if [[ $1 != "files" && $1 != "bases" ]]; then
	pushToLog "[ERROR] - Wrong backup type set"

	$SETCOLOR_FAILURE
	echo "Wrong backup type set!"
	$SETCOLOR_NORMAL
	echo "Type must be set to \"files\" or \"bases\""

	exit 1
fi

if [[ $2 != "hourly" && $2 != "daily" && $2 != "daily_week" && $2 != "daily_month" && $2 != "weekly" && $2 != "monthly" ]]; then
	pushToLog "[ERROR] - Wrong period set"

	$SETCOLOR_FAILURE
	echo "Wrong period set!"
	$SETCOLOR_NORMAL
	echo "Period must be set to \"hourly\" or \"daily\" or \"daily_week\" or \"daily_month\" or \"weekly\" or \"monthly\""

	exit 1
fi

if [ -n "$3" ]; then
	if [[ $3 != 0 && $3 != 1 && $3 != 3 && $3 != 5 && $3 != 7 && $3 != 9 ]]; then
		pushToLog "[ERROR] - Wrong compression ratio set"

		$SETCOLOR_FAILURE
		echo "Wrong compression ratio set!"
		$SETCOLOR_NORMAL
		echo "Compression ratio must be set to 0|1|3|5|7|9 (5 by default)"

		exit 1
	else
		COMPRESS_RATIO="$3"
	fi
else
	COMPRESS_RATIO=5
fi

if [ -n "$4" ]; then
	if [[ $4 != "webdav" && $4 != "s3" && $4 != "ssh" ]]; then
		pushToLog "[ERROR] - Wrong protocol set"

		$SETCOLOR_FAILURE
		echo "Wrong protocol set!"
		$SETCOLOR_NORMAL
		echo "Protocol must be set to webdav|s3|ssh (all protocols enabled by default)"

		exit 1
	else
		ENABLED_PROTO="$4"
	fi
else
	ENABLED_PROTO="all"
fi

if [ -z "$CLOUD_PROTO" ]; then
	CLOUD_PROTO="webdav"
fi

if [[ "$CLOUD_PROTO" != "webdav" && "$CLOUD_PROTO" != "s3" && "$CLOUD_PROTO" != "ssh" ]]; then
	pushToLog "[ERROR] - Wrong cloud protocol given"

	$SETCOLOR_FAILURE
	echo "Wrong cloud protocol given!"
	$SETCOLOR_NORMAL
	echo "Protocol must be set to webdav, s3 or ssh (webdav by default)"

	exit 1
fi

# period time postfix
if [[ $2 == "hourly" ]]; then
	PERIOD="$2"_$(date +"%H")
elif [[ $2 == "daily" ]]; then
	PERIOD=$(date +"%u")_$(date +"%A")
elif [[ $2 == "daily_week" ]]; then
	PERIOD="$2"_$(date +"%u")
elif [[ $2 == "daily_month" ]]; then
	PERIOD="$2"_$(date +"%d")
else
	PERIOD="$2"
fi

# get cloud ssh port if exists
if [ -n "$CLOUD_SSH_HOST" ]; then
	if [[ $CLOUD_SSH_HOST == *:* ]]; then
		CLOUD_SSH_HOST_PORT=$(echo "$CLOUD_SSH_HOST" | awk -F ':' '{print $2}')
		CLOUD_SSH_HOST=$(echo "$CLOUD_SSH_HOST" | awk -F ':' '{print $1}')
	else
		CLOUD_SSH_HOST_PORT=22
	fi
fi

SCRIPT_INSTANCE_KEY=$(tr -cd 'a-zA-Z0-9' < /dev/urandom | head -c 10)
RSYNC_EXCLUDE_LIST_FILE="${TMP_PATH}/WebServerCloudBackups.tmp.rsync_exclude.${SCRIPT_INSTANCE_KEY}"

if [[ "$SORT_BACKUPS" == "true" ]]; then
	CLOUD_SUBDIR_FILES="/files"
	CLOUD_SUBDIR_BASES="/databases"
fi

if command -v mariadb-dump >/dev/null 2>&1; then
	MYSQLDUMP="mariadb-dump"
fi

# projects loop
for i in "${!projects[@]}"
do
	# get project name
	PROJECT_NAME=$(echo "${projects[$i]}" | cut -f 1 -d ' ')

	# get project proto
	case "$PROJECT_NAME" in
		*:webdav)
			CLOUD_PROTO_PROJECT=webdav
			;;
		*:s3)
			CLOUD_PROTO_PROJECT=s3
			;;
		*:ssh)
			CLOUD_PROTO_PROJECT=ssh
			;;
		*)
			CLOUD_PROTO_PROJECT=$CLOUD_PROTO
			;;
	esac

	PROJECT_NAME=$(echo "$PROJECT_NAME" | awk -F ':' '{print $1}')

	# get other vars
	PROJECT_DB=$(echo "${projects[$i]}" | cut -f 2 -d ' ')
	PROJECT_FOLDER=$(echo "${projects[$i]}" | cut -f 3 -d ' ' | sed "s/\/$//g")
	PROJECT_ARCHIVE_PASS=$(echo "${projects[$i]}" | cut -f 4 -d ' ')
	PROJECT_CLOUD_PATH=$(echo "$CLOUD_PATH" | sed "s/\/$//g")"/${PROJECT_NAME}"

	if [[ $PROJECT_ARCHIVE_PASS != "false" ]]; then
		ARCHIVE_PASS=" -p${PROJECT_ARCHIVE_PASS}"
	elif [[ $GLOBAL_ARCHIVE_PASS != "false" ]]; then
		ARCHIVE_PASS=" -p${GLOBAL_ARCHIVE_PASS}"
	else
		ARCHIVE_PASS=""
	fi

	if [[ $SPLIT != "false" ]]; then
		SPLIT_7Z=" -v${SPLIT}"
	else
		SPLIT_7Z=""
	fi

	if [ -z "$LAST_BACKUPS_PATH" ]; then
		LAST_BACKUPS_PATH="${CUR_PATH}/last_backups"
	else
		LAST_BACKUPS_PATH=$(echo "$LAST_BACKUPS_PATH" | sed "s/\/$//g")
	fi

	# create dir for last backups listings if not exists
	if ! [ -d "${LAST_BACKUPS_PATH}" ]; then
		mkdir "$LAST_BACKUPS_PATH"
	fi

	# files backup
	if [[ $PROJECT_FOLDER != "false" && $1 == "files" ]]; then
		SKIP=0

		# get project cloud proto for project files
		case "$PROJECT_FOLDER" in
			*:webdav)
				CLOUD_PROTO_PROJECT_FILES=webdav
				;;
			*:s3)
				CLOUD_PROTO_PROJECT_FILES=s3
				;;
			*:ssh)
				CLOUD_PROTO_PROJECT_FILES=ssh
				;;
			*)
				CLOUD_PROTO_PROJECT_FILES=$CLOUD_PROTO_PROJECT
				;;
		esac

		if [[ $ENABLED_PROTO != "all" && $ENABLED_PROTO != "$CLOUD_PROTO_PROJECT_FILES" ]]; then
			SKIP=1
		fi

		if [ $SKIP -eq 0 ]; then
			# remove proto
			PROJECT_FOLDER=$(echo "$PROJECT_FOLDER" | awk -F ':' '{print $1}')

			echo "${BOLD_TEXT}# $PROJECT_NAME files backup${NORMAL_TEXT}"

			pushToLog "[NOTICE] - $PROJECT_NAME files backup (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"

			if [ -d "$PROJECT_FOLDER" ]; then
				if [[ $CLOUD_PROTO_PROJECT_FILES == "webdav" || $CLOUD_PROTO_PROJECT_FILES == "s3" ]]; then
					CLOUD_CHECK_FAIL=0

					# check/create project folder in cloud (webdav)
					if [[ $CLOUD_PROTO == "webdav" ]]; then
						echo -n "Checking cloud..."

						CHECK_FILE=$(echo "$TMP_PATH" | sed "s/\/$//g")"/check_folder_in_cloud"

						touch "$CHECK_FILE"

						CLOUD_FOLDER_CHECK=$(curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -T "$CHECK_FILE" "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/" 2>&1 >/dev/null)

						if [ -n "$CLOUD_FOLDER_CHECK" ]; then
							curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X MKCOL "$PROJECT_CLOUD_PATH" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Can't create directory for $PROJECT_NAME files in cloud (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD}; cloud path: ${PROJECT_CLOUD_PATH})"; CLOUD_CHECK_FAIL=1; }

							if [[ "$SORT_BACKUPS" == "true" ]]; then
								curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X MKCOL "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Can't create subdirectory for $PROJECT_NAME files in cloud (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD}; cloud path: ${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES})"; CLOUD_CHECK_FAIL=1; }
							fi
						else
							curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X DELETE "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/check_folder_in_cloud" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Can't remove check file for $PROJECT_NAME files in cloud (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD}; check file cloud path: ${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/check_folder_in_cloud)"; CLOUD_CHECK_FAIL=1; }
						fi

						rm "$CHECK_FILE"

						if [ "$CLOUD_CHECK_FAIL" -eq 0 ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL
						else
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL
						fi
					fi

					if [ "$CLOUD_CHECK_FAIL" -eq 0 ]; then
						# get last backup files list
						if [[ -f "${LAST_BACKUPS_PATH}/${PROJECT_NAME}_files_${PERIOD}" ]]; then
							LAST_BACKUP_FILES=$(cat "${LAST_BACKUPS_PATH}/${PROJECT_NAME}_files_${PERIOD}")
						else
							LAST_BACKUP_FILES=
						fi

						# archiving

						ARCHIVE_PATH=$(echo "$TMP_PATH" | sed "s/\/$//g")/"${PROJECT_NAME}_files_${PERIOD}.7z"

						echo -n "Archiving..."

						EXCLUDE_7Z=""
						EXCLUDE_RELATIVE_7Z=""

						# exclude folders
						if [ -n "$EXCLUDE" ]; then
							EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo "$EXCLUDE" | sed 's/\ /\ -xr!/g')
						fi

						if [ -n "$EXCLUDE_RELATIVE" ]; then
							EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo "$EXCLUDE_RELATIVE" | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
						fi

						# hourly exclude folders
						if [[ $2 == 'hourly' ]]; then
							if [ -n "$HOURLY_EXCLUDE" ]; then
								EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo "$HOURLY_EXCLUDE" | sed 's/\ /\ -xr!/g')
							fi

							if [ -n "$HOURLY_EXCLUDE_RELATIVE" ]; then
								EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo "$HOURLY_EXCLUDE_RELATIVE" | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
							fi
						fi

						# daily exclude folders
						if [[ $2 == 'daily' ]]; then
							if [ -n "$DAILY_EXCLUDE" ]; then
								EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo "$DAILY_EXCLUDE" | sed 's/\ /\ -xr!/g')
							fi

							if [ -n "$DAILY_EXCLUDE_RELATIVE" ]; then
								EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo "$DAILY_EXCLUDE_RELATIVE" | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
							fi
						fi

						# weekly exclude folders
						if [[ $2 == 'weekly' ]]; then
							if [ -n "$WEEKLY_EXCLUDE" ]; then
								EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo "$WEEKLY_EXCLUDE" | sed 's/\ /\ -xr!/g')
							fi

							if [ -n "$WEEKLY_EXCLUDE_RELATIVE" ]; then
								EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo "$WEEKLY_EXCLUDE_RELATIVE" | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
							fi
						fi

						# monthly exclude folders
						if [[ $2 == 'monthly' ]]; then
							if [ -n "$MONTHLY_EXCLUDE" ]; then
								EXCLUDE_7Z="$EXCLUDE_7Z -xr!"$(echo "$MONTHLY_EXCLUDE" | sed 's/\ /\ -xr!/g')
							fi

							if [ -n "$MONTHLY_EXCLUDE_RELATIVE" ]; then
								EXCLUDE_RELATIVE_7Z="$EXCLUDE_RELATIVE_7Z -x!$(basename "$PROJECT_FOLDER")/"$(echo "$MONTHLY_EXCLUDE_RELATIVE" | sed "s/\ /\ -x!$(basename "$PROJECT_FOLDER")\//g")
							fi
						fi

						ARCHIVING_FAIL=0

						7z a -mx$COMPRESS_RATIO -mhe=on $SPLIT_7Z $ARCHIVE_PASS "$ARCHIVE_PATH" "$PROJECT_FOLDER" $EXCLUDE_7Z $EXCLUDE_RELATIVE_7Z > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while creating $PROJECT_NAME files archive (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"; ARCHIVING_FAIL=1; }

						# remove part postfix if only one part
						if [[ $(ls "$ARCHIVE_PATH".* 2>/dev/null | wc -l) -eq 1 ]]; then
							mv "${ARCHIVE_PATH}.001" "$ARCHIVE_PATH"
						fi

						if [ "$ARCHIVING_FAIL" -eq 1 ]; then
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL

							ARCHIVE=0
						elif [ -f "$ARCHIVE_PATH" ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL

							ARCHIVE=1
						elif [ -f "${ARCHIVE_PATH}.001" ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL

							ARCHIVE=1
						else
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL

							ARCHIVE=0
						fi

						if [ "$ARCHIVE" -eq 1 ]; then
							# remove old files from cloud
							if [ -n "$LAST_BACKUP_FILES" ]; then
								if [[ $CLOUD_PROTO_PROJECT_FILES == "webdav" ]] || [[ $CLOUD_PROTO_PROJECT_FILES == "s3" ]]; then
									echo -n "Removing old archives from cloud..."

									CLOUD_OLD_ARCHIVES_REMOVE_FAIL=0

									if [[ $CLOUD_PROTO_PROJECT_FILES == "webdav" ]]; then
										curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X DELETE "$LAST_BACKUP_FILES" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[WARNING] - Can't remove $PROJECT_NAME old files archives (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"; CLOUD_OLD_ARCHIVES_REMOVE_FAIL=1; }
									elif [[ $CLOUD_PROTO_PROJECT_FILES == "s3" ]]; then
										LAST_BACKUP_FILES=$(echo "$LAST_BACKUP_FILES" | sed 's/,/ /g')

										for FILE in $LAST_BACKUP_FILES; do
											s3cmd rm "$FILE" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[WARNING] - Can't remove $PROJECT_NAME old files archive (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD}; filename: ${FILE})"; CLOUD_OLD_ARCHIVES_REMOVE_FAIL=1; }
										done
									fi

									if [ "$CLOUD_OLD_ARCHIVES_REMOVE_FAIL" -eq 0 ]; then
										$SETCOLOR_SUCCESS
										echo "[OK]"
										$SETCOLOR_NORMAL
									else
										$SETCOLOR_FAILURE
										echo "[FAIL]"
										$SETCOLOR_NORMAL
									fi
								fi
							fi

							# upload new files to cloud
							echo -n "Uploading via ${CLOUD_PROTO_PROJECT_FILES}..."

							UPLOAD_FAIL=0

							if [[ $CLOUD_PROTO_PROJECT_FILES == "webdav" ]]; then
								curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -T "{$(ls $ARCHIVE_PATH* | tr '\n' ',' | sed 's/,$//g')}" "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while uploading $PROJECT_NAME files archive (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"; UPLOAD_FAIL=1; }
							elif [[ $CLOUD_PROTO_PROJECT_FILES == "s3" ]]; then
								s3cmd put $(ls "$ARCHIVE_PATH"* | tr '\n' ' ') "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while uploading $PROJECT_NAME files archive (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"; UPLOAD_FAIL=1; }
							fi

							if [ "$UPLOAD_FAIL" -eq 0 ]; then
								$SETCOLOR_SUCCESS
								echo "[OK]"
								$SETCOLOR_NORMAL

								NEW_BACKUP_FILES="${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/"$(ls "$ARCHIVE_PATH"* | sed 's/.*\///g' | tr '\n' ',' | sed 's/,$//g' | sed "s|,|,${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_FILES}/|g")

								echo "$NEW_BACKUP_FILES" > "${LAST_BACKUPS_PATH}/${PROJECT_NAME}_files_${PERIOD}"
							else
								$SETCOLOR_FAILURE
								echo "[FAIL]"
								$SETCOLOR_NORMAL
							fi
						fi

						# cleanup
						rm "$ARCHIVE_PATH"* > /dev/null 2>/dev/null
					fi
				fi

				if [[ $CLOUD_PROTO_PROJECT_FILES == "ssh" ]]; then
					if [ -n "$CLOUD_SSH_HOST" ] && [ -n "$CLOUD_SSH_HOST_USER" ]; then
						CLOUD_SSH_PROJECT_PATH=$(echo "$CLOUD_SSH_HOST_PATH" | sed "s/\/$//g")"/${PROJECT_NAME}"
						CLOUD_SSH_PROJECT_BACKUP_PATH="${CLOUD_SSH_PROJECT_PATH}${CLOUD_SUBDIR_FILES}/${PROJECT_NAME}_files_${PERIOD}"

						RSYNC_EXCLUDE_LIST=""

						# exclude folders
						if [ -n "$EXCLUDE" ]; then
							RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $EXCLUDE"
						fi

						if [ -n "$EXCLUDE_RELATIVE" ]; then
							RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $EXCLUDE_RELATIVE"
						fi

						# hourly exclude folders
						if [[ $2 == 'hourly' ]]; then
							if [ -n "$HOURLY_EXCLUDE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $HOURLY_EXCLUDE"
							fi

							if [ -n "$HOURLY_EXCLUDE_RELATIVE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $HOURLY_EXCLUDE_RELATIVE"
							fi
						fi

						# daily exclude folders
						if [[ $2 == 'daily' ]]; then
							if [ -n "$DAILY_EXCLUDE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $DAILY_EXCLUDE"
							fi

							if [ -n "$DAILY_EXCLUDE_RELATIVE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $DAILY_EXCLUDE_RELATIVE"
							fi
						fi

						# weekly exclude folders
						if [[ $2 == 'weekly' ]]; then
							if [ -n "$WEEKLY_EXCLUDE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $WEEKLY_EXCLUDE"
							fi

							if [ -n "$WEEKLY_EXCLUDE_RELATIVE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $WEEKLY_EXCLUDE_RELATIVE"
							fi
						fi

						# monthly exclude folders
						if [[ $2 == 'monthly' ]]; then
							if [ -n "$MONTHLY_EXCLUDE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $MONTHLY_EXCLUDE"
							fi

							if [ -n "$MONTHLY_EXCLUDE_RELATIVE" ]; then
								RSYNC_EXCLUDE_LIST="$RSYNC_EXCLUDE_LIST $MONTHLY_EXCLUDE_RELATIVE"
							fi
						fi

						# prepare exclude list file
						RSYNC_EXCLUDE_ARRAY=($RSYNC_EXCLUDE_LIST)

						printf "%s\n" "${RSYNC_EXCLUDE_ARRAY[@]}" > "$RSYNC_EXCLUDE_LIST_FILE"

						echo -n "Uploading via ssh..."

						UPLOAD_FAIL=0

						ssh -p "$CLOUD_SSH_HOST_PORT" -o batchmode=yes -o StrictHostKeyChecking=no "${CLOUD_SSH_HOST_USER}@${CLOUD_SSH_HOST}" "mkdir -p ${CLOUD_SSH_PROJECT_PATH}${CLOUD_SUBDIR_FILES}" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while creating directory for $PROJECT_NAME files (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"; UPLOAD_FAIL=1; }

						rsync -azq -e "ssh -p $CLOUD_SSH_HOST_PORT -o batchmode=yes -o StrictHostKeyChecking=no" --exclude-from="$RSYNC_EXCLUDE_LIST_FILE" --delete --ignore-missing-args "$PROJECT_FOLDER" "${CLOUD_SSH_HOST_USER}@${CLOUD_SSH_HOST}:${CLOUD_SSH_PROJECT_BACKUP_PATH}/" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while uploading $PROJECT_NAME files (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"; UPLOAD_FAIL=1; }

						if [ "$UPLOAD_FAIL" -eq 0 ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL
						else
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL
						fi

						rm -f "$RSYNC_EXCLUDE_LIST_FILE"
					else
						pushToLog "[ERROR] - Project $PROJECT_NAME files proto is ssh, but CLOUD_HOST not defined (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"

						$SETCOLOR_FAILURE
						echo "Project files proto is ssh, but CLOUD_HOST not defined!"
						$SETCOLOR_NORMAL
					fi
				fi
			else
				pushToLog "[ERROR] - Project $PROJECT_NAME folder not found (proto: ${CLOUD_PROTO_PROJECT_FILES}; period: ${PERIOD})"

				$SETCOLOR_FAILURE
				echo "Project folder not found!"
				$SETCOLOR_NORMAL
			fi

			echo
		fi
	fi

	# bases backup
	if [[ $PROJECT_DB != "false" && $1 == "bases" ]]; then
		SKIP=0

		# get project cloud proto for project database
		case "$PROJECT_DB" in
			*:webdav)
				CLOUD_PROTO_PROJECT_DB=webdav
				;;
			*:s3)
				CLOUD_PROTO_PROJECT_DB=s3
				;;
			*:ssh)
				CLOUD_PROTO_PROJECT_DB=ssh
				;;
			*)
				CLOUD_PROTO_PROJECT_DB=$CLOUD_PROTO_PROJECT
				;;
		esac

		if [[ $ENABLED_PROTO != "all" && $ENABLED_PROTO != "$CLOUD_PROTO_PROJECT_DB" ]]; then
			SKIP=1
		fi

		if [ $SKIP -eq 0 ]; then
			# remove proto
			PROJECT_DB=$(echo "$PROJECT_DB" | awk -F ':' '{print $1}')

			echo "${BOLD_TEXT}# $PROJECT_NAME database backup${NORMAL_TEXT}"

			pushToLog "[NOTICE] - $PROJECT_NAME database backup (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"

			MYSQL_DUMP_PATH=$(echo "$TMP_PATH" | sed "s/\/$//g")/"${PROJECT_NAME}_base_${PERIOD}.sql.gz"

			# base dumping
			echo -n "Creating database dump..."

			DUMP_SINGLE_TRANSACTION_FAIL=0

			$MYSQLDUMP --insert-ignore --skip-lock-tables --single-transaction=TRUE --add-drop-table --no-tablespaces -u "$MYSQL_USER" --password="$MYSQL_PASS" "$PROJECT_DB" 2>"$SCRIPT_ERRORS_TMP" | gzip > "$MYSQL_DUMP_PATH"

			DUMP_ERRORS=$(cat "$SCRIPT_ERRORS_TMP" 2>/dev/null | grep -v 'Using a password' 2>&1)
			DUMP_ERRORS=$(echo "$DUMP_ERRORS" | grep -v 'Forcing protocol to' 2>&1)

			DUMP_SINGLE_TRANSACTION_CHECK=$(echo "$DUMP_ERRORS" | grep "Table definition has changed")

			if [ -z "$DUMP_ERRORS" ]; then
				$SETCOLOR_SUCCESS
				echo "[OK]"
				$SETCOLOR_NORMAL

				DUMP=1
			elif [ -n "$DUMP_SINGLE_TRANSACTION_CHECK" ]; then
				$SETCOLOR_FAILURE
				echo "[FAIL]"
				$SETCOLOR_NORMAL

				DUMP=0
				DUMP_SINGLE_TRANSACTION_FAIL=1

				pushToLog "[WARNING] - Can't create project $PROJECT_NAME database dump with enabled --single-transaction, will be trying with disabled (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"
			else
				$SETCOLOR_FAILURE
				echo "[FAIL]"
				$SETCOLOR_NORMAL

				DUMP=0

				pushToLog "[ERROR] - Can't create project $PROJECT_NAME database dump (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"
			fi

			if [ "$DUMP_SINGLE_TRANSACTION_FAIL" -eq 1 ]; then
				echo -n "Creating database dump (disabled --single-transaction)..."

				$MYSQLDUMP --insert-ignore --skip-lock-tables --add-drop-table --no-tablespaces -u "$MYSQL_USER" --password="$MYSQL_PASS" "$PROJECT_DB" 2>"$SCRIPT_ERRORS_TMP" | gzip > "$MYSQL_DUMP_PATH"

				DUMP_ERRORS=$(cat "$SCRIPT_ERRORS_TMP" 2>/dev/null | grep -v 'Using a password' 2>&1)
				DUMP_ERRORS=$(echo "$DUMP_ERRORS" | grep -v 'Forcing protocol to' 2>&1)

				if [ -z "$DUMP_ERRORS" ]; then
					$SETCOLOR_SUCCESS
					echo "[OK]"
					$SETCOLOR_NORMAL

					DUMP=1
				else
					$SETCOLOR_FAILURE
					echo "[FAIL]"
					$SETCOLOR_NORMAL

					DUMP=0

					pushToLog "[ERROR] - Can't create project $PROJECT_NAME database dump (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"
				fi
			fi

			if [ "$DUMP" -eq 1 ]; then
				if [[ $CLOUD_PROTO_PROJECT_DB == "webdav" || $CLOUD_PROTO_PROJECT_DB == "s3" ]]; then
					CLOUD_CHECK_FAIL=0

					# check/create project folder in cloud (webdav)
					if [[ $CLOUD_PROTO == "webdav" ]]; then
						echo -n "Checking cloud..."

						CHECK_FILE=$(echo "$TMP_PATH" | sed "s/\/$//g")"/check_folder_in_cloud"

						touch "$CHECK_FILE"

						CLOUD_FOLDER_CHECK=$(curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -T "$CHECK_FILE" "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}/" 2>&1 >/dev/null)

						if [ -n "$CLOUD_FOLDER_CHECK" ]; then
							curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X MKCOL "$PROJECT_CLOUD_PATH" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Can't create directory for $PROJECT_NAME databases in cloud (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD}; cloud path: ${PROJECT_CLOUD_PATH})"; CLOUD_CHECK_FAIL=1; }

							if [[ "$SORT_BACKUPS" == "true" ]]; then
								curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X MKCOL "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Can't create subdirectory for $PROJECT_NAME databases in cloud (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD}; cloud path: ${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES})"; CLOUD_CHECK_FAIL=1; }
							fi
						else
							curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X DELETE "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}/check_folder_in_cloud" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Can't remove check file for $PROJECT_NAME databases in cloud (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD}; check file cloud path: ${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}/check_folder_in_cloud)"; CLOUD_CHECK_FAIL=1; }
						fi

						rm "$CHECK_FILE"

						if [ "$CLOUD_CHECK_FAIL" -eq 0 ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL
						else
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL
						fi
					fi

					if [ "$CLOUD_CHECK_FAIL" -eq 0 ]; then
						# get last backup files list
						if [ -f "${LAST_BACKUPS_PATH}/${PROJECT_NAME}_base_${PERIOD}" ]; then
							LAST_BACKUP_FILES=$(cat "${LAST_BACKUPS_PATH}/${PROJECT_NAME}_base_${PERIOD}")
						else
							LAST_BACKUP_FILES=
						fi

						ARCHIVE_PATH=$(echo "$TMP_PATH" | sed "s/\/$//g")"/${PROJECT_NAME}_base_${PERIOD}.7z"

						# archiving
						echo -n "Archiving..."

						ARCHIVING_FAIL=0

						7z a -mx$COMPRESS_RATIO -mhe=on$SPLIT_7Z$ARCHIVE_PASS "$ARCHIVE_PATH" "$MYSQL_DUMP_PATH" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while creating $PROJECT_NAME database archive (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"; ARCHIVING_FAIL=1; }

						# remove part postfix if only one part
						if [[ $(ls "$ARCHIVE_PATH".* 2>/dev/null | wc -l) -eq 1 ]]; then
							mv "${ARCHIVE_PATH}.001" "$ARCHIVE_PATH"
						fi

						if [ "$ARCHIVING_FAIL" -eq 1 ]; then
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL

							ARCHIVE=0
						elif [ -f "$ARCHIVE_PATH" ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL

							ARCHIVE=1
						elif [ -f "${ARCHIVE_PATH}.001" ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL

							ARCHIVE=1
						else
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL

							ARCHIVE=0
						fi

						if [ "$ARCHIVE" -eq 1 ]; then
							# remove old files from cloud
							if [ -n "$LAST_BACKUP_FILES" ]; then
								if [[ $CLOUD_PROTO_PROJECT_DB == "webdav" ]] || [[ $CLOUD_PROTO_PROJECT_DB == "s3" ]]; then
									echo -n "Removing old archives from cloud..."

									CLOUD_OLD_ARCHIVES_REMOVE_FAIL=0

									if [[ $CLOUD_PROTO_PROJECT_DB == "webdav" ]]; then
										curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -X DELETE "$LAST_BACKUP_FILES" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[WARNING] - Can't remove $PROJECT_NAME old database archives (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"; CLOUD_OLD_ARCHIVES_REMOVE_FAIL=1; }
									elif [[ $CLOUD_PROTO_PROJECT_DB == "s3" ]]; then
										LAST_BACKUP_FILES=$(echo "$LAST_BACKUP_FILES" | sed 's/,/ /g')

										for FILE in $LAST_BACKUP_FILES; do
											s3cmd rm "$FILE" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[WARNING] - Can't remove $PROJECT_NAME old database archive (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD}; filename: ${FILE})"; CLOUD_OLD_ARCHIVES_REMOVE_FAIL=1; }
										done
									fi

									if [ "$CLOUD_OLD_ARCHIVES_REMOVE_FAIL" -eq 0 ]; then
										$SETCOLOR_SUCCESS
										echo "[OK]"
										$SETCOLOR_NORMAL
									else
										$SETCOLOR_FAILURE
										echo "[FAIL]"
										$SETCOLOR_NORMAL
									fi
								fi
							fi

							# upload new files to cloud
							echo -n "Uploading via ${CLOUD_PROTO_PROJECT_DB}..."

							UPLOAD_FAIL=0

							if [[ $CLOUD_PROTO_PROJECT_DB == "webdav" ]]; then
								curl -fsS --user "$CLOUD_USER":"$CLOUD_PASS" -T "{$(ls $ARCHIVE_PATH* | tr '\n' ',' | sed 's/,$//g')}" "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}/" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while uploading $PROJECT_NAME database archive (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"; UPLOAD_FAIL=1; }
							elif [[ $CLOUD_PROTO_PROJECT_DB == "s3" ]]; then
								s3cmd put $(ls "$ARCHIVE_PATH"* | tr '\n' ' ') "${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}/" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while uploading $PROJECT_NAME database archive (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"; UPLOAD_FAIL=1; }
							fi

							if [ "$UPLOAD_FAIL" -eq 0 ]; then
								$SETCOLOR_SUCCESS
								echo "[OK]"
								$SETCOLOR_NORMAL

								NEW_BACKUP_FILES="${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}"/$(ls "$ARCHIVE_PATH"* | sed 's/.*\///g' | tr '\n' ',' | sed 's/,$//g' | sed "s|,|,${PROJECT_CLOUD_PATH}${CLOUD_SUBDIR_BASES}/|g")

								echo "$NEW_BACKUP_FILES" > "${LAST_BACKUPS_PATH}/${PROJECT_NAME}_base_${PERIOD}"
							else
								$SETCOLOR_FAILURE
								echo "[FAIL]"
								$SETCOLOR_NORMAL
							fi

							# cleanup
							rm "$ARCHIVE_PATH"* > /dev/null 2>/dev/null
						fi
					fi
				fi

				if [[ $CLOUD_PROTO_PROJECT_DB == "ssh" ]]; then
					if [ -n "$CLOUD_SSH_HOST" ] && [ -n "$CLOUD_SSH_HOST_USER" ]; then
						CLOUD_SSH_PROJECT_PATH=$(echo "$CLOUD_SSH_HOST_PATH" | sed "s/\/$//g")"/${PROJECT_NAME}"

						echo -n "Uploading via ssh..."

						UPLOAD_FAIL=0

						ssh -p "$CLOUD_SSH_HOST_PORT" -o batchmode=yes -o StrictHostKeyChecking=no "${CLOUD_SSH_HOST_USER}@${CLOUD_SSH_HOST}" "mkdir -p ${CLOUD_SSH_PROJECT_PATH}${CLOUD_SUBDIR_BASES}" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while creating directory for $PROJECT_NAME database archive (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"; UPLOAD_FAIL=1; }

						rsync -azq -e "ssh -p $CLOUD_SSH_HOST_PORT -o batchmode=yes -o StrictHostKeyChecking=no" "$MYSQL_DUMP_PATH" "${CLOUD_SSH_HOST_USER}@${CLOUD_SSH_HOST}:${CLOUD_SSH_PROJECT_PATH}${CLOUD_SUBDIR_BASES}/" > /dev/null 2>"$SCRIPT_ERRORS_TMP" || { pushToLog "[ERROR] - Error occurred while uploading $PROJECT_NAME database archive (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"; UPLOAD_FAIL=1; }

						if [ "$UPLOAD_FAIL" -eq 0 ]; then
							$SETCOLOR_SUCCESS
							echo "[OK]"
							$SETCOLOR_NORMAL
						else
							$SETCOLOR_FAILURE
							echo "[FAIL]"
							$SETCOLOR_NORMAL
						fi
					else
						pushToLog "[ERROR] - Project $PROJECT_NAME database proto is ssh, but CLOUD_HOST not defined (proto: ${CLOUD_PROTO_PROJECT_DB}; period: ${PERIOD})"

						$SETCOLOR_FAILURE
						echo "Project db proto is ssh, but CLOUD_HOST not defined!"
						$SETCOLOR_NORMAL
					fi
				fi
			fi

			# cleanup
			unlink "$MYSQL_DUMP_PATH"

			echo
		fi
	fi
done
