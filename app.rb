require 'sinatra'
require 'sinatra/config_file'
require 'io/console'
require 'eth'
require 'rest-client'

# Monkey patch so we can get the passphrase from the console with "no echo"

class IO
  def get_passphrase
    sysread(256, EthereumSignerApp::key_passphrase)
  end
end

class EthereumSignerApp < Sinatra::Base
  register Sinatra::ConfigFile
  
  @@key_passphrase = ""
  @@key = nil

  default_options = {
    :transfer_limit_wei => 0,
    :source => nil,
    :destinations => [],
    :keyfile => nil,
    :gas_price => 41_000_000_000,
    :etherscan_api_token => '',
    :network => 'main'
  }

  def self.key_passphrase
    @@key_passphrase
  end
  
  def self.config_error(message)
    fail message
  end
  
  def key_unlocked?
    @@key != nil
  end

  def nonce(address)
  
    api_url = nil
  
    case settings.network
    when 'main'
      api_url = 'https://api.etherscan.io'
    when 'ropsten'
      api_url = 'https://ropsten.etherscan.io'
    when 'kovan'
      api_url = 'https://kovan.etherscan.io'
    when 'rinkeby'
      api_url = 'https://rinkeby.etherscan.io'
    else
      http_error("Invalid network #{network}, please check your configuration", 500)
    end

    response = RestClient::Request.execute(method: :get, url: "#{api_url}/api", payload: { module: "proxy", action: "eth_getTransactionCount", address:  address, tag: "latest", apikey: settings.etherscan_api_token}, ssl_ca_file: 'cacert.pem') { |response, request, result| response }

    if response.code == 200 then
      api_response = JSON.parse(response, :symbolize_names => true)

      if api_response[:jsonrpc] == "2.0" then
        return api_response[:result].to_i(16)
      end

    else
      logger.error "Etherscan API returned non-200 response code for 'eth_getTransactionCount': #{response.code}"
    end
  end

  def http_error(message, status_code = 422)
     logger.error "Error #{status_code}: #{message}"
     halt status_code, { status: "error", message: [message]}.to_json
  end

  def http_response(data, status_code = 200, message = "Ok")
     logger.info "Response #{status_code}: #{message}"
    halt status_code, { status: "ok", message: message, data: data }.to_json
  end
  
  configure do
    enable :logging

    # Load configuration settings
    default_options.each do |k, v|
      set k, v
    end

    config_file "config/settings.yml"

    # Check all configuration parameters are set
    config_error("You must specify a keyfile") if ! settings.keyfile
    config_error("You must specify a source ETH address") if ! settings.source
    config_error("You must specify a list of allowed destinations") if settings.destinations.length == 0
    config_error("You must specify a maximum wei transfer limit") if settings.transfer_limit_wei == 0

    # Unlock key through console
    loop do
      print "[signatory] Enter passphrase to unlock key '#{settings.keyfile}': "
      STDOUT.flush
      STDIN.noecho(&:get_passphrase)
      
      begin
        @@key = Eth::Key.decrypt File.read(settings.keyfile), @@key_passphrase.chomp
      rescue Exception => e
        puts e.message
      end

      # Securely read the passphrase and wipe it after use (https://bugs.ruby-lang.org/issues/5741) - you would thing IO#getpass would do this for you
      io = StringIO.new("\0" * @@key_passphrase.bytesize)
      io.read(@@key_passphrase.bytesize, @@key_passphrase)

      break if @@key
    end
  end

  before do
    content_type 'application/json'
  end
  
  get '/status' do
    http_error("Key is locked, something went really wrong", 500) unless key_unlocked?
    http_response("Key is unlocked, ready to proceed")
  end

  post '/sign' do
    http_error("Key is locked, something went really wrong", 500) unless key_unlocked?

    begin
      data = JSON.parse(request.body.read, symbolize_names: true)
    rescue JSON::ParserError => e
      http_error("Malformed JSON request: #{e}")
    end

    if data
      http_error("Invalid request, missing destination") unless data.key?(:destination)
      http_error("Invalid request, missing wei") unless data.key?(:wei)

      # Get destination and amount
      destination = data[:destination]
      wei = data[:wei].to_i

      # Check that destination is an address and is in our whitelist
      http_error("Transfers to #{destination} are not allowed") if ! settings.destinations.include? destination

      # Check the amount requested is not above the transfer
      http_error("Amount cannot exceed #{settings.transfer_limit_wei} wei") if wei > settings.transfer_limit_wei

      # Get nonce
      nonce = nonce(settings.source) || http_error("Error retrieving nonce", 500)
      
      # Sign transaction
      tx = Eth::Tx.new({
        data: '',
        gas_limit: 21_000,
        gas_price: settings.gas_price,
        nonce: nonce,
        to: destination,
        value: wei
      })

      tx.sign @@key

      http_response({transaction: tx.hex, hash: tx.hash}, 200, "Transaction successfully signed")
    else
      http_error("Invalid request")
    end
  end

end
