#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Sorted Sets - Idiomatic Ruby API Examples"
puts "=" * 80

# ============================================================
# Example 1: Gaming Leaderboard
# ============================================================

puts "\nExample 1: Gaming Leaderboard"
puts "-" * 80

leaderboard = redis.sorted_set(:game, :leaderboard)
leaderboard.add(
  alice: 1500,
  bob: 2000,
  charlie: 1800,
  diana: 2200,
  eve: 1650
)

puts "Top 3 players:"
leaderboard.top(3, with_scores: true).each_with_index do |(player, score), index|
  puts "  #{index + 1}. #{player}: #{score.to_i} points"
end

# Player wins a match
puts "\nAlice wins a match (+200 points)!"
leaderboard.increment(:alice, 200)

puts "\nAlice's new rank: ##{leaderboard.reverse_rank(:alice) + 1}"
puts "Alice's score: #{leaderboard.score(:alice).to_i}"

# ============================================================
# Example 2: Priority Queue
# ============================================================

puts "\nExample 2: Priority Queue"
puts "-" * 80

queue = redis.sorted_set(:tasks, :priority)
queue.add(
  "urgent_bug_fix" => 1,
  "feature_request" => 5,
  "documentation" => 10,
  "code_review" => 3,
  "refactoring" => 8
)

puts "Processing tasks by priority:"
3.times do
  task = queue.pop_min
  puts "  - #{task}" if task
end

puts "\nRemaining tasks: #{queue.count}"

# ============================================================
# Example 3: Time-Based Rankings
# ============================================================

puts "\nExample 3: Recent Posts (Time-Based)"
puts "-" * 80

recent_posts = redis.sorted_set(:posts, :recent)

now = Time.now.to_i
recent_posts.add(
  "post:123" => now,
  "post:124" => now - 3600,      # 1 hour ago
  "post:125" => now - 7200,      # 2 hours ago
  "post:126" => now - 86400,     # 1 day ago
  "post:127" => now - 172800     # 2 days ago
)

puts "Most recent 3 posts:"
recent_posts.top(3).each do |post_id|
  puts "  - #{post_id}"
end

# Remove posts older than 1 day
cutoff = now - 86400
removed = recent_posts.remove_by_score(-Float::INFINITY, cutoff - 1)
puts "\nRemoved #{removed} old posts"
puts "Remaining posts: #{recent_posts.count}"

# ============================================================
# Example 4: Score Ranges
# ============================================================

puts "\nExample 4: Student Grades"
puts "-" * 80

grades = redis.sorted_set(:class, :grades)
grades.add(
  alice: 95,
  bob: 78,
  charlie: 88,
  diana: 92,
  eve: 65,
  frank: 82
)

puts "Students with A grades (90-100):"
a_students = grades.by_score(90, 100)
puts "  #{a_students.join(', ')}"

puts "\nStudents with B grades (80-89):"
b_students = grades.by_score(80, 89)
puts "  #{b_students.join(', ')}"

puts "\nStudents who need help (< 70):"
struggling = grades.by_score(0, 69)
puts "  #{struggling.join(', ')}"

# ============================================================
# Example 5: Rank Queries
# ============================================================

puts "\nExample 5: Rank Queries"
puts "-" * 80

scores = redis.sorted_set(:competition, :scores)
scores.add(player1: 100, player2: 200, player3: 150, player4: 175, player5: 225)

puts "Bottom 2 performers:"
scores.bottom(2).each { |player| puts "  - #{player}" }

puts "\nTop 2 performers:"
scores.top(2).each { |player| puts "  - #{player}" }

puts "\nMiddle range (ranks 1-3, 0-indexed):"
scores.range(1..3).each { |player| puts "  - #{player}" }

# ============================================================
# Example 6: Chainable Operations
# ============================================================

puts "\nExample 6: Chainable Operations"
puts "-" * 80

session_scores = redis.sorted_set(:session, SecureRandom.hex(4))
  .add(user1: 10, user2: 20)
  .increment(:user1, 5)
  .decrement(:user2, 3)
  .expire(3600)

puts "Session scores:"
session_scores.to_h.each do |user, score|
  puts "  #{user}: #{score.to_i}"
end
puts "TTL: #{session_scores.ttl} seconds"

# ============================================================
# Example 7: Iteration
# ============================================================

puts "\nExample 7: Iteration"
puts "-" * 80

ratings = redis.sorted_set(:movie, :ratings)
ratings.add(
  "The Matrix" => 4.5,
  "Inception" => 4.8,
  "Interstellar" => 4.7,
  "The Prestige" => 4.3
)

puts "All movies and ratings:"
ratings.each do |movie, rating|
  puts "  #{movie}: #{'⭐' * rating.to_i} (#{rating})"
end

# ============================================================
# Example 8: Conversion Methods
# ============================================================

puts "\nExample 8: Conversion Methods"
puts "-" * 80

favorites = redis.sorted_set(:user, :favorites)
favorites.add(item1: 10, item2: 25, item3: 15)

puts "As array: #{favorites.to_a.inspect}"
puts "As hash: #{favorites.to_h.inspect}"
puts "Count: #{favorites.count}"
puts "Empty? #{favorites.empty?}"

# ============================================================
# Cleanup
# ============================================================

puts "\n" + "=" * 80
puts "Cleaning up..."
redis.del(
  "game:leaderboard",
  "tasks:priority",
  "posts:recent",
  "class:grades",
  "competition:scores",
  "movie:ratings",
  "user:favorites"
)
# Session scores will auto-expire
redis.close
puts "Done!"

