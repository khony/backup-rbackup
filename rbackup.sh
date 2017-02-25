#!/bin/bash
FILES=/etc/rbackup/*.conf

[ -d "/usr/share/rbackup" ] || mkdir /usr/share/rbackup
[ -d "/etc/rbackup" ] || mkdir /etc/rbackup

function _help {
    echo "@ rbackup params"
    echo "-i install"
    echo "-e execute"
    echo "-l list all configured"
    echo "-z zabbix auto discovery LLD"
    echo "-c check zabbix routine"
}

function install_rbackup {
    echo "Installing at /usr/bin"
    cp -f $0 /usr/bin/rbackup.sh
    ln -s /usr/bin/rbackup.sh /usr/bin/rbackup 2> /dev/null
    if [ -f "conf/rsync_ext_media.conf "];then
        cp -f conf/rsync_ext_media.conf /etc/rbackup/rsync_ext_media.conf.example 2> /dev/null
    fi
    echo "Done!"
}

function bacula_auto_discovery {
    file="/tmp/file_zabbix_rsync"
    echo -e "{" > $file
    echo -e "\t\"data\":[" >> $file
    first=1
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in $FILES
    do
        if [ $first == 0 ];then
            echo -e "\t," >> $file
        fi
        first=0
        i=`echo $f | rev | cut -d'/' -f 1 | rev`
        echo -e "\t{\"{#RSYNC}\":\"$i\"}" >> $file
    done
    echo -e "\t]" >> $file
    echo -e "}" >> $file
    cat $file
    rm -f $file
    IFS=$SAVEIFS
}

function bacula_check {
    cat /usr/share/rbackup/$*
}

function list_backups {
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in $FILES
    do
        echo "$f"
    done
    IFS=$SAVEIFS
}

function reset_variables {
    unset mail
    unset name
    unset dest
    unset orig
    unset ext_ids
}

function do_backup {
    #set variables
    reset_variables
    source $1
    routine=`echo $1 | rev | cut -d'/' -f 1 | rev`
    log_file="/tmp/$routine.log"
    #pre requisites
    [ -d "$dest" ] || mkdir -p $dest
    #check if already running
    testrsync=`ps aux|grep rsync|grep -v grep`
    if [ "$testrsync" == "" ];then
        echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Init backup $routine" > $log_file
    else
        echo "Backup already running @ $(date +%d/%m/%Y) - $(date +%H:%M)" | mail -s "Backup ($name/Already running)" $mail
        exit 0
    fi

    #check if have to umount $dest
    if [ ! -z ${ext_ids+x} ];then 
        umount $dest 2> /dev/null
        sleep 2
        echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Mounting volume" >> $log_file 
        for i in "${ext_ids[@]}"
        do
            mount $i $dest 2> /dev/null
            if [ $? -eq 0 ]; then
                echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Mounted $i" >> $logfile
            fi
        done
        #check if mounted
        mountpoint $dest
        if [ ! $? -eq 0 ]; then
            echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Not mounted - Error" >> $log_file
            exit 0
        fi
    fi
    
    echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Rsync started from $orig to $dest" >> $log_file
    rsync --delete -av $orig $dest 2>> $log_file
    rsyncstatus=`echo $?`
    data=`date`
    echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Rsync end" >> $log_file

    #umount after backup
    if [ ! -z ${ext_ids+x} ];then 
        umount $dest 2> /dev/null
    fi

    echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Backup ended" >> $log_file

    if [ "$rsyncstatus" == "0" ];then
        #backup ok
        $status="OK"
    else
        #backup com erro
        $status="ERROR"
    fi

    echo "$(date +%s),$rsyncstatus" > /usr/share/rbackup/$routine

    #send e-mail
    if [ -e "$mail" ];then 
        cat $log_file | mail -s "Backup ($name/$status)" $mail
    fi

    #auto-update
    wget "https://raw.githubusercontent.com/khony/backup-rbackup/master/rbackup.sh" -O /tmp/rbackup.sh
    if [ $? -eq 0 ]; then
        chmod +x /tmp/rbackup.sh > /dev/null
        /tmp/rbackup.sh -i > /dev/null
    fi
}

function execute_backup {
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in $FILES;do
        do_backup "$f"
    done
    IFS=$SAVEIFS
}

while getopts zeilhc:d: option
do
        case "${option}"
        in
                z) # bacula auto discovery
                  bacula_auto_discovery
                  exit 0
                  ;;
                c) #bacula check routine
                  bacula_check ${OPTARG}
                  exit 0
                  ;;
                i) #install rbackup
                  install_rbackup
                  ;;
                l) #list backups
                  list_backups
                  exit 0
                  ;;
                d) #dir of backups
                  FILES="${OPTARGS}"
                  execute_backup
                  ;;
                e) #do backups
                  execute_backup
                  ;;
                h)
                  _help
                  ;;
                \?) #do backups
                  echo "-h for help"
                  execute_backup
                  ;;
        esac
done

