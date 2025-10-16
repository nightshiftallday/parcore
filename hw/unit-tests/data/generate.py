import pyarrow as pa
import pyarrow.parquet as pq
import numpy as np

data = {f'col{i}': np.random.randint(0, 1000, 1024, dtype=np.int32) for i in range(3)}
pq.write_table(pa.table(data), 'data.parquet')
