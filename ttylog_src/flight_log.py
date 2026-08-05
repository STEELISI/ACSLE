import cmd
import csv
from collections import OrderedDict
import datetime
import sys, re
from termcolor import colored, cprint
import bisect
import os, git, time


class ComRepeater(cmd.Cmd):
    """Simple prompt for repeating commands"""

    prompt = "(flight-log)# "
    intro = """
    This application allows you to see your historical activity.\n
    Additionally, you can select the commands that you want to include in the script.
    New nodes will be swapped in, and your selected commands will be run on those nodes.\n
    Run 'help' command to see which commands you can run\n
    """

    def __init__(self):
        super().__init__()

    def do_list(self, args):
        """\nShow summarized historical activity.\nExamples:\n
        list -> shows summary of all lines
        list 5 -> shows summary of line 5 where 5 is an integer
        list 5 7 -> shows summary of lines between [5,7] where 5 and 7 are integers.
        """
        list_args = args.split()
        if len(list_args) > 2:
            print("The command takes only two arguments")
            return

        for ind in range(len(list_args)):
            try:
                list_args[ind] = int(list_args[ind])
            except ValueError as e:
                print("Please enter only integer arguments")
                return

        csv_obj.display_summarized_rows(*list_args)

    def do_expand(self, args):
        """\nFully expand the lines showing full input and output.\nExamples:\n
        expand -> expand all lines
        expand 5 -> expand line 5 where 5 is an integer
        expand 5 7 -> expand lines between [5,7] where 5 and 7 are integers.
        """
        list_args = args.split()
        if len(list_args) > 2:
            print("The command takes only two arguments")
            return

        for ind in range(len(list_args)):
            try:
                list_args[ind] = int(list_args[ind])
            except ValueError as e:
                print("Please enter only integer arguments")
                return

        csv_obj.expand_rows(*list_args)

    def do_add(self, args):
        """\nAdd lines to the script.\nExamples:\n
        add 5 -> add line 5, where 5 is an integer
        add 5 7 -> add lines between [5,7], where 5 and 7 are integers.
        """
        list_args = args.split()
        if len(list_args) > 2:
            print("The command takes only two arguments")
            return

        for ind in range(len(list_args)):
            try:
                list_args[ind] = int(list_args[ind])
            except ValueError as e:
                print("Please enter only integer arguments")
                return

        csv_obj.add_replay_lines(*list_args)

    def do_remove(self, args):
        """\nRemove lines that were added to the script.\nExamples:\n
        remove 5 -> remove line 5, where 5 is an integer
        remove 5 7 -> remove lines between [5,7], where 5 and 7 are integers.
        """
        list_args = args.split()
        if len(list_args) > 2:
            print("The command takes only two arguments")
            return

        for ind in range(len(list_args)):
            try:
                list_args[ind] = int(list_args[ind])
            except ValueError as e:
                print("Please enter only integer arguments")
                return

        csv_obj.remove_replay_lines(*list_args)

    def do_showscript(self, args):
        """\nShow summary of lines in the script.\n
        """

        csv_obj.display_replay_lines()

    def do_save(self, args):
        """\nCreate a bash script for each node, with the selected commands. Examples:\n
        save /tmp/first/ -> Will create a bash script in '/tmp/first/' directory.
        Script name is flightlog.<epoch_time>.sh
        """
        list_args = args.split()
        if len(list_args) != 1:
            print("The command takes only 1 argument, which is the output directory path\n")
            return

        csv_obj.generate_scripts(*list_args)

    def do_exit(self, arg):
        """Exit the application"""
        print('Exiting')
        return True


