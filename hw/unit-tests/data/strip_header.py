import sys
sys.path.append("gen-py")
from parquet.ttypes import PageHeader
from thrift.transport import TTransport
from thrift.protocol import TCompactProtocol
import snappy

with open(sys.argv[1], 'rb') as f:
    data = f.read()

# Parse first page header
transport = TTransport.TMemoryBuffer(data)
protocol = TCompactProtocol.TCompactProtocol(transport)
header = PageHeader()
header.read(protocol)
header_size = transport._buffer.tell()

print(f"Header: {header_size} bytes")
print(f"Compressed: {header.compressed_page_size}")
print(f"Uncompressed: {header.uncompressed_page_size}")

# Extract just this page's compressed data
compressed = data[header_size:header_size + header.compressed_page_size]

with open(sys.argv[1].replace('.bin', '_compressed.bin'), 'wb') as f:
    f.write(compressed)

# Decompress with hadoop snappy
decompressed = snappy.decompress(compressed)

with open(sys.argv[1].replace('.bin', '_decompressed.bin'), 'wb') as f:
    f.write(decompressed)
    
print(f"Done: {len(compressed)} -> {len(decompressed)} bytes")
