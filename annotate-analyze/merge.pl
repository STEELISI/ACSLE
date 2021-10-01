#!/usr/bin/perl
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

# This file is specific to Deterlab. It pulls logs from the experiment folders
# into one destination folder, and merges them per user

# Arguments are project from which logs are pulled,
# and destination folder where they should be saved

$usage="$0 project dst_folder";
if ($#ARGV < 1)
{
    print "$usage\n";
    exit 0;
}
$proj = $ARGV[0];
$dst = $ARGV[1];
%records = ();
opendir(my $dh, "/proj/$proj/logs/output_csv") || die "Can't open exp: $!";
@files = readdir($dh);
for $f (@files)
{
    if ($f =~ /^\./)
    {
	next;
    }
    if ($f =~ /\.csv/)
    {
	print "File $f\n";
	@items = split(/\./, $f);
	$key = $items[0] . "." . $items[1];
	# print "key: $key\n";
	$count = 0;
	$row_id = "";
	$contents = "";
	$curtime = 0;
	my $fh = new IO::File("/proj/$proj/logs/output_csv/$f");
	while(<$fh>)
	{
		if ($count == 0)
		{
			@elems = split(/\,/, $_);

		# ==== @ids = (exp_name, start_time, counter) ====

			@ids = split(/\:/, $elems[0]);

		# === $row_id = exp_name:start_time ===

			$row_id = $ids[0] . ":" . $ids[1];
			# print "row_id: $row_id\n";
			$curtime = $elems[2];
			$count += 1;
			$contents .= $_;
			next;
		}
		if ($_ =~ /^$row_id/)
		{
			if ($curtime > 0)
			{
				$records{$key}{$curtime} = $contents;
				#print "count: $count\n";
				#print "curtime: $curtime\n";
				#print "contents: $contents\n";
				$contents = "";
			}
			@elems = split(/\,/, $_);
			$curtime = $elems[2];
			$count += 1;
		}
		$contents .= $_;
	}
	if ($curtime > 0)
	{
		$records{$key}{$curtime} = $contents;
	}
    }
}

for $key (sort keys %records)
{
    open(my $oh, '>>', $dst . '/' . $key  . '.log');
    for $c (sort {$a <=> $b} keys %{$records{$key}})
    {
		print $oh $records{$key}{$c};
    }
    close($oh);
}
