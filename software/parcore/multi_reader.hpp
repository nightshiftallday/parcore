#include <parcore/reader.hpp>

namespace parcore {

class MultiReader {
public:
  MultiReader(std::vector<std::shared_ptr<Reader>> readers);

  const metadata::Metadata &metadata() const;

  void enqueue_column_chunk(size_t chunk, size_t column);

  [[nodiscard]] bool has_next_column_chunk();

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk();

private:
  std::vector<std::shared_ptr<Reader>> readers_;

  size_t enqueue_index_ = 0;
  size_t next_index_ = 0;
};

template <typename T, typename... Args>
std::shared_ptr<MultiReader> make_multi_reader(size_t count, Args &&...args) {
  static_assert(std::is_base_of_v<Reader, T>, "T must derive from Reader");

  std::vector<std::shared_ptr<Reader>> readers;
  readers.reserve(count);

  for (size_t i = 0; i < count; ++i) {
    readers.push_back(
        std::make_shared<T>(std::forward<Args>(args)...,
                            static_cast<libstf::stream_t>(i) // decoder = i
                            ));
  }

  return std::make_shared<MultiReader>(std::move(readers));
}

} // namespace parcore
