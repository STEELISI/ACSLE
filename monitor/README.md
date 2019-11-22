* mkdir /usr/local/src/ttylog
* cp ~aashraya/work_17_April/*.py /usr/local/src/ (copy analyze.py and pre_process.py)
* cp ~aashraya/work_17_April/start_ttylog.sh /usr/local/src/
* cp ~aashraya/work_17_April/ttylog /usr/local/src/ttylog/
* Append 'ForceCommand /usr/local/src/start_ttylog.sh' to '/etc/ssh/sshd_config'
* Append 'python3 /usr/local/src/pre_process.py &' to /usr/local/etc/emulab/rc/rc.testbed
* service sshd restart
* reboot
* As soon as the node reboots, take the snapshot of the image. Do not SSH into the node. First take the screenshot after rebooting.
