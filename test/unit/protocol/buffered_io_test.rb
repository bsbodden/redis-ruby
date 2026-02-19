# frozen_string_literal: true

require_relative "../unit_test_helper"

# Simple fake IO that allows sequencing read_nonblock responses
class FakeIO
  attr_accessor :responses, :write_responses, :closed

  def initialize(responses = [])
    @responses = responses.dup
    @write_responses = []
    @closed = false
    @written = []
  end

  def read_nonblock(_size, *_args, **_kwargs)
    raise IOError, "stream closed" if @responses.empty? && @closed

    r = @responses.shift
    raise r if r.is_a?(Class) && r < Exception
    raise r if r.is_a?(Exception)

    r
  end

  def write_nonblock(data, **_kwargs)
    r = @write_responses.shift
    return r if r

    @written << data
    data.bytesize
  end

  def wait_readable(_timeout = nil)
    r = @responses.shift
    r == :ready ? true : r
  end

  def wait_writable(_timeout = nil)
    r = @write_responses.shift
    r == :ready ? true : r
  end

  def flush; end
  def close = @closed = true
  def closed? = @closed
  def eof? = @responses.empty?
end

class BufferedIOTest < Minitest::Test
  # ============================================================
  # Constructor
  # ============================================================

  def test_initialize_with_defaults
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)

    assert_in_delta(5.0, bio.read_timeout)
    assert_in_delta(5.0, bio.write_timeout)
  end

  def test_initialize_with_custom_timeouts
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io, read_timeout: 10.0, write_timeout: 15.0)

    assert_in_delta(10.0, bio.read_timeout)
    assert_in_delta(15.0, bio.write_timeout)
  end

  def test_initialize_with_custom_chunk_size
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io, chunk_size: 8192)

    assert_instance_of RR::Protocol::BufferedIO, bio
  end
  # ============================================================
  # getbyte
  # ============================================================

  def test_getbyte_returns_byte_value
    io = FakeIO.new(["A"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 65, bio.getbyte
  end

  def test_getbyte_fills_buffer_when_offset_past_end
    io = FakeIO.new(["AB"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 65, bio.getbyte
    assert_equal 66, bio.getbyte
  end

  def test_getbyte_eof_raises_connection_error
    io = FakeIO.new(["A", nil])
    bio = RR::Protocol::BufferedIO.new(io)
    bio.getbyte # consumes 'A'
    assert_raises(RR::ConnectionError) { bio.getbyte }
  end
  # ============================================================
  # gets_chomp
  # ============================================================

  def test_gets_chomp_reads_line
    io = FakeIO.new(["OK\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "OK", bio.gets_chomp
  end

  def test_gets_chomp_with_multiple_lines
    io = FakeIO.new(["hello\r\nworld\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "hello", bio.gets_chomp
    assert_equal "world", bio.gets_chomp
  end

  def test_gets_chomp_fills_until_eol_found
    io = FakeIO.new(["hel", "lo\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "hello", bio.gets_chomp
  end

  def test_gets_chomp_empty_line
    io = FakeIO.new(["\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "", bio.gets_chomp
  end
  # ============================================================
  # gets_integer
  # ============================================================

  def test_gets_integer_positive
    io = FakeIO.new(["42\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 42, bio.gets_integer
  end

  def test_gets_integer_negative
    io = FakeIO.new(["-7\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal(-7, bio.gets_integer)
  end

  def test_gets_integer_zero
    io = FakeIO.new(["0\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 0, bio.gets_integer
  end

  def test_gets_integer_multi_digit
    io = FakeIO.new(["12345\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 12_345, bio.gets_integer
  end

  def test_gets_integer_needing_refill
    io = FakeIO.new(["12", "3\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 123, bio.gets_integer
  end
  # ============================================================
  # read_chomp
  # ============================================================

  def test_read_chomp_reads_exact_bytes
    io = FakeIO.new(["hello\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "hello", bio.read_chomp(5)
  end

  def test_read_chomp_with_remaining_data
    io = FakeIO.new(["foobar\r\nbaz\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "foobar", bio.read_chomp(6)
    assert_equal "baz", bio.gets_chomp
  end
  # ============================================================
  # read
  # ============================================================

  def test_read_exact_bytes
    io = FakeIO.new(["ABCDE"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "ABC", bio.read(3)
  end

  def test_read_multiple_calls
    io = FakeIO.new(["ABCDEF"])
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal "AB", bio.read(2)
    assert_equal "CD", bio.read(2)
    assert_equal "EF", bio.read(2)
  end
  # ============================================================
  # skip
  # ============================================================

  def test_skip_bytes
    io = FakeIO.new(["ABCDEF"])
    bio = RR::Protocol::BufferedIO.new(io)
    result = bio.skip(3)

    assert_nil result
    assert_equal "DEF", bio.read(3)
  end
end

class BufferedIOTestPart2 < Minitest::Test
  # ============================================================
  # Constructor
  # ============================================================

  # ============================================================
  # write
  # ============================================================

  def test_write_data
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 5, bio.write("hello")
  end

  def test_write_partial_then_complete
    io = FakeIO.new
    io.write_responses = [3, 2]
    bio = RR::Protocol::BufferedIO.new(io)

    assert_equal 5, bio.write("hello")
  end

  def test_write_wait_writable
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    seq = sequence("write_seq")
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(:wait_writable).in_sequence(seq)
    mock_io.expects(:wait_writable).with(5.0).returns(true).in_sequence(seq)
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(2).in_sequence(seq)
    bio = RR::Protocol::BufferedIO.new(mock_io)

    assert_equal 2, bio.write("hi")
  end

  def test_write_wait_readable
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    seq = sequence("write_seq")
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(:wait_readable).in_sequence(seq)
    mock_io.expects(:wait_readable).with(5.0).returns(true).in_sequence(seq)
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(2).in_sequence(seq)
    bio = RR::Protocol::BufferedIO.new(mock_io)

    assert_equal 2, bio.write("hi")
  end

  def test_write_timeout_on_writable
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(:wait_writable)
    mock_io.expects(:wait_writable).with(5.0).returns(nil)
    bio = RR::Protocol::BufferedIO.new(mock_io)
    assert_raises(RR::TimeoutError) { bio.write("hi") }
  end

  def test_write_timeout_on_readable
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(:wait_readable)
    mock_io.expects(:wait_readable).with(5.0).returns(nil)
    bio = RR::Protocol::BufferedIO.new(mock_io)
    assert_raises(RR::TimeoutError) { bio.write("hi") }
  end

  def test_write_connection_closed_nil
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    mock_io.expects(:write_nonblock).with("hi", exception: false).returns(nil)
    bio = RR::Protocol::BufferedIO.new(mock_io)
    assert_raises(RR::ConnectionError) { bio.write("hi") }
  end
  # ============================================================
  # flush, close, closed?
  # ============================================================

  def test_flush
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)
    bio.flush
  end

  def test_close
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)
    bio.close

    assert_predicate io, :closed?
  end

  def test_closed_true
    io = FakeIO.new
    io.closed = true
    bio = RR::Protocol::BufferedIO.new(io)

    assert_predicate bio, :closed?
  end

  def test_closed_false
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)

    refute_predicate bio, :closed?
  end
  # ============================================================
  # eof?
  # ============================================================

  def test_eof_when_buffer_consumed_and_io_at_eof
    io = FakeIO.new(["A"])
    bio = RR::Protocol::BufferedIO.new(io)
    bio.getbyte  # consume

    assert_predicate bio, :eof?
  end

  def test_not_eof_when_buffer_has_data
    io = FakeIO.new(["AB"])
    bio = RR::Protocol::BufferedIO.new(io)
    bio.getbyte  # consume only A

    refute_predicate bio, :eof?
  end

  def test_not_eof_when_io_not_at_eof
    io = FakeIO.new(%w[A B])
    bio = RR::Protocol::BufferedIO.new(io)
    bio.getbyte  # consume
    # io still has responses
    refute_predicate bio, :eof?
  end
  # ============================================================
  # with_timeout
  # ============================================================

  def test_with_timeout_sets_and_restores
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io, read_timeout: 5.0)

    assert_in_delta(5.0, bio.read_timeout)

    bio.with_timeout(2.0) do
      assert_in_delta(2.0, bio.read_timeout)
    end

    assert_in_delta(5.0, bio.read_timeout)
  end

  def test_with_timeout_restores_on_exception
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io, read_timeout: 5.0)

    begin
      bio.with_timeout(1.0) do
        raise "test error"
      end
    rescue RuntimeError
      # expected
    end

    assert_in_delta(5.0, bio.read_timeout)
  end
end

class BufferedIOTestPart3 < Minitest::Test
  # ============================================================
  # Constructor
  # ============================================================

  # ============================================================
  # fill_buffer - error handling
  # ============================================================

  def test_fill_buffer_connection_error_on_io_error
    io = FakeIO.new([IOError.new("stream closed")])
    bio = RR::Protocol::BufferedIO.new(io)
    assert_raises(RR::ConnectionError) { bio.getbyte }
  end

  def test_fill_buffer_connection_error_on_econnreset
    io = FakeIO.new([Errno::ECONNRESET.new])
    bio = RR::Protocol::BufferedIO.new(io)
    assert_raises(RR::ConnectionError) { bio.getbyte }
  end

  def test_fill_buffer_connection_closed_eof
    io = FakeIO.new([nil])
    bio = RR::Protocol::BufferedIO.new(io)
    assert_raises(RR::ConnectionError) { bio.getbyte }
  end

  def test_fill_buffer_wait_readable
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    seq = sequence("read_seq")
    mock_io.expects(:read_nonblock).returns(:wait_readable).in_sequence(seq)
    mock_io.expects(:wait_readable).with(5.0).returns(true).in_sequence(seq)
    mock_io.expects(:read_nonblock).returns("A").in_sequence(seq)
    bio = RR::Protocol::BufferedIO.new(mock_io)

    assert_equal 65, bio.getbyte
  end

  def test_fill_buffer_wait_readable_timeout
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    mock_io.expects(:read_nonblock).returns(:wait_readable)
    mock_io.expects(:wait_readable).with(5.0).returns(nil)
    bio = RR::Protocol::BufferedIO.new(mock_io)
    assert_raises(RR::TimeoutError) { bio.getbyte }
  end

  def test_fill_buffer_wait_writable
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    seq = sequence("read_seq")
    mock_io.expects(:read_nonblock).returns(:wait_writable).in_sequence(seq)
    mock_io.expects(:wait_writable).with(5.0).returns(true).in_sequence(seq)
    mock_io.expects(:read_nonblock).returns("B").in_sequence(seq)
    bio = RR::Protocol::BufferedIO.new(mock_io)

    assert_equal 66, bio.getbyte
  end

  def test_fill_buffer_wait_writable_timeout
    mock_io = mock("io")
    mock_io.stubs(:closed?).returns(false)
    mock_io.expects(:read_nonblock).returns(:wait_writable)
    mock_io.expects(:wait_writable).with(5.0).returns(nil)
    bio = RR::Protocol::BufferedIO.new(mock_io)
    assert_raises(RR::TimeoutError) { bio.getbyte }
  end
  # ============================================================
  # Buffer cutoff / large buffer reallocation
  # ============================================================

  def test_fill_buffer_resets_oversized_buffer
    large_data = "x" * 70_000
    io = FakeIO.new([large_data, "A"])
    bio = RR::Protocol::BufferedIO.new(io)
    bio.read(70_000) # consume all
    # Next fill should reallocate buffer (buffer was > BUFFER_CUTOFF)
    assert_equal 65, bio.getbyte
  end
  # ============================================================
  # ensure_remaining
  # ============================================================

  def test_ensure_remaining_fills_when_needed
    io = FakeIO.new(%w[AB CDEF])
    bio = RR::Protocol::BufferedIO.new(io)
    bio.getbyte # consume A
    result = bio.read(4)

    assert_equal "BCDE", result
  end
  # ============================================================
  # Append mode in fill_buffer (non-empty buffer)
  # ============================================================

  def test_fill_buffer_append_mode
    io = FakeIO.new(["hel", "lo\r\n"])
    bio = RR::Protocol::BufferedIO.new(io)
    result = bio.gets_chomp

    assert_equal "hello", result
  end
  # ============================================================
  # read_timeout / write_timeout accessors
  # ============================================================

  def test_read_timeout_accessor
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)
    bio.read_timeout = 10.0

    assert_in_delta(10.0, bio.read_timeout)
  end

  def test_write_timeout_accessor
    io = FakeIO.new
    bio = RR::Protocol::BufferedIO.new(io)
    bio.write_timeout = 15.0

    assert_in_delta(15.0, bio.write_timeout)
  end
end
