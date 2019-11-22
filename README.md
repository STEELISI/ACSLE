# ACSLE

This is the code accompanying our SIGCSE 2020 paper "Using Terminal Histories to Monitor Student Progress on Hands-on Exercises". 

Full paper can be accessed at: http://www.isi.edu/~mirkovic/publications/sigcse2020.pdf

The monitoring code should run on RedHat Linux flavors but may not be 
portable to other OS-es. It uses strace to capture user command line input

The preprocess code is specific to Deterlab in the way it copies files to
output folders. On a different platform you would need to modify the 
destination folders.

The rest of the code should be portable to any platform.

For comments/questions please contact Jelena Mirkovic at sunshine@isi.edu.