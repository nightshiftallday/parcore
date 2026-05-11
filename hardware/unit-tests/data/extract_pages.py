# extract_pages.py
import sys
import pyarrow.parquet as pq

pf = pq.ParquetFile(sys.argv[1])

with open(sys.argv[1], 'rb') as f:
    for i in range(pf.metadata.num_row_groups):
        for j in range(pf.metadata.num_columns):
            col_meta = pf.metadata.row_group(i).column(j)
            
            # Read entire column chunk
            f.seek(col_meta.data_page_offset)
            data = f.read(col_meta.total_compressed_size)
            
            # Just save it - it contains all pages for this column
            with open(sys.argv[1].replace('.parquet', f'_rg{i}_col{j}_chunk.bin'), 'wb') as out:
                out.write(data)

            dict_offset = col_meta.dictionary_page_offset
            data_offset = col_meta.data_page_offset
            if dict_offset is not None:
                # Read only dictionary pages
                size = data_offset - dict_offset
                f.seek(dict_offset)
                dict_data = f.read(size)

                with open(sys.argv[1].replace('.parquet', f'_rg{i}_col{j}_dict.bin'), 'wb') as out:
                    out.write(dict_data)
