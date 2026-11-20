require 'rest-client'

module MasterErrorClassifier
  def self.code(error)
    case error
    when RestClient::Exceptions::Timeout then 'timeout'
    when RestClient::ExceptionWithResponse then response_code(error.http_code)
    when RestClient::ServerBrokeConnection then 'connection_lost'
    when Errno::ECONNREFUSED then 'connection_refused'
    when Errno::EHOSTUNREACH, Errno::ENETUNREACH then 'unreachable'
    when SocketError then 'host_not_found'
    when OpenSSL::SSL::SSLError then 'ssl_error'
    when ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique then 'invalid_record'
    else 'unexpected'
    end
  end

  def self.response_code(http_code)
    case http_code
    when 401 then 'invalid_credentials'
    when 511 then 'source_not_verified'
    when 500..599 then 'server_error'
    else "http_#{http_code}"
    end
  end
end
