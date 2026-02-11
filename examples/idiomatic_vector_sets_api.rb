# frozen_string_literal: true

# Idiomatic Ruby API for Vector Sets
#
# This example demonstrates the modern, Ruby-esque API for working with
# Redis Vector Sets, inspired by popular vector databases like Pinecone,
# Weaviate, and Qdrant.
#
# Prerequisites:
# - Redis 8.0+ with Vector Sets support
# - Run: docker run -d -p 6379:6379 redis:latest

require_relative "../lib/redis_ruby"

redis = RedisRuby.new

puts "=" * 80
puts "Idiomatic Ruby API for Vector Sets"
puts "=" * 80
puts

# ============================================================
# 1. Creating and Configuring Vector Sets
# ============================================================

puts "1. Creating and Configuring Vector Sets"
puts "-" * 80

# Define a vector set with configuration (for documentation)
builder = redis.vector_set("product:embeddings") do
  dimension 384  # Vector dimension
  quantization :binary  # Quantization method
  metadata_schema do
    field :category, type: :string
    field :price, type: :number
    field :in_stock, type: :boolean
  end
end

puts "Created vector set configuration:"
puts "  Key: #{builder.key}"
puts "  Dimension: #{builder.config[:dimension]}"
puts "  Quantization: #{builder.config[:quantization]}"
puts "  Metadata fields: #{builder.config[:metadata_fields].keys.join(', ')}"
puts

# ============================================================
# 2. Adding Vectors with Metadata
# ============================================================

puts "2. Adding Vectors with Metadata"
puts "-" * 80

# Get a chainable proxy for vector operations
vectors = redis.vectors("product:embeddings")

# Add vectors one at a time with method chaining
vectors
  .add("laptop_001", [0.1, 0.2, 0.3] * 128,
       category: "electronics",
       price: 999.99,
       in_stock: true)
  .add("book_001", [0.2, 0.3, 0.4] * 128,
       category: "books",
       price: 19.99,
       in_stock: true)
  .add("headphones_001", [0.15, 0.25, 0.35] * 128,
       category: "electronics",
       price: 149.99,
       in_stock: false)

puts "Added 3 vectors with metadata"
puts "Total vectors: #{vectors.count}"
puts

# Add multiple vectors in batch
vectors.add_many([
  { id: "tablet_001", vector: [0.12, 0.22, 0.32] * 128,
    category: "electronics", price: 499.99, in_stock: true },
  { id: "novel_001", vector: [0.22, 0.32, 0.42] * 128,
    category: "books", price: 24.99, in_stock: true },
  { id: "speaker_001", vector: [0.18, 0.28, 0.38] * 128,
    category: "electronics", price: 299.99, in_stock: true },
])

puts "Added 3 more vectors in batch"
puts "Total vectors: #{vectors.count}"
puts "Vector dimension: #{vectors.dimension}"
puts

# ============================================================
# 3. Retrieving Vectors and Metadata
# ============================================================

puts "3. Retrieving Vectors and Metadata"
puts "-" * 80

# Get a vector by ID
vector_data = vectors.get("laptop_001")
puts "Retrieved vector for laptop_001:"
puts "  Dimension: #{vector_data.length}"
puts "  First 5 values: #{vector_data.first(5).map { |v| format('%.2f', v) }.join(', ')}"
puts

# Get metadata for a vector
metadata = vectors.metadata("laptop_001")
puts "Metadata for laptop_001:"
metadata.each do |key, value|
  puts "  #{key}: #{value}"
end
puts

# Update metadata
vectors.set_metadata("laptop_001", price: 899.99, on_sale: true)
puts "Updated metadata for laptop_001"
updated_metadata = vectors.metadata("laptop_001")
puts "  New price: $#{updated_metadata['price']}"
puts "  On sale: #{updated_metadata['on_sale']}"
puts

# ============================================================
# 4. Vector Similarity Search
# ============================================================

puts "4. Vector Similarity Search"
puts "-" * 80

# Basic similarity search
query_vector = [0.11, 0.21, 0.31] * 128
results = vectors.search(query_vector)
  .limit(3)
  .execute

