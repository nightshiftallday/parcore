from random import randint
import pyarrow as pa
import pyarrow.parquet as pq
import numpy as np

data = {f'col{i}': np.random.randint(0, 1000, 1024, dtype=np.int32) for i in range(3)}
pq.write_table(pa.table(data), 'data.parquet', data_page_version="1.0")

rle_data = {'col0': [i for i in range(10, 20) for _ in range(i)]}
print(rle_data)
pq.write_table(pa.table(rle_data), 'rle_data.parquet', data_page_version="1.0")

bpe_data = {'col0': list(range(10, 20)) * 15}
print(bpe_data)
pq.write_table(pa.table(bpe_data), 'bpe_data.parquet', data_page_version="1.0")


mixed_data = {'col0':
                [i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2 +
                [i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2
             }
print(mixed_data)
pq.write_table(pa.table(mixed_data), 'mixed_data.parquet', data_page_version="1.0")

big_bpe_data = {'col0': list(range(10, 100)) * 5}
pq.write_table(pa.table(big_bpe_data), 'big_bpe_data.parquet', data_page_version="1.0")

def explode_data(data):
    factor = randint(2, 4)
    data = np.repeat(data, factor)
    one_tenth = len(data) // 100
    start = randint(0, one_tenth)
    end = randint(len(data) - one_tenth, len(data))
    factor = randint(3, 4)
    return np.repeat(data[start:end], factor)

huge_data = np.array(mixed_data['col0'])
for _ in range(4):
    huge_data = explode_data(huge_data)

huge = {'col0': huge_data }
print(len(huge_data))
pq.write_table(pa.table(huge), 'huge.parquet', data_page_version="1.0")
