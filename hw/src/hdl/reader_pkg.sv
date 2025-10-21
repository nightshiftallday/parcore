package reader_pkg;
    // Reader configuration parameters
    parameter int NUM_STAGES = 3;
    parameter int NUM_UNITS = 1;
    parameter int WITH_HEADER_READER = 0;

    // Config parameters
    parameter int CONFIG_WIDTH = 48; // must be divisible by 8
    parameter int BUFFER_DEPTH = 128;

    // Header reader parameters
    parameter int HEADER_SIZE_START = 16;
    parameter int HEADER_DATA_WIDTH = 38;

    // Config indices
    parameter RESET_BIT_INDEX = 0;
    parameter PAGE_TYPE_CONFIG_INDEX = 1;
    parameter COMPRESSION_CONFIG_INDEX = 5;
    parameter ENCODING_CONFIG_INDEX = 8;
    parameter BYTE_WIDTH_CONFIG_INDEX = 12;


endpackage