puts "Top 3 similar items:"
results.each { |id| puts "  - #{id}" }
puts

# Search with similarity scores
results_with_scores = vectors.search(query_vector)
  .limit(3)
  .with_scores
  .execute

puts "Top 3 similar items with scores:"
results_with_scores.each do |id, score|
  puts "  - #{id}: #{format('%.4f', score)}"
end
puts

# ============================================================
# 5. Filtered Vector Search
# ============================================================

puts "5. Filtered Vector Search"
puts "-" * 80

# Search with metadata filtering
electronics_results = vectors.search(query_vector)
  .filter(".category == 'electronics'")
  .limit(5)
  .with_scores
  .execute

puts "Electronics only (filtered search):"
electronics_results.each do |id, score|
  puts "  - #{id}: #{format('%.4f', score)}"
end
puts

# Search with price filter
affordable_results = vectors.search(query_vector)
  .where(".price < 300")
  .limit(5)
  .with_scores
  .with_metadata
  .execute

puts "Affordable items (price < $300):"
affordable_results.each do |id, data|
  puts "  - #{id} (score: #{format('%.4f', data['score'])}):"
  puts "      price: $#{data['attributes']['price']}"
  puts "      category: #{data['attributes']['category']}"
end
puts

# Search with complex filter
in_stock_electronics = vectors.search(query_vector)
  .filter(".category == 'electronics' && .in_stock == true")
  .limit(5)
  .with_scores
  .with_metadata
  .execute

puts "In-stock electronics:"
in_stock_electronics.each do |id, data|
  puts "  - #{id} (score: #{format('%.4f', data['score'])}):"
  puts "      price: $#{data['attributes']['price']}"
  puts "      in_stock: #{data['attributes']['in_stock']}"
end
puts

# ============================================================
# 6. Advanced Search Options
# ============================================================

puts "6. Advanced Search Options"
puts "-" * 80

# Search with exploration factor (ef parameter)
precise_results = vectors.search(query_vector)
  .exploration_factor(200)
  .limit(3)
  .with_scores
  .execute

puts "Search with higher exploration factor (ef=200):"
precise_results.each do |id, score|
  puts "  - #{id}: #{format('%.4f', score)}"
end
puts

# Search with distance threshold
threshold_results = vectors.search(query_vector)
  .threshold(0.5)
  .limit(10)
  .with_scores
  .execute

puts "Search with distance threshold (epsilon=0.5):"
threshold_results.each do |id, score|
  puts "  - #{id}: #{format('%.4f', score)}"
end
puts

# ============================================================
# 7. Vector Set Information
# ============================================================

puts "7. Vector Set Information"
puts "-" * 80

puts "Vector set statistics:"
puts "  Total vectors: #{vectors.count}"
puts "  Dimension: #{vectors.dimension}"
puts

info = vectors.info
puts "Detailed info:"
info.each do |key, value|
  puts "  #{key}: #{value}"
end
puts

# ============================================================
# 8. Cleanup
# ============================================================

puts "8. Cleanup"
puts "-" * 80

# Remove individual vectors
removed = vectors.remove("headphones_001")
puts "Removed headphones_001: #{removed == 1 ? 'success' : 'failed'}"
puts "Remaining vectors: #{vectors.count}"
puts

# Clean up
redis.del("product:embeddings")
redis.close

puts "=" * 80
puts "Example completed!"
puts "=" * 80


# Search with metadata
results_with_metadata = vectors.search(query_vector)
  .limit(3)
  .with_metadata
  .execute

puts "Top 3 similar items with metadata:"
results_with_metadata.each do |id, attrs|
  puts "  - #{id}:"
  attrs.each { |k, v| puts "      #{k}: #{v}" }
end
puts

# Search with both scores and metadata
results_full = vectors.search(query_vector)
  .limit(3)
  .with_scores
  .with_metadata
  .execute

puts "Top 3 similar items with scores and metadata:"
results_full.each do |id, data|
  puts "  - #{id} (score: #{format('%.4f', data['score'])}):"
  data["attributes"].each { |k, v| puts "      #{k}: #{v}" }
end
puts

