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
for group in $user_groups
do
    if [ "$group" = "root" ] || [ "$group" = "sudo" ] || [ "$group" = "wheel" ]
    then
        exit_flag=0
        break
    else
        continue
    fi
done
if [ $exit_flag = 1 ]
then
    bash
    exit
fi

if [ -z "$SSH_ORIGINAL_COMMAND" ]; then

    TTY_CMD=$(tty)
    TTY=${TTY_CMD:5}
    HN=$(cat /var/emulab/boot/nickname)
    HOST=$(echo $HN | awk -F. '{print $(NF - 2)}')
    EXP=$(echo $HN | awk -F. '{print $(NF - 1)}')
    PROJ=$(echo $HN | awk -F. '{print $(NF)}')
    USER=$USER

    sudo mkdir -p /var/log/ttylog/

    if sudo [ -e "/proj/$PROJ/exp/$EXP/count.$HOST" ]; then
        CNT=$(sudo cat /proj/$PROJ/exp/$EXP/count.$HOST)
        let CNT++
        echo $CNT | sudo tee /proj/$PROJ/exp/$EXP/count.$HOST > /dev/null
    else
        sudo touch /proj/$PROJ/exp/$EXP/count.$HOST
        sudo chmod ugo+rw /proj/$PROJ/exp/$EXP/count.$HOST
        echo "0" > /proj/$PROJ/exp/$EXP/count.$HOST
        CNT=$(cat /proj/$PROJ/exp/$EXP/count.$HOST)
    fi

    export TTY_SID=$CNT
    export TTY_USER=$USER
    LOGPATH=/var/log/ttylog/ttylog.$USER.$CNT

    sudo touch $LOGPATH
    sudo chmod ugo+rw $LOGPATH

    echo "starting session w tty_sid:$CNT" >> $LOGPATH
    echo "User prompt is ${USER}@${HOST}" >> $LOGPATH
    echo "Home directory is ${HOME}" >> $LOGPATH

    sudo /usr/local/src/ttylog/ttylog $TTY >> $LOGPATH 2>/dev/null &

    bash
    echo "END tty_sid:$CNT" >> $LOGPATH

elif [ "$(echo ${SSH_ORIGINAL_COMMAND} | grep '^sftp' )" ]; then

    /usr/lib/openssh/sftp-server

elif [ "$(echo ${SSH_ORIGINAL_COMMAND} | grep '^scp' )" ]; then

    exec ${SSH_ORIGINAL_COMMAND}

elif [ "$(echo ${SSH_ORIGINAL_COMMAND})" ]; then

    TMPPATH=/tmp/sshcmds.sh
    $(echo $SSH_ORIGINAL_COMMAND >> $TMPPATH)
    bash $TMPPATH
    rm $TMPPATH

fi
