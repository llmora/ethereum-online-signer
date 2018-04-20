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

    # R1: Ensure that key is encrypted on disk, bail otherwise
    begin
      @@key = Eth::Key.decrypt File.read(settings.keyfile), ""
      raise "Key is stored unencrypted and may have been compromised. To avoid security risks you must always use an encrypted key, exiting."
    rescue RuntimeError => e
    end

    # Unlock key through console
    
    exception = nil

    loop do
      print "[signatory] Enter passphrase to unlock key '#{settings.keyfile}': "
      
      banner_show_time = Time.now.to_f
      
      # R6: Trying to set noecho on a non-TTY will fail
      STDOUT.flush
      begin
        STDIN.noecho(&:get_passphrase)
      rescue  => e
        exception = e
        break
      end
      
      # R5: Ensure the passphrase is not being fed from STDIN by requiring at least one second between the prompt being shown and the passphrase being fed in
      password_entered_time = Time.now.to_f
      
      if(password_entered_time - banner_show_time > 0.5)
        begin
          @@key = Eth::Key.decrypt File.read(settings.keyfile), @@key_passphrase.chomp
        rescue Exception => e
          print "[signatory] Error unlocking key: #{e.message}\n"
        end
      else
        print "[signatory] Passphrase entered too quickly, please wait at least a second after the prompt is shown\n"
      end

      # R2: Remove passphrase from memory as soon as possible
      # Securely read the passphrase and wipe it after use (https://bugs.ruby-lang.org/issues/5741) - you would thing IO#getpass would do this for you
      io = StringIO.new("\0" * @@key_passphrase.bytesize)
      io.read(@@key_passphrase.bytesize, @@key_passphrase)

      break if @@key
    end
    
    if exception != nil
      # TODO: How does rack handle initialisation errors?
      raise exception
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

      # Get destination, amount and nonce
      destination = data[:destination]
      wei = data[:wei].to_i
      nonce = data[:nonce].to_i

      # R3: Transfers are only allowed to predefined target wallets
      # Check that destination is an address and is in our whitelist
      http_error("Transfers to #{destination} are not allowed") if ! settings.destinations.include? destination

      # R4: There is a cap on the maximum amount of currency that can be transferred
      # Check the amount requested is not above the transfer
      http_error("Amount cannot exceed #{settings.transfer_limit_wei} wei") if wei > settings.transfer_limit_wei

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

      # Add transaction to the local audit log

      http_response({transaction: tx.hex, hash: tx.hash}, 200, "Transaction successfully signed")
    else
      http_error("Invalid request")
    end
  end

end
