# WebServerCloudBackups
Automatic backups your web projects bases and files to the clouds.

Requirements
------------

- curl
- 7zip archiver (usually **p7zip-rar** **p7zip-full** on deb-based distros)

Configuring
-----------

1. Login server in root user

2. Copy **backup.sh** and **backup.conf** to other directory on your server.

3. Change permissions of **backup.conf** to **600**.

4. Declare main vars in **backup.conf**

- **MYSQL_PASS** - MySQL/MariaDB root password;
- **CLOUD_USER** - login for your cloud;
- **CLOUD_PASS** - password for your cloud user;
- **CLOUD_PATH** - full path to cloud folder (ex.: https://webdav.yandex.ru/Backups/)
- **TMP_PATH** - path for temporary files on server (ex.: /tmp/)
- **GLOBAL_ARCHIVE_PASS** - global password for created archives (if project password set to **false** it will be used this password. if project password set to **false** and this password set to **false** password not set to project archive.)

5. Add your projects after **declare -A projects** one per row like below:

```bash
projects[unique_key]="<project_name> <db_name> <project_folder> <project_archive_password>"
```

Example:

```bash
projects[1]="domain.org false /home/user/www/domain.org false"
projects[2]="domain.com com_db /home/user/www/domain.com 1234"
```

Parameters in quotes must be written through spaces and all required.

Parameters:

- project name (you **must** create folder with same name in the cloud folder, defined in **CLOUD_PATH**)
- database name (type **false** if database backup is not required for project)
- full path to project folder (type **false** if files backup is not required for project)
- project archive password (type **false** if password is not required for project archive or using global password, defined in **GLOBAL_ARCHIVE_PASS**)

Usage
-----

### Directly in shell

    bash backup.sh <backup_type> <period> <compress_ratio>

Compression ratio parameter is opional. It sets to 5 if it not set.

Example:

    bash backup.sh bases daily 7

Supported backup types:

- files - backup projects folder
- bases - backup projects bases

Supported periods:

- daily - add number and name of the current week day to archive name (ex.: domain.com_files_5_Friday.7z)
- weekly - add "weekly" mark to archive name (ex.: domain.com_files_weekly.7z)
- monthly - add "monthly" mark to archive name (ex.: domain.com_files_monthly.7z)

Supported compress ratio:

- 0 - without compression
- 1 - fastest
- 3 - fast
- 5 - normal (default) 
- 7 - maximum
- 9 - ultra

Better compression ratios with big files can lead to fails. if at an archiving there is a fails that it is necessary to lower compression ratio.

### Cron

Add lines in root crontab like below

    0 0 * * * bash /var/scripts/backup.sh bases daily # bases backup every day in 00:00
    20 0 * * 1 bash /var/scripts/backup.sh bases weekly # bases backup every monday in 00:20
    40 0 1 * * bash /var/scripts/backup.sh bases monthly # bases backup every 1st day every month in 00:40
    0 1 * * 1 bash /var/scripts/backup.sh files weekly 7 # files backup every monday in 01:00 with changed compression ratio
    0 4 1 * * bash /var/scripts/backup.sh files monthly 7 # files backup every 1st day every month in 04:00 with changed compression ratio

If you want receive script result to email add below to the top of crontab list (require working MTA on your server)

    MAILTO=name@domain.com

Changelog
---------

- 14.05.2017 - 1.0.2 - add compress ratio parameter
- 13.05.2017 - 1.0.1 - main script code refactoring
- 11.05.2017 - 1.0.0 - released
