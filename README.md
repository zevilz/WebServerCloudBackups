# WebServerCloudBackups [![Version](https://img.shields.io/badge/version-v1.9.2-brightgreen.svg)](https://github.com/zevilz/WebServerCloudBackups/releases/tag/1.9.2)
Automatic backups your web projects bases (MySQL/MariaDB) and files to the clouds via WebDAV or Amazon S3 and to backup servers via SSH (rsync). Supports setting passwords for archives (WebDav/S3) and excluding specified folders.

## Requirements

- curl (for WebDAV)
- [s3cmd](https://s3tools.org/s3cmd) (for S3)
- 7zip archiver (usually **p7zip-rar** **p7zip-full** on deb-based distros)
- connection to backup server via SSH key without passphrase (for ssh)

## Configuring

1. Login server in root user

2. Copy **backup.sh** and **backup.conf** to other directory on your server.

3. Change permissions of **backup.conf** to **600**.

4. Declare main vars in **backup.conf**

- **MYSQL_USER** - MySQL/MariaDB user (min user privileges: `EVENT,LOCK TABLES,SELECT,SHOW DATABASES` on all databases);
- **MYSQL_PASS** - MySQL/MariaDB user password;
- **CLOUD_USER** - login for your cloud (for WebDAV);
- **CLOUD_PASS** - password for your cloud user (for WebDAV);
- **CLOUD_PATH** - full path to cloud folder for WebDAV (ex.: `https://webdav.yandex.ru/Backups/`) or path to S3 spacename (ex.: `s3://myspacename`);
- **CLOUD_PROTO** - cloud protocol (`webdav` or `s3` or `ssh`, default value is `webdav` if empty or undefined);
- **CLOUD_SSH_HOST** - hostname/IP and port of backup server separated by colon (for ssh; ex.: `123.123.123.123`, `123.123.123.123:2222`, `hostname.com:4444`);
- **CLOUD_SSH_HOST_USER** - system username of backup server (for ssh);
- **CLOUD_SSH_HOST_PATH** - full path to backups dir on backups server (for ssh, projects dirs will be created automatically) ;
- **TMP_PATH** - path for temporary files on server (ex.: `/tmp/`);
- **GLOBAL_ARCHIVE_PASS** - global password for created archives (if project password set to `false` it will be used this password. if project password set to `false` and this password set to `false` password not set to project archive.);
- **EXCLUDE** - spaces separated folders to exclude (supports wildcard in folders names, ex.: `EXCLUDE=".svn .git *cache*"`);
- **EXCLUDE_RELATIVE** - relative folders paths to exclude separated by spaces (supports wildcard in paths to folders, ex.: `EXCLUDE_RELATIVE="wp-content/cache templates/*_temp"`);
- **\<PERIOD\>_EXCLUDE** - spaces separated folders to exclude for specific backup period (ex.: `DAILY_EXCLUDE="uploads"`);
- **\<PERIOD\>_EXCLUDE_RELATIVE** - relative folders paths to exclude separated by spaces for specific backup period (ex.: `WEEKLY_EXCLUDE_RELATIVE="wp-content/uploads"`);
- **SPLIT** - size of archive parts (set `false` if you don't want split archives into parts); supports `b` (bytes), `k` (kilobytes) `m` (megabytes) `g` (gigabytes) (ex.: `SPLIT="500m"`);
- **LAST_BACKUPS_PATH** - folder for lists of last backup files (script use its for deleting old files from cloud to avoid errors and unnecessary files with splitting archives into parts; folder create automatically; this folder is in the same folder as the main script with name `last_backups` if this var not set);
- **SCRIPT_LOG_PATH** - full path for logs (directory must be exists and current user must be have permissions for write into it; logging disabled if path not setted);
- **SORT_BACKUPS** (true|false) - sort backups by subdirectories in cloud (`files` for files, `databases` for databases; disabled by default).

Note: relative and not relative lists will be united if using ssh proto.

5. Add your projects after `declare -A projects` one per row like below:

```bash
projects[unique_key]="<project_name> <db_name> <project_folder> <project_archive_password>"
```

Parameters in quotes must be written through spaces and all required.

Parameters:

- **<project_name>** - project name, you **must** create folder with same name in the cloud folder, defined in **CLOUD_PATH**
- **<db_name>** - database name, type **false** if database backup is not required for project
- **<project_folder>** - full path to project folder, type **false** if files backup is not required for project
- **<project_archive_password>** - project archive password, type **false** if password is not required for project archive or using global password, defined in **GLOBAL_ARCHIVE_PASS**

You can specify backup method to project or to files or database separatelly. Just add protocol to project name or database name or files path via colon.

NOTE: you can't use WebDav and S3 protocols together (only WebDav+SSH or S3+SSH). Ability to use all protocols at the same time will be added later.

### Examples

Use default protocol defined in **CLOUD_PROTO** var:

```bash
projects[1]="domain.org false /home/user/www/domain.org false"
projects[2]="domain.com com_db /home/user/www/domain.com 1234"
```

Do backup all project via ssh:

```bash
...
CLOUD_PROTO="webdav"
...
projects[1]="domain.com:ssh com_db /home/user/www/domain.com false"
```

Do backup project database via WebDav and files via default proto (ssh):

```bash
...
CLOUD_PROTO="ssh"
...
projects[1]="domain.com com_db:webdav /home/user/www/domain.com false"
```

Do backup project database via default proto (WebDav) and files via ssh:

```bash
...
CLOUD_PROTO="webdav"
...
projects[1]="domain.com com_db /home/user/www/domain.com:ssh false"
```

## Usage

### Directly in shell

```bash
bash backup.sh <backup_type> <period> <compress_ratio> <enabled_protocol>
```

Compression ratio parameter is opional. It sets to 5 if it not set. It required if you want set another protocol (for backward compatibility).

Examples:

```bash
bash backup.sh bases daily
bash backup.sh files weekly 7
bash backup.sh files weekly 5 ssh
```

Supported backup types:

- `files` - backup projects folder
- `bases` - backup projects bases

Supported periods:

- `hourly` - add "hourly" mark and current hour to archive name (ex.: domain.com_base_hourly_02.7z)
- `daily` - add number and name of the current week day to archive name (ex.: domain.com_files_5_Friday.7z)
- `weekly` - add "weekly" mark to archive name (ex.: domain.com_files_weekly.7z)
- `monthly` - add "monthly" mark to archive name (ex.: domain.com_files_monthly.7z)

Supported compress ratio:

- `0` - without compression
- `1` - fastest
- `3` - fast
- `5` - normal (default) 
- `7` - maximum
- `9` - ultra

Note: better compression ratios with big files can lead to fails. if at an archiving there is a fails that it is necessary to lower compression ratio.

Supported protocols:

- `webdav` - WebDav
- `s3` - Amazon S3
- `ssh` - via rsync (required connection to backup server via ssh key)

Note: by default the script will do backups with all protocols. The script backup only with specified protocol if it set.

### Cron

Add lines in root crontab like below

    10 * * * * /bin/bash /path/to/script/backup.sh bases hourly # bases backup every hour in 10 minutes
    0 0 * * * /bin/bash /path/to/script/backup.sh bases daily # bases backup every day in 00:00
    20 0 * * 1 /bin/bash /path/to/script/backup.sh bases weekly # bases backup every monday in 00:20
    40 0 1 * * /bin/bash /path/to/script/backup.sh bases monthly # bases backup every 1st day every month in 00:40
    0 1 * * 1 /bin/bash /path/to/script/backup.sh files weekly 7 # files backup every monday in 01:00 with changed compression ratio
    0 4 1 * * /bin/bash /path/to/script/backup.sh files monthly 7 # files backup every 1st day every month in 04:00 with changed compression ratio
    0 1 * * 1 /bin/bash /path/to/script/backup.sh files weekly 5 ssh # only files backup via rsync every monday in 01:00

If you want receive script result to email add below to the top of crontab list (require working MTA on your server)

    MAILTO=name@domain.com

## Tested on

- Hetzner Storage Box (WebDav, SSH)
- Yandex Disk (WebDav, not recommended for big files)
- Mail.ru Cloud (WebDav)
- DigitalOcean Spaces (S3)
- backup servers (SSH)

## TODO

- [ ] add support for others database types backup
- [x] ~~add support for partitioning archives into specified size~~
- [x] ~~add automatically checking/creating folders in cloud~~
- [x] ~~add logging~~
- [ ] validating vars from config file
- [x] ~~add full support for some special characters, spaces and non latin characters in file names and paths~~
- [ ] add ability to backup files and databases to own archive
- [ ] add functionality for restore from backups
- [ ] add support for local backup to mounted clouds disks
- [x] ~~add support for backups via rsync~~
- [ ] make package with system daemon and flexible backups customization
- [ ] refactor this sh*t

Changelog
---------

- 23.03.2024 - 1.9.2 - Added `--ignore-missing-args` to rsync for suppress vanished files warnings
- 18.03.2024 - 1.9.1 - Fixed files exclusion with ssh protocol
- 17.02.2024 - 1.9.0 - Added support for sorting backups by subdirectories
- 27.01.2024 - 1.8.1 - [Bugfix with enabled --single-transaction mode](https://github.com/zevilz/WebServerCloudBackups/releases/tag/1.8.1)
- 21.01.2024 - 1.8.0 - added logging, escaping values of sensitive vars, refactoring, bugfixes
- 21.07.2023 - 1.7.0 - [added support for backups via rsync](https://github.com/zevilz/WebServerCloudBackups/releases/tag/1.7.0)
- 14.03.2022 - 1.6.2 - [added new parameters to mysqldump command](https://github.com/zevilz/WebServerCloudBackups/releases/tag/1.6.2) + gzip compression
- 17.12.2020 - 1.6.1 - fixed archive filename for hourly backup period
- 13.12.2020 - 1.6.0 - added hourly backup period
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
