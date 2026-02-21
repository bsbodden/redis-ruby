# frozen_string_literal: true

module RR
  module Connection
    # Callback and SSL configuration support for SSL connections
    #
    # Extracted from SSL to keep class size manageable. Provides:
    # - Connection lifecycle callback registration/dispatch
    # - SSL context creation and certificate configuration
    # - Socket cleanup on error
    module SSLSupport
      VALID_EVENT_TYPES = %i[connected disconnected reconnected error].freeze

      # Register a callback for connection lifecycle events
      #
      # @param event_type [Symbol] Event type (:connected, :disconnected, :reconnected, :error)
      # @param callback [Proc] Callback to invoke when event occurs
      # @return [void]
      # @raise [ArgumentError] if event_type is invalid
      def register_callback(event_type, callback = nil, &block)
        callback ||= block
        raise ArgumentError, "Callback must be provided" unless callback

        unless VALID_EVENT_TYPES.include?(event_type)
          raise ArgumentError, "Invalid event type: #{event_type}. Valid types: #{VALID_EVENT_TYPES.join(", ")}"
        end

        @callbacks[event_type] << callback
      end

      # Deregister a callback for connection lifecycle events
      #
      # @param event_type [Symbol] Event type
      # @param callback [Proc] Callback to remove
      # @return [void]
      def deregister_callback(event_type, callback)
        @callbacks[event_type].delete(callback)
      end

      # Disconnect from the server
      #
      # @return [void]
      def disconnect
        return unless connected?

        trigger_callbacks(:disconnected, {
          type: :disconnected,
          host: @host,
          port: @port,
          timestamp: Time.now,
        })

        close
      end

      private

      # Trigger appropriate callback on successful connection
      def trigger_connect_success
        event_type = @ever_connected ? :reconnected : :connected
        @ever_connected = true
        trigger_callbacks(event_type, { type: event_type, host: @host, port: @port, timestamp: Time.now })
      end

      # Trigger error callback and raise wrapped error
      def trigger_connect_error(err)
        error = wrap_connection_error(err)
        trigger_callbacks(:error, { type: :error, host: @host, port: @port, error: error, timestamp: Time.now })
        raise error
      end

      # Wrap non-ConnectionError exceptions
      def wrap_connection_error(err)
        return err if err.is_a?(ConnectionError)

        ConnectionError.new("Failed to connect to #{@host}:#{@port}: #{err.message}")
      end

      # Trigger callbacks for an event
      def trigger_callbacks(event_type, event_data)
        @callbacks[event_type].each do |callback|
          callback.call(event_data)
        rescue StandardError => e
          warn "Error in #{event_type} callback: #{e.message}"
        end
      end

      # Configure underlying TCP socket
      def configure_tcp_socket
        @tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        @tcp_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)
      end

      # Create SSL context with configured parameters
      def create_ssl_context
        context = OpenSSL::SSL::SSLContext.new
        context.verify_mode = @ssl_params.fetch(:verify_mode) { OpenSSL::SSL::VERIFY_PEER }
        configure_ca_certificates(context)
        configure_client_certificates(context)
        context.ciphers = @ssl_params[:ciphers] if @ssl_params[:ciphers]
        context.min_version = @ssl_params.fetch(:min_version) { OpenSSL::SSL::TLS1_2_VERSION }
        context
      end

      def configure_ca_certificates(context)
        if @ssl_params[:ca_file]
          context.ca_file = @ssl_params[:ca_file]
        elsif @ssl_params[:ca_path]
          context.ca_path = @ssl_params[:ca_path]
        else
          context.set_params(verify_mode: context.verify_mode)
        end
      end

      def configure_client_certificates(context)
        context.cert = @ssl_params[:cert] if @ssl_params[:cert]
        context.key = @ssl_params[:key] if @ssl_params[:key]
      end

      # Check if peer verification is enabled
      def verify_peer?
        @ssl_params.fetch(:verify_mode) { OpenSSL::SSL::VERIFY_PEER } != OpenSSL::SSL::VERIFY_NONE
      end

      # Clean up sockets when connection setup fails
      def cleanup_sockets_on_error
        begin
          @ssl_socket&.close
        rescue StandardError
          nil
        end
        begin
          @tcp_socket&.close
        rescue StandardError
          nil
        end
        @ssl_socket = nil
        @tcp_socket = nil
      end
    end
  end
end
