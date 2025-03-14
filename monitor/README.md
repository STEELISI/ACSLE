* clone the repository
* mkdir /usr/local/src/ttylog (Make the directory to store ttylog program)
* cp ACSLE/monitor/analyze.py /usr/local/src/
* cp ACSLE/monitor/pre_process.py /usr/local/src/
* cp ACSLE/monitor/start_ttylog.sh /usr/local/src/
* cp ACSLE/monitor/script.sh /usr/local/src/
* cp ACSLE/monitor/ttylog /usr/local/src/ttylog/
* echo 'ForceCommand /usr/local/src/script.sh "$SSH_ORIGINAL_COMMAND"' >> /etc/ssh/sshd_config (Start 'script.sh' as soon as a user SSH's in)
* echo 'python3 /usr/local/src/pre_process.py &' >> /usr/local/etc/emulab/rc/rc.testbed (Launch 'pre_process.py' at system startup)
* service sshd restart
* reboot
* As soon as the system reboots, take the snapshot of the system. Do not SSH into the node before taking the snapshot.
