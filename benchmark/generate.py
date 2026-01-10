from random import randint
import pyarrow as pa
import pyarrow.parquet as pq
import numpy as np
import sys

def usage():
    print(f"usage: {sys.argv[0]} <data_type> <kind> <factor_low> <factor_high>")
    os.exit(1)

if len(sys.argv) < 4:
    usage()

dt = sys.argv[1]
kind = sys.argv[2]
factor_low = sys.argv[3]
factor_high = sys.argv[4]

match kind:
    case 'bpe':
        # TODO: make this customizable to have customizable bit-width
        base = list(range(16, 32))

    case 'rle':
        base = [1337] * 32

    case _:
        print(f"invlaid kind: {kind}")
        os.exit(2)

match dt:
    case 'uint32':
        typ = pa.uint32()

    case 'int32':
        typ = pa.int32()

    case 'uint64':
        typ = pa.uint64()

    case 'int64':
        typ = pa.int64()

    case _:
        print(f"invlaid data type: {dt}")
        os.exit(3)

factor_low = int(factor_low)
factor_high = int(factor_high)

for factor in range(factor_low, factor_high):
    print(f"scaling with a factor of {factor}, thus multiplying by {2**factor}")
    array = pa.array(base * (2**factor), type=typ)

    data = {f'col': array}
    pq.write_table(pa.table(data), f'data_{factor:0>2}.parquet', data_page_version="1.0", write_page_index=True)
