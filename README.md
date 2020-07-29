# WebServerCloudBackups [![Version](https://img.shields.io/badge/version-v1.5.0-brightgreen.svg)](https://github.com/zevilz/WebServerCloudBackups/releases/tag/1.5.0) [![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://www.paypal.me/zevilz)
Automatic backups your web projects bases (MySQL/MariaDB) and files to the clouds via WebDAV or Amazon S3. Supports setting passwords for archives and excluding specified folders.

Requirements
------------

- curl (for WebDAV)
- [s3cmd](https://s3tools.org/s3cmd) (for S3)
- 7zip archiver (usually **p7zip-rar** **p7zip-full** on deb-based distros)

Configuring
-----------

1. Login server in root user

2. Copy **backup.sh** and **backup.conf** to other directory on your server.

3. Change permissions of **backup.conf** to **600**.

4. Declare main vars in **backup.conf**

- **MYSQL_USER** - MySQL/MariaDB user (min user privileges: `EVENT,LOCK TABLES,SELECT,SHOW DATABASES` on all databases);
- **MYSQL_PASS** - MySQL/MariaDB user password;
- **CLOUD_USER** - login for your cloud (for WebDAV);
- **CLOUD_PASS** - password for your cloud user (for WebDAV);
- **CLOUD_PATH** - full path to cloud folder for WebDAV (ex.: `https://webdav.yandex.ru/Backups/`) or path to S3 spacename (ex.: `s3://myspacename`)
- **CLOUD_PROTO** - cloud protocol (`webdav` or `s3`, default value is `webdav` if empty or undefined)
- **TMP_PATH** - path for temporary files on server (ex.: `/tmp/`)
- **GLOBAL_ARCHIVE_PASS** - global password for created archives (if project password set to `false` it will be used this password. if project password set to `false` and this password set to `false` password not set to project archive.)
- **EXCLUDE** - spaces separated folders to exclude (supports wildcard in folders names, ex.: `EXCLUDE=".svn .git *cache*"`)
- **EXCLUDE_RELATIVE** - relative folders paths to exclude separated by spaces (supports wildcard in paths to folders, ex.: `EXCLUDE_RELATIVE="wp-content/cache templates/*_temp"`)
- **\<PERIOD\>_EXCLUDE** - spaces separated folders to exclude for specific backup period (ex.: `DAILY_EXCLUDE="uploads"`)
- **\<PERIOD\>_EXCLUDE_RELATIVE** - relative folders paths to exclude separated by spaces for specific backup period (ex.: `WEEKLY_EXCLUDE_RELATIVE="wp-content/uploads"`)
- **SPLIT** - size of archive parts (set `false` if you don't want split archives into parts); supports `b` (bytes), `k` (kilobytes) `m` (megabytes) `g` (gigabytes) (ex.: `SPLIT="500m"`)
- **LAST_BACKUPS_PATH** - folder for lists of last backup files (script use its for deleting old files from cloud to avoid errors and unnecessary files with splitting archives into parts; folder create automatically; this folder is in the same folder as the main script with name `last_backups` if this var not set)

5. Add your projects after `declare -A projects` one per row like below:

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

```bash
bash backup.sh <backup_type> <period> <compress_ratio>
```

Compression ratio parameter is opional. It sets to 5 if it not set.

Example:

```bash
bash backup.sh bases daily 7
```

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

    0 0 * * * /bin/bash /path/to/script/backup.sh bases daily # bases backup every day in 00:00
    20 0 * * 1 /bin/bash /path/to/script/backup.sh bases weekly # bases backup every monday in 00:20
    40 0 1 * * /bin/bash /path/to/script/backup.sh bases monthly # bases backup every 1st day every month in 00:40
    0 1 * * 1 /bin/bash /path/to/script/backup.sh files weekly 7 # files backup every monday in 01:00 with changed compression ratio
    0 4 1 * * /bin/bash /path/to/script/backup.sh files monthly 7 # files backup every 1st day every month in 04:00 with changed compression ratio

If you want receive script result to email add below to the top of crontab list (require working MTA on your server)

    MAILTO=name@domain.com

Tested on
---------
- Hetzner Storage Box (WebDav)
- Yandex Disk (WebDav, not recommended for big files)
- Mail.ru Cloud (WebDav)
- DigitalOcean Spaces (S3)

TODO
----
- [ ] add support for others database types backup
- [x] ~~add support for partitioning archives into specified size~~
- [x] ~~add automatically checking/creating folders in cloud~~
- [ ] add logging with rotation
- [ ] validating vars from config file
- [ ] add full support for some special characters, spaces and non latin characters in file names and paths
- [ ] add ability to backup files and databases to own archive
- [ ] add functionality for restore from backups
- [ ] add support for local backup to mounted clouds disks
- [ ] add support for backups via rsync

Changelog
---------

- 29.07.2020 - 1.5.0 - added parameters for excluding folders for specific backup periods
- 17.04.2020 - 1.4.1 - removed "--databases" parameter in mysqldump command for support restore databases to another databases
- 23.11.2019 - 1.4.0 - added support for S3 storages
- 24.10.2019 - 1.3.2 - [bug fixes](https://github.com/zevilz/WebServerCloudBackups/releases/tag/1.3.2)
- 23.10.2019 - 1.3.1 - hidden curl success messages for clean output
- 18.02.2019 - 1.3.0 - added support for sets user for databases backups instead using root user
- 01.03.2018 - 1.2.1 - bug fixes
- 22.02.2018 - 1.2.0 - added support for partitioning archives into specified size, automatically checking/creating folders in cloud, automatically remove slashes in the end of paths in vars to avoid errors, small code refactoring
- 20.02.2018 - 1.1.0 - added support for excluding folders when archiving, small code refactoring, added new vars to config file
- 14.05.2017 - 1.0.2 - added compress ratio parameter
- 13.05.2017 - 1.0.1 - main script code refactoring
- 11.05.2017 - 1.0.0 - released
