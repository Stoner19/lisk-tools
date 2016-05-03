#!/bin/bash


#Thanks Oliver for these pieces
UNAME=$(uname)
DB_USER=$USER
DB_NAME="lisk_test"
DB_PASS="password"
case "$UNAME" in
"Darwin")
  DB_SUPER=$USER
  ;;
"FreeBSD")
  DB_SUPER="pgsql"
  ;;
"Linux")
  DB_SUPER="postgres"
  ;;
*)
  echo "Error: Failed to detect platform."
  exit 0
  ;;
esac


create_user() {
  stop_lisk &> /dev/null
  drop_database &> /dev/null
  sudo -u $DB_SUPER dropuser --if-exists "$DB_USER" &> /dev/null
  sudo -u $DB_SUPER createuser --createdb "$DB_USER" &> /dev/null
  sudo -u $DB_SUPER psql -d postgres -c "ALTER USER "$DB_USER" WITH PASSWORD '$DB_PASS';" &> /dev/null
  if [ $? != 0 ]; then
    echo "X Failed to create postgres user."
    exit 0
  else
    echo "√ Postgres user created successfully."
  fi
}

drop_database() {
  dropdb --if-exists "$DB_NAME" &> /dev/null
}

create_database() {
  drop_database
  createdb "$DB_NAME" &> /dev/null
  if [ $? != 0 ]; then
    echo "X Failed to create postgres database."
    exit 0
  else
    echo "√ Postgres database created successfully."
  fi
}
#End Thanks Oliver for these pieces

##Backup DB
backup_db() {
  
find backup_location/pg_backup/* -type f -mmin +720 -delete
pg_dump "$DB_NAME" | gzip > backup_location/pg_backup/lisk_backup_block-`curl -s http://localhost:7000/api/loader/status/sync | cut -d: -f5 | cut -d} -f1`.gz  

echo "Backup Complete!"
}

##DB Restore
restore_db() {

echo "Select snapshot to restore or type exit to quit"
select FILENAME in backup_location/pg_backup/*;
        do
        case $FILENAME in
                "$EXIT" )
                echo "Exiting without restore"
                exit
                ;;

                *)
                echo "Restore backup $FILENAME"
                restore_file=$FILENAME
                break
                ;;
        esac
done

bash lisk_home/lisk.sh stop

create_database

gunzip -c $restore_file | psql -q -U "$DB_USER" -d "$DB_NAME" &> /dev/null

echo "Restore Complete!"

bash lisk_home/lisk.sh start

}

##Remote DB Snap
remote_snap() {

echo "Select snapshot to grab or type exit to quit"
remote_servers=("https://downloads.lisk.io/lisk/test/blockchain.db.gz" "https://lisktools.io/backups/lisk_pg_backup.gz")
select SERVER in "${remote_servers[@]}" ;
        do
        case $SERVER in
                "$EXIT" )
                echo "Exiting without restore"
                exit 0
                ;;

                *)
                rm -rf backup_location/pg_backup/blockchain.db.gz &> /dev/null
                rm -rf backup_location/pg_backup/lisk_pg_backup.gz &> /dev/null
                wget $SERVER -P backup_location/pg_backup/
                echo "Grabbed Remote Backup!"
                break
                ;;
        esac
done
restore_db

}

list_backups() {
ls -ltrA backup_location/pg_backup
}

schedule_backups() {
cronjob_line="*/30 * * * * /bin/bash tools_location/Lisk_Management_Tools/liskBackupMan.sh backup"
crontab -l | grep -q liskBackupMan.sh && echo "Backups already scheduled!" || (crontab -u $DB_USER -l; echo "$cronjob_line" ) | crontab -u $DB_USER - | echo "Backups scheduled for every 30 minutes!"
}


case $1 in
"restore")
  restore_db
  ;;
"backup")
  backup_db
  ;;
"list")
  list_backups
  ;;
"schedule")
 schedule_backups
  ;;
"remote")
 remote_snap
 ;;
*)
  echo "Error: Unrecognized command."
  echo ""
  echo "Available commands are: list backup restore schedule remote"
  ;;
esac

