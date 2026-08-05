#!/bin/bash
#
#
# Copyright (C) 2018 University of Southern California.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#

# This program starts the ttylog logger
user_groups=$(groups)
exit_flag=1

if command -v sudo > /dev/null 2>&1; then
    sudo="sudo"
else 
    sudo=""
    exit_flag=0 # No sudo group means everyones in the sudo group
fi

for group in $user_groups
do
    if [ "$group" = "root" ] || [ "$group" = "$sudo" ] || [ "$group" = "wheel" ]
    then
        exit_flag=0
        break
    else
        continue
    fi
done

if [ $exit_flag = 1 ]
then
    exec bash
    exit
fi


function clean_up {
        echo
        $sudo bash -c "echo 'END tty_sid:$CNT' >> $LOGPATH"
        PSTRING_KILL=$(ps -o args -p ${PID_CONTCSV} --no-headers 2>/dev/null)
        if [[ $PSTRING_KILL =~ ${CONTCSVPATH} ]]; then
            $sudo kill ${PID_CONTCSV} 2>/dev/null
        fi
        PSTRING_KILL=$(ps -o args -p ${PID_ANNOTATOR} --no-headers 2>/dev/null)
        if [[ $PSTRING_KILL =~ ${ANNOTATORPATH} ]]; then
            $sudo kill ${PID_ANNOTATOR} 2>/dev/null
        fi
        PSTRING_KILL=$(ps -o args -p ${PID_INTERVENTION} --no-headers 2>/dev/null)
        if [[ $PSTRING_KILL =~ ${ANNOTATORPATH} ]]; then
            $sudo kill ${PID_INTERVENTION} 2>/dev/null
        fi
        exit
    }

function start_up {
    
    TTY_CMD=$(tty)
    TTY=${TTY_CMD:5}

    HN=$(cat /proc/sys/kernel/hostname)
    USER=$(whoami)

    $sudo mkdir -p /var/log/ttylog/
    #Checking for the existence for a log file constructed using hostname, project name, and experiment name
    #A log file constructed using just the hostname will also work fine.
    if $sudo [ -e "/tmp/count.$USER" ]; then
        CNT=$($sudo cat /tmp/count.$USER)
        let CNT++
        echo $CNT | $sudo tee /tmp/count.$USER > /dev/null
    #Created a log file consisting of hostname, project name, and experiment name
    #A log file constructed using just the hostname will also work fine.
    else
        $sudo touch /tmp/count.$USER
        $sudo chmod ugo+rw /tmp/count.$USER
        echo "0" > /tmp/count.$USER
        CNT=0
    fi

    export TTY_SID=$CNT
    export TTY_USER=$USER
    LOGPATH=/var/log/ttylog/ttylog.$HN.$USER.$CNT.trace

    $sudo touch $LOGPATH
    $sudo chmod ugo+rw $LOGPATH

    
    echo "starting session w tty_sid:$CNT" >> $LOGPATH
    echo "User prompt is ${PS1@P}" >> $LOGPATH
    echo "Home directory is ${HOME}" >> $LOGPATH

   }
   

if [ -z "$SSH_ORIGINAL_COMMAND" ]; then

    #Kill background processes
    trap clean_up exit

    start_up

    $sudo /usr/local/src/ttylog/ttylog $TTY >> $LOGPATH 2>/dev/null &


    # Annotator requires existence of a CSV file produced by analyze_continuous.py
    # Create a directory for storing CSV's from analyze_continuous.py
    # This directory is wiped off when the experiment is swapped off
    CONTCSVDIR="/var/log/analyze_cont/"
    if ! $sudo [ -d $CONTCSVDIR ]; then
        $sudo mkdir -p $CONTCSVDIR
    fi
    CONTCSVPATH=${CONTCSVDIR}analyze.$USER.$CNT.csv
    $sudo python3 /usr/local/src/analyze_continuous.py ${LOGPATH} ${CONTCSVPATH} 2>/dev/null &
    PID_CONTCSV=$!

    # Create an empty CSV file if no such file exists.
    if ! $sudo [ -f $CONTCSVPATH ]; then
        $sudo touch ${CONTCSVPATH}
    fi

    # Create a directory to for storing output from annotator script
    # This directory is wiped off when the experiment is swapped off
    ANNDIR="/var/log/annotator/"
    if ! $sudo [ -d $ANNDIR ]; then
        $sudo mkdir -p $ANNDIR
    fi
    ANNOTATORPATH=${ANNDIR}annotate.$USER.$CNT
    # This file contains the milestones file
    MILESTONEFILE="/var/log/milestones/milestone_file"
    MILESTONEMESS="/var/log/milestones/milestone_messages"
    if $sudo [ -f $MILESTONEFILE ]; then
        if ! $sudo [ -f ${ANNOTATORPATH} ]; then
            $sudo touch ${ANNOTATORPATH}
        fi
        $sudo perl /usr/local/src/milestones-lbl.pl ${MILESTONEFILE} ${CONTCSVPATH} ${ANNOTATORPATH} 2>/dev/null &
        PID_ANNOTATOR=$!
        $sudo python3 /usr/local/src/intervention.py ${ANNOTATORPATH} ${MILESTONEFILE} ${MILESTONEMESS} 2>/dev/null &
        PID_INTERVENTION=$!
    fi

    bash

elif [ "$(echo ${SSH_ORIGINAL_COMMAND} | grep '^sftp' )" ]; then
    
    /usr/lib/openssh/sftp-server

elif [ "$(echo ${SSH_ORIGINAL_COMMAND} | grep '^scp' )" ]; then

    start_up

    time=`date +%s`

    echo "${SSH_ORIGINAL_COMMAND};$time" >> $LOGPATH
    
    printf "<file copy dialogue>\nEND tty_sid:$CNT\n;$time" >> $LOGPATH
    
    exec ${SSH_ORIGINAL_COMMAND}

elif [ "$(echo ${SSH_ORIGINAL_COMMAND})" ]; then

    start_up

    time=`date +%s`

    echo  "${SSH_ORIGINAL_COMMAND};$time" >> $LOGPATH

    TMPPATH=/tmp/sshcmds.$RANDOM.sh
    $(echo $SSH_ORIGINAL_COMMAND >> $TMPPATH)
    bash $TMPPATH 2>&1 | tee -a $LOGPATH
    printf "END tty_sid:$CNT\n;$time" >> $LOGPATH
    rm -f $TMPPATH

fi
