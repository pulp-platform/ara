Execute the script with the following command:

```bash
python vinsn_trace_gen.py instructions.txt rand_seq.S 6 10 main.c
```

 - instructions.txt is the input file with the list of instructions.
 - rand_seq.S is the output file where the random sequences will be written.
 - 6 is the length of each random sequence (including the initial vsetvli instruction).
 - 10 is the number of random sequences to generate.
 - main.c is the file where the main function and function declarations will be written.