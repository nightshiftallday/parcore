#include <common.h>
#include <arrow/api.h>

#include <CLI/CLI.hpp>

int main(int argc, char **argv) {
    CLI::App app("CPU reader");

    //Inputs 
    std::string file_path;

    app.add_option("file", file_path, "Input file")->required();
    // app.add_option("-c,--count", count, "Number of times")->default_val("5");
    // app.add_option("-n,--name", name, "User name")->default_val("default");

    CLI11_PARSE(app, argc, argv);

    //Fields
    std::unique_ptr<parquet::arrow::FileReader> reader = common::prepareArrowTableReader(file_path);
    std::shared_ptr<arrow::Table> table;

    // Start measurement
    auto start = std::chrono::high_resolution_clock::now();

    // This reads the entire table contained in the file.
    // Afterwards, all data is present and obtainable as raw arrays.
    if (!reader->ReadTable(&table).ok()) {
        std::cerr << "Error reading Parquet table from file " << file_path << std::endl;
        return 1;
    }
    // Stop measurement
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> time = end - start;

    assert(table.get()->num_columns() == 1);
    assert(!reader.get()->properties().use_threads());

    std::cout << time.count() << std::endl;


#ifdef DEBUG
    std::filesystem::path path(file_path);
    std::string file_stem = path.stem().string();

    std::ofstream outfile(file_stem + "CPU_output.txt");


    auto col = table->column(0);
    auto array = col->chunk(0); // std::shared_ptr<arrow::Array>
    auto data_buffer = array->data()->buffers[1];  // [0] is null bitmap, [1] is actual values

    if (!data_buffer) {
        std::cerr << "No value buffer found." << std::endl;
        return 1;
    }

    size_t byte_width = array->type()->byte_width();  // works for fixed-size types
    size_t size = array->length() * byte_width;
    const void* buffer_data = data_buffer->data();

    common::printBuffer(buffer_data, size, byte_width, 8, false);  // Or any config you want
#endif


    return 0;
}