class ProcessCSV:

    def __init__(self, exp, proj):
        self.exp_name = None
        self.start_time = None

        # Detect project name with correct capitalization
        arr = os.listdir('/proj/')
        for d in arr:
            if (d.casefold() == proj):
                proj = d
                
        self.git_repo_path = "/proj/"+proj+"/upload_modified_files/" 
        self.max_width_dict = {
            'line_id': 7,
            'node': 10,
            'time': 22,
            'cwd': 20,
            'cmd': 30,
            'output': 30,
            'prompt': 20,
            'commit_hash': 12
        }
        self.colored_dict = {
            'line_id': 'red',
            'node': 'blue',
            'time': 'magenta',
            'cwd': 'yellow',
            'cmd': 'green',
            'output': 'cyan',
            'prompt': 'yellow',
            'commit_hash': 'green'
        }
        self.summary_columns = ['line_id', 'node', 'time', 'cmd', 'output', 'commit_hash']
        self.replay_line_ids = []
        self.csv_dict = OrderedDict()


        arr = os.listdir('/proj/'+proj+"/logs/output_csv")
        counter_row = 0
        timedict = dict()

        for f in sorted(arr):
            if exp.casefold() not in f.casefold():
                continue
            csv_file = '/proj/'+proj+"/logs/output_csv/"+f
            with open(csv_file, 'r', newline='') as inp_csv:
                csv_reader = csv.reader(inp_csv, delimiter=',', quotechar='%')

                # Iterate through every row in CSV
                for row in csv_reader:
                    exp_name_row, start_time_row, crow = row[0].split(":")
                    if self.exp_name is None and self.start_time is None:
                        self.exp_name = exp_name_row
                        self.start_time = start_time_row

                    tempdict = dict()
                    tempdict['line_id'] = str(counter_row)
                    tempdict['rowid'] = row[0]
                    tempdict['node'] = row[1]
                    tempdict['time'] = row[2]
                    tempdict['cwd'] = row[3]
                    tempdict['cmd'] = row[4]
                    tempdict['output'] = row[5]
                    tempdict['prompt'] = row[6]
                    time = int(row[2])
                    
                    while True:
                        if time in timedict:
                            time += 1
                        else:
                            break
                    timedict[time] = tempdict
                

        for i in sorted (timedict):
            self.csv_dict[counter_row] = timedict[i]
            self.csv_dict[counter_row]['line_id'] = str(counter_row)
            counter_row += 1
        self.get_git_hashes() #Jelena return later

    def get_git_hashes(self):
        """Add git commit hashes to the csv_dict dictionary"""

        for key, row_dict in self.csv_dict.items():
            row_dict['commit_hash'] = 'N'

        if self.git_repo_path is None:
            return

        git_repo = None

        try:
            git_repo = git.Repo(self.git_repo_path)
        except git.exc.NoSuchPathError as e:
            print(e)
        except git.exc.InvalidGitRepositoryError as e:
            print(e)

        if git_repo is None:
            return

        # Get chronological list of git commits
        git_repo.commit('master')
        git_commits_list = reversed(list(git_repo.iter_commits()))

        for git_commit in git_commits_list:

            git_commit_msg = git_commit.message
            p = re.compile(r'^Adding files by')
            if not p.match(git_commit_msg):
                continue

            # Parse the git commit message
            # Sample git commit message is 'Adding files by user_name at 1586403844 with command vim test/a.txt on node attacker\n'
            git_commit_split = git_commit_msg.split()[3:]
            index_word_at = git_commit_split.index('at')
            git_user_name = ' '.join(git_commit_split[:index_word_at])
            # Change the splitted git message to ['1586403844', 'with', 'command', 'vim', 'test/a.txt', 'on', 'node', 'attacker']
            git_commit_split = git_commit_split[(index_word_at + 1):]
            git_timestamp = git_commit_split[0]
            git_node = git_commit_split[-1]
            # Change the splitted git message to ['vim', 'test/a.txt']
            git_commit_split = git_commit_split[3:-3]
            git_command = ' '.join(git_commit_split)

            for key, row_dict in self.csv_dict.items():
                row_dict_user = row_dict['prompt'].split('@')[0]
                if (row_dict['rowid'] == git_timestamp):
                    # Get the SHA hash from git commit
                    row_dict['commit_hash'] = git_commit.hexsha


    def display_summarized_rows(self, start_line=None, end_line=None):

        cprint("\nSummary of historic activity\n", 'red', attrs=['underline'])

        for column in self.summary_columns:
            cprint("{}".format(column.ljust(self.max_width_dict[column])), self.colored_dict[column], attrs=['bold', 'reverse'], end='||')

        print()
        print('-'*125)

        if end_line is None and type(start_line) == int:

            if start_line not in self.csv_dict:
                print("Line id", start_line, "does not exist\n")
                return

            row_dict = self.csv_dict[start_line]
            for column_name in self.summary_columns:
                column_value = row_dict[column_name]
                # Change time to human readable time
                column_value = datetime.datetime.fromtimestamp(int(column_value)).strftime('%b-%d-%Y %H:%M:%S') if column_name == 'time' else column_value
                # Shorten the git hash
                column_value = 'Y' if (column_name == 'commit_hash' and column_value != 'N') else column_value
                # Encoding is done to properly print escape characters such as '\n'
                column_value = column_value.encode("unicode_escape").decode("utf-8")
                # Limit the column value to respective maxwidth
                column_value = column_value[:(self.max_width_dict[column_name])]
                cprint("{}".format(column_value.ljust(self.max_width_dict[column_name])), self.colored_dict[column_name], end='||')
            print()
            print()
            return

        print_all = True if start_line is None else False
        for key, row_dict in self.csv_dict.items():

            if print_all or (start_line <= key <= end_line):
                for column_name in self.summary_columns:
                    column_value = row_dict[column_name]
                    # Change time to human readable time
                    column_value = datetime.datetime.fromtimestamp(int(column_value)).strftime(
                        '%b-%d-%Y %H:%M:%S') if column_name == 'time' else column_value
                    # Shorten the git hash
                    column_value = 'Y' if (column_name == 'commit_hash' and column_value != 'N') else column_value
                    # Encoding is done to properly print escape characters such as '\n'
                    column_value = column_value.encode("unicode_escape").decode("utf-8")
                    # Limit the column value to respective maxwidth
                    column_value = column_value[:(self.max_width_dict[column_name])]
                    cprint("{}".format(column_value.ljust(self.max_width_dict[column_name])),
                           self.colored_dict[column_name], end='||')
                print()
        print()

    def expand_rows(self, start_line=None, end_line=None):

        cprint("\nExpanded rows\n", 'cyan', attrs=['bold', 'underline'])
        print('-' * 100)

        if end_line is None and type(start_line) == int:

            if start_line not in self.csv_dict:
                cprint("Line id", start_line, "does not exist")
                return

            cprint("Expanding line {}\n".format(start_line), 'green', attrs=['bold', 'underline'])
            row_dict = self.csv_dict[start_line]
            for field_name, field_value in row_dict.items():
                if (field_name == 'rowid'):
                    continue
                cprint("{}:".format(field_name), self.colored_dict[field_name], attrs=['bold', 'reverse'])
                field_value = datetime.datetime.fromtimestamp(int(field_value)).strftime('%b-%d-%Y %H:%M:%S') if field_name == 'time' else field_value
                cprint("{}\n".format(field_value), self.colored_dict[field_name])

            print()
            return

        print_all = True if start_line is None else False
        for key, row_dict in self.csv_dict.items():

            if print_all or (start_line <= key <= end_line):
                cprint("Expanding line {}\n".format(key), 'green', attrs=['bold', 'underline'])
                for field_name, field_value in row_dict.items():
                    cprint("{}:".format(field_name), self.colored_dict[field_name], attrs=['bold', 'reverse'])
                    field_value = datetime.datetime.fromtimestamp(int(field_value)).strftime(
                        '%b-%d-%Y %H:%M:%S') if field_name == 'time' else field_value
                    cprint("{}\n".format(field_value), self.colored_dict[field_name])
                print('#' * 100)

    def add_replay_lines(self, start_line=None, end_line=None):

        if start_line is None and end_line is None:
            print("Please enter line ids which you want to add to the script")
            return

        if end_line is None and type(start_line) == int:

            if start_line not in self.csv_dict:
                print("Line id", start_line, "does not exist\n")
                return

            # If the line_id is not already present, insert it in the list while maintaining the sorted order
            if start_line not in self.replay_line_ids:
                bisect.insort(self.replay_line_ids, start_line)
            return

        csv_dict_keys = self.csv_dict.keys()
        for line_id in range(start_line, end_line + 1):

            if (line_id in csv_dict_keys) and (line_id not in self.replay_line_ids):
                bisect.insort(self.replay_line_ids, line_id)

    def remove_replay_lines(self, start_line=None, end_line=None):

        if start_line is None and end_line is None:
            print("Please enter line ids which you want to remove from the script")
            return

        if end_line is None and type(start_line) == int:

            if start_line in self.replay_line_ids:
                self.replay_line_ids.remove(start_line)
            else:
                print("Line id", start_line, "does not exist in list of lines in the script\n")
            return

        for line_id in range(start_line, end_line + 1):

            if line_id in self.replay_line_ids:
                self.replay_line_ids.remove(line_id)

    def display_replay_lines(self):

        cprint("\nSummary of lines in the script\n", 'red', attrs=['underline'])

        for column in self.summary_columns:
            cprint("{}".format(column.ljust(self.max_width_dict[column])), self.colored_dict[column], attrs=['bold', 'reverse'], end='||')

        print()
        print('-' * 115)

        for line_id in self.replay_line_ids:

            if line_id not in self.csv_dict:
                continue
            row_dict = self.csv_dict[line_id]
            for column_name in self.summary_columns:
                column_value = row_dict[column_name]
                # Change time to human readable time
                column_value = datetime.datetime.fromtimestamp(int(column_value)).strftime('%b-%d-%Y %H:%M:%S') if column_name == 'time' else column_value
                # Shorten the git hash
                column_value = 'Y' if (column_name == 'commit_hash' and column_value != 'N') else column_value
                # Encoding is done to properly print escape characters such as '\n'
                column_value = column_value.encode("unicode_escape").decode("utf-8")
                # Limit the column value to respective maxwidth
                column_value = column_value[:(self.max_width_dict[column_name])]
                cprint("{}".format(column_value.ljust(self.max_width_dict[column_name])), self.colored_dict[column_name], end='||')
            print()
        print()

    def generate_scripts(self, output_dir='./'):
        """Generate a bash script for each node"""

        if not os.path.isdir(output_dir):
            print("Please specify a directory which exists and you have access to\n")
            return

        # Add a trailing slash to directory
        if output_dir[-1] != '/':
            output_dir = output_dir + '/'

        bash_prompt_string = '#! /bin/bash\nexp=$1\nproj=$2\n\n'
        bash_prompt_string +='if [ "$#" -ne 2 ]; then\n\techo "Usage $0 experiment project"\nfi\n\n'
        base_file_name = 'flight-log.'+ str(int(time.time()))
        
        output_file_name = output_dir + base_file_name + '.sh'

        try:
            output_file_handle = open(output_file_name, 'w')
        except PermissionError as e:
            print("You don't have permission to write to this directory\nPlease specify a directory which exists and you have access to\n")
            return
        except Exception as e:
            print(e)
            return
            
        output_file_handle.write(bash_prompt_string)
             
        for line_id in self.replay_line_ids:
            # Jelena: do something here to detect parallel cmds
            row_dict = self.csv_dict[line_id]
            row_dict_node = row_dict['node']
                   

            # Since we have the directory for each command that was executed
            # We go into that directory using 'cd' and then execute the command
            full_command = "{} {} && {}".format('cd', row_dict['cwd'], row_dict['cmd'])
            output_file_handle.write('ssh -o StrictHostKeyChecking=no ' + row_dict_node + '.$exp.$proj'
                                     + ' "' + full_command + '" &\n')

        output_file_handle.close()

        print("\nGenerated bash scripts in the provided directory\n")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 {} exp proj ".format(sys.argv[0]))
        exit(0)
    exp = sys.argv[1]
    proj = sys.argv[2]
    csv_obj = ProcessCSV(exp, proj)
    repeater_prompt = ComRepeater().cmdloop()
