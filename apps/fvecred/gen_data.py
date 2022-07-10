import random

fw = open("data.txt", 'w')

fw.write("{")
for i in range(2048):
    rand_num = random.randint(-4096, 4096)
    if i == 2047:
        fw.write(str(rand_num) + "}")
    else:
        fw.write(str(rand_num) + ", ")

fw.close()
