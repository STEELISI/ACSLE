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

#This program starts the script for launching the ttylog logger
#For sending SIGHUP upon exit, we need to set the shell to interacive (-i), login (-l)
#huponexit option needs to be set to send SIGHUP to background process on exit
if [ "$1" = "" ]; then
    bash -l -O huponexit /usr/local/src/start_ttylog.sh
else
    $@;
fi
