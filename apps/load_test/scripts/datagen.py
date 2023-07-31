from array import array
import numpy as np

def emit(name, array, alignment='8'):
	print(".global %s" % name)
	print(".balign " + alignment)
	print("%s:" % name)
	bs = array.tobytes()
	for i in range(0, len(bs), 4):
		s = ""
		for n in range(4):
			s += "%02x" % bs[i+3-n]
		print("    .word 0x%s" % s)

def check_segments(seg_data, vec_length, segment_size):
    list_arr = []

    for seg in range(segment_size):
        list_arr.append([])

    for idx in range(vec_length):
        for current_seg in range(segment_size):
            list_arr[current_seg].append(seg_data[idx*segment_size+current_seg])

    return list_arr

num_lanes = 4
vec_length = 64
segment_size = 4
data_type = np.int32

data_to_segment = np.arange(0, vec_length*segment_size, 1, data_type)

check_arry_list = check_segments(data_to_segment, vec_length, segment_size)

emit('originalVec', data_to_segment, alignment=str(num_lanes*8))
for idx in range(segment_size):
    emit('checkArr'+str(idx), np.array(check_arry_list[idx], dtype=data_type), alignment=str(num_lanes*8) )
