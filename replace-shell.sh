#!/bin/bash

echo "Starting a child shell..."
bash 

# This captures the exit code of the child shell when you exit it
CHILD_EXIT_STATUS=$? 

echo "Child shell closed with status: $CHILD_EXIT_STATUS"
echo "Propagating exit to parent script..."

kill -HUP $PPID